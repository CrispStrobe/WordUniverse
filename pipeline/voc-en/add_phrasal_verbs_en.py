#!/usr/bin/env python3
"""Phrasal-verb dataset builder for the EN vocabulary DB.

Stage 0 (--extract): pull English phrasal verbs from the normalized
Wiktionary DB (CC-BY-SA 4.0, no NC clause) into a candidate JSONL.

Source signal: Wiktionary's "English phrasal verbs" category plus the
per-particle subcategories ('English phrasal verbs formed with "up"',
etc.). The subcategory name yields the particle directly; the entry
word yields the full phrasal and base verb. Glosses give the meaning,
and the examples table gives license-clean corpus sentences.

Stage 1 (--rank): score candidates by the base verb's own frequency
(reads frequency_json/grade_level already in grundwortschatz_en.db — no
extra dependency), pick a primary kid-friendly meaning, and generate
DISTRACTOR PARTICLES for free by mining which other particles each base
verb really combines with across the dataset. Caps to a K-6 set.

Stage 2 (--grade): LLM grade-leveled example sentences (grades 1-6) +
a kid-friendly meaning paraphrase. Reuses the round-robin LLMClient,
parse_json, response_format and JSONL-checkpoint machinery from
add_llm_examples_en.py (Scaleway / Nebius / Mistral / ...).

Stage 3 (--check): validate + LLM-correct rows where the phrasal verb
is missing from a sentence or a grade is empty.

Stage 4 (--load): write a `phrasal_verbs` side-table into
grundwortschatz_en.db (idempotent rebuild). Re-run after --grade to
fold the LLM examples in; pass --compress to refresh the shipped asset.

Pipeline order:
    --extract  (Wiktionary; local mount or VPS)   [done offline]
    --rank                                          non-LLM
    --load                                          non-LLM (ships fallback data)
    --grade   (env GROQ_API_KEY="" COHERE_API_KEY="" ... )   LLM, run last
    --check                                                  LLM
    --load --compress                               non-LLM (final asset)

Usage:
    python3 add_phrasal_verbs_en.py --extract [--wikt PATH] [--limit N]
    python3 add_phrasal_verbs_en.py --rank [--top N]
    python3 add_phrasal_verbs_en.py --grade [--limit N] [--dry-run]
    python3 add_phrasal_verbs_en.py --check
    python3 add_phrasal_verbs_en.py --load [--compress]
"""
from __future__ import annotations

import argparse
import gzip
import json
import re
import shutil
import sqlite3
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
WIKT_DB_PATH = "/Volumes/backups/code/WiktionaryEN-space/en_wiktionary_normalized.db"
SRC_DB = HERE / "grundwortschatz_en.db"
DB_GZ = REPO / "assets" / "grundwortschatz_en.db.gz"

CANDIDATES_JSONL = HERE / "phrasal_candidates_en.jsonl"
RANKED_JSONL = HERE / "phrasal_ranked_en.jsonl"
GRADE_JSONL = HERE / "phrasal_grade_results_en.jsonl"
CHECK_JSONL = HERE / "phrasal_check_results_en.jsonl"

DEFAULT_TOP = 400  # cap on the K-6 phrasal-verb set
DEFAULT_MAX_PER_BASE = 8  # diversity cap per base verb (get/come/go are prolific)

# Particles we treat as valid phrasal-verb particles. Wiktionary's
# "formed with X" set is broader (includes prepositions like "against");
# we keep the full set but flag the core adverbial particles, which are
# the ones that produce true (non-compositional) phrasal verbs.
CORE_PARTICLES = {
    "up", "down", "in", "out", "on", "off", "away", "back", "over",
    "around", "round", "about", "along", "apart", "aside", "forth",
    "ahead", "together", "through", "across", "by",
}

_CAT_PARTICLE_RE = re.compile(r'English phrasal verbs formed with "(.+?)"')


def _open_wikt(path: str) -> sqlite3.Connection:
    if not Path(path).exists():
        sys.exit(f"ERROR: Wiktionary DB not found: {path}\n"
                 "Pass --wikt or run on the VPS "
                 "(/root/voc-enrich/en_wiktionary_normalized_all.db).")
    return sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=30)


def _particle_categories(c: sqlite3.Connection) -> dict[int, str | None]:
    """Map phrasal-verb category id -> particle ('up', ...) or None (umbrella)."""
    out: dict[int, str | None] = {}
    for cid, name in c.execute(
        "SELECT id, category FROM categories "
        "WHERE category = 'English phrasal verbs' "
        "   OR category LIKE 'English phrasal verbs formed with %'"
    ):
        m = _CAT_PARTICLE_RE.match(name)
        out[cid] = m.group(1) if m else None
    return out


def _clean_gloss(g: str | None) -> str | None:
    g = (g or "").strip()
    # Drop Wiktionary's non-idiomatic "see X, Y" boilerplate senses.
    if not g or g.lower().startswith("used other than figuratively"):
        return None
    return g


def _chunks(seq: list[int], n: int = 900):
    for i in range(0, len(seq), n):
        yield seq[i:i + n]


def _bulk_glosses(c: sqlite3.Connection, ids: list[int]) -> dict[int, list[str]]:
    """entry_id -> ordered, de-duped gloss list (one indexed pass per chunk)."""
    out: dict[int, list[str]] = {}
    for chunk in _chunks(ids):
        ph = ",".join("?" * len(chunk))
        for eid, g in c.execute(
            f"""SELECT s.entry_id, g.gloss_text
                  FROM senses s JOIN glosses g ON g.sense_id = s.id
                 WHERE s.entry_id IN ({ph})
                 ORDER BY s.entry_id, s.sense_index, g.gloss_order""",
            chunk,
        ):
            g = _clean_gloss(g)
            if g and g not in out.setdefault(eid, []):
                out[eid].append(g)
    return out


def _bulk_synonyms(c: sqlite3.Connection, ids: list[int]) -> dict[int, list[str]]:
    out: dict[int, list[str]] = {}
    for chunk in _chunks(ids):
        ph = ",".join("?" * len(chunk))
        for eid, syn in c.execute(
            f"SELECT entry_id, synonym_word FROM synonyms "
            f"WHERE entry_id IN ({ph})",
            chunk,
        ):
            if syn and syn not in out.setdefault(eid, []):
                out[eid].append(syn)
    return out


def _bulk_examples(c: sqlite3.Connection, ids: list[int],
                   cap: int = 3) -> dict[int, list[str]]:
    """entry_id -> up to `cap` example sentences.

    The `examples` table has no index on sense_id, so we map our senses
    to entries first, then scan `examples` exactly once (708k rows ~1-2s)
    rather than per-entry.
    """
    sense_to_entry: dict[int, int] = {}
    for chunk in _chunks(ids):
        ph = ",".join("?" * len(chunk))
        for sid, eid in c.execute(
            f"SELECT id, entry_id FROM senses WHERE entry_id IN ({ph})",
            chunk,
        ):
            sense_to_entry[sid] = eid
    out: dict[int, list[str]] = {}
    for sid, text in c.execute("SELECT sense_id, text FROM examples"):
        eid = sense_to_entry.get(sid)
        if eid is None or not text or not text.strip():
            continue
        lst = out.setdefault(eid, [])
        if len(lst) < cap:
            lst.append(text.strip())
    return out


def extract(wikt_path: str, limit: int | None) -> int:
    c = _open_wikt(wikt_path)
    cat_particle = _particle_categories(c)
    print(f"phrasal-verb categories: {len(cat_particle)}")
    cids = list(cat_particle)
    ph = ",".join("?" * len(cids))

    # entry_id -> set of particles (an entry can sit in several subcats)
    ent_particles: dict[int, set[str]] = {}
    for eid, cid in c.execute(
        f"""SELECT ec.entry_id, ec.category_id
              FROM entry_categories ec JOIN entries e ON e.id = ec.entry_id
             WHERE ec.category_id IN ({ph})
               AND e.lang_code = 'en' AND e.pos = 'verb'""",
        cids,
    ):
        p = cat_particle.get(cid)
        if p:
            ent_particles.setdefault(eid, set()).add(p)

    entry_ids = sorted(ent_particles)
    if limit:
        entry_ids = entry_ids[:limit]
    print(f"distinct EN verb phrasal entries: {len(ent_particles)}"
          + (f" (limited to {len(entry_ids)})" if limit else ""))

    # Set-based bulk fetch (indexed; one pass each) instead of per-entry.
    words: dict[int, str] = {}
    for chunk in _chunks(entry_ids):
        ph2 = ",".join("?" * len(chunk))
        words.update(c.execute(
            f"SELECT id, word FROM entries WHERE id IN ({ph2})", chunk))
    print("  fetching glosses / synonyms / examples in bulk …")
    glosses_by = _bulk_glosses(c, entry_ids)
    synonyms_by = _bulk_synonyms(c, entry_ids)
    examples_by = _bulk_examples(c, entry_ids)

    written = skipped = core = 0
    with CANDIDATES_JSONL.open("w") as fh:
        for eid in entry_ids:
            word = words.get(eid)
            glosses = glosses_by.get(eid, [])
            if not word or not glosses:
                skipped += 1
                continue
            tokens = word.split()
            base_verb = tokens[0] if tokens else word
            particles = sorted(ent_particles[eid])
            # primary particle: prefer a core particle present in the word
            primary = next(
                (t for t in tokens[1:] if t in CORE_PARTICLES),
                next((p for p in particles if p in CORE_PARTICLES),
                     particles[0] if particles else None),
            )
            rec = {
                "phrasal": word,
                "base_verb": base_verb,
                "particle": primary,
                "all_particles": particles,
                "is_core": primary in CORE_PARTICLES,
                "glosses": glosses,
                "synonyms": synonyms_by.get(eid, []),
                "examples": examples_by.get(eid, []),
                "source": "wiktionary",
                "license": "CC-BY-SA-4.0",
            }
            fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
            written += 1
            core += 1 if rec["is_core"] else 0

    print(f"\nwrote {written} candidates -> {CANDIDATES_JSONL.name} "
          f"({skipped} skipped: no usable gloss)")
    print(f"  of which {core} use a core adverbial particle "
          f"(up/down/in/out/...) — the prime game material")
    return 0


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

def _load_jsonl(path: Path) -> list[dict]:
    if not path.exists():
        return []
    out = []
    with path.open() as fh:
        for line in fh:
            line = line.strip()
            if line:
                out.append(json.loads(line))
    return out


def _primary_meaning(glosses: list[str]) -> str:
    """First gloss, simplified to a short kid-readable phrase."""
    g = glosses[0]
    g = re.sub(r"^[Tt]o\s+", "", g)            # drop infinitive "To "
    g = re.split(r"[;.]", g)[0]                # first clause only
    g = re.sub(r"\s*\([^)]*\)", "", g).strip() # drop "(someone/something)"
    return g or glosses[0]


# Copula / auxiliary base verbs whose "phrasal verbs" (be on, have on, ...)
# are mostly compositional and make poor game material — exclude them.
# `kill` is excluded on content grounds (K-6 audience). `die *` is kept —
# "die out/off/away/down" are benign science / sound-fading vocab.
BASE_VERB_STOPLIST = {"be", "have", "kill"}

# Specific phrasal verbs excluded as inappropriate for a K-6 audience.
PHRASAL_STOPLIST = {"do in"}  # = to murder / exhaust

# Pool to pad distractors when the base verb doesn't form enough real
# alternative phrasal verbs. Ordered by general frequency.
_DISTRACTOR_POOL = ["up", "down", "in", "out", "on", "off", "away", "back", "over"]


def _distractors(base_verb: str, correct: str,
                 real_by_base: dict[str, set[str]]) -> list[str]:
    """Up to 3 wrong particles — real phrasal verbs of the same base verb
    first (hardest distractors), then padded from a common pool."""
    chosen: list[str] = []
    for p in _DISTRACTOR_POOL:                 # stable, frequency-ordered
        if p == correct:
            continue
        if p in real_by_base.get(base_verb, set()):
            chosen.append(p)
        if len(chosen) == 3:
            return chosen
    for p in _DISTRACTOR_POOL:
        if p != correct and p not in chosen:
            chosen.append(p)
        if len(chosen) == 3:
            break
    return chosen


# ---------------------------------------------------------------------------
# Stage 1 — rank / filter (non-LLM)
# ---------------------------------------------------------------------------

def rank(top: int, max_per_base: int) -> int:
    cands = _load_jsonl(CANDIDATES_JSONL)
    if not cands:
        sys.exit(f"No candidates — run --extract first ({CANDIDATES_JSONL.name}).")

    # base verb -> set of core particles it really forms phrasal verbs with
    real_by_base: dict[str, set[str]] = {}
    for r in cands:
        if r["is_core"] and r["particle"]:
            real_by_base.setdefault(r["base_verb"], set()).add(r["particle"])

    con = sqlite3.connect(SRC_DB)
    con.row_factory = sqlite3.Row
    # base verb -> (word_id, grade_level, zipf, word_type)
    base_info: dict[str, tuple[int, int | None, float, str | None]] = {}

    def lookup(bv: str):
        if bv in base_info:
            return base_info[bv]
        row = con.execute(
            "SELECT id, grade_level, frequency_json, word_type FROM words "
            "WHERE lower(word) = ? ORDER BY id LIMIT 1", (bv.lower(),)
        ).fetchone()
        info = None
        if row:
            zipf = 0.0
            if row["frequency_json"]:
                try:
                    zipf = float(json.loads(row["frequency_json"]).get("zipf") or 0)
                except (json.JSONDecodeError, TypeError, ValueError):
                    zipf = 0.0
            info = (row["id"], row["grade_level"], zipf, row["word_type"])
        base_info[bv] = info
        return info

    ranked: list[dict] = []
    drop_noncore = drop_nobase = drop_aux = drop_shape = drop_notverb = 0
    for r in cands:
        if not r["is_core"]:
            drop_noncore += 1
            continue
        # require a real "verb + particle" shape (drops single-word entries
        # like 'up'/'about' that landed in the phrasal-verb category)
        if len(r["phrasal"].split()) < 2:
            drop_shape += 1
            continue
        if (r["base_verb"].lower() in BASE_VERB_STOPLIST
                or r["phrasal"].lower() in PHRASAL_STOPLIST):
            drop_aux += 1
            continue
        info = lookup(r["base_verb"])
        if info is None:                       # base verb not in curriculum DB
            drop_nobase += 1
            continue
        word_id, base_grade, zipf, word_type = info
        if word_type != "verb":                # 'one up', 'about ...' etc.
            drop_notverb += 1
            continue
        grade_band = min(6, max(base_grade or 3, 3))  # phrasal verbs are grade 3+
        ranked.append({
            "phrasal": r["phrasal"],
            "base_verb": r["base_verb"],
            "particle": r["particle"],
            "word_id": word_id,
            "meaning": _primary_meaning(r["glosses"]),
            "senses": r["glosses"][:3],
            "distractors": _distractors(r["base_verb"], r["particle"], real_by_base),
            "wiktionary_examples": r["examples"][:3],
            "synonyms": r["synonyms"][:5],
            "grade_band": grade_band,
            "base_zipf": round(zipf, 2),
            "source": "wiktionary",
            "license": "CC-BY-SA-4.0",
        })
    con.close()

    # Dedupe by phrasal (a phrasal verb can have several Wiktionary entries;
    # keep the first / highest-zipf one) so the game never repeats a verb.
    ranked.sort(key=lambda x: x["base_zipf"], reverse=True)
    seen_phrasal: set[str] = set()
    ranked = [r for r in ranked
              if r["phrasal"].lower() not in seen_phrasal
              and not seen_phrasal.add(r["phrasal"].lower())]

    # Diversity-aware capping: a few base verbs (get/come/go) form dozens of
    # phrasal verbs and would otherwise swamp the set. Pass 1 takes up to
    # max_per_base of each (zipf order); pass 2 backfills any remaining slots
    # from the leftovers so we still hit `top`.
    per_base: dict[str, int] = {}
    capped, leftovers = [], []
    for r in ranked:
        if len(capped) >= top:
            break
        bv = r["base_verb"]
        if per_base.get(bv, 0) < max_per_base:
            per_base[bv] = per_base.get(bv, 0) + 1
            capped.append(r)
        else:
            leftovers.append(r)
    backfilled = 0
    for r in leftovers:
        if len(capped) >= top:
            break
        capped.append(r)
        backfilled += 1

    with RANKED_JSONL.open("w") as fh:
        for r in capped:
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")

    print(f"candidates: {len(cands)}")
    print(f"  dropped {drop_noncore} non-core (prepositional, not a true particle)")
    print(f"  dropped {drop_shape} not 'verb + particle' shape (single-word entries)")
    print(f"  dropped {drop_aux} with copula/auxiliary base verb (be/have)")
    print(f"  dropped {drop_nobase} whose base verb is not in the curriculum DB")
    print(f"  dropped {drop_notverb} whose base word is not a verb (one up, ...)")
    distinct_bases = len({r["base_verb"] for r in capped})
    print(f"  ranked {len(ranked)} -> kept {len(capped)} by base-verb zipf "
          f"(--top {top}, --max-per-base {max_per_base})")
    print(f"  {distinct_bases} distinct base verbs in the kept set "
          f"({backfilled} slots backfilled past the per-base cap)")
    if len(ranked) > len(capped):
        print(f"  NOTE: {len(ranked) - len(capped)} ranked PVs dropped below the cap")
    print(f"wrote {RANKED_JSONL.name}")
    return 0


# ---------------------------------------------------------------------------
# Stage 2 — LLM grade-leveled examples (run last; needs API keys)
# ---------------------------------------------------------------------------

PHRASAL_GRADE_SYSTEM = """\
You are an English teacher (grades 1-6). You are given ONE English phrasal verb \
and its meaning.

Task: write exactly 2 example sentences per grade level (1-6), plus a short \
kid-friendly definition of the phrasal verb.

Rules:
- The phrasal verb MUST appear in every sentence (verb may be inflected, e.g. \
"give up" -> "gave up", "gives up"; keep the particle).
- Use the given meaning, not another meaning of the words.
- Grade 1-2: max 8 words; Grade 3-4: max 11 words; Grade 5-6: max 14 words.
- Simple everyday language, age-appropriate (no violence, alcohol, politics).
- Increase difficulty across grades. Never refuse.

Reply ONLY with valid JSON (no Markdown):
{"meaning_kid": "<short kid-friendly definition>", "grade_examples": \
{"1": ["S1","S2"], "2": ["S1","S2"], "3": ["S1","S2"], "4": ["S1","S2"], \
"5": ["S1","S2"], "6": ["S1","S2"]}}"""

# Phrasal-verb sentences run a little longer than single-word ones.
PHRASAL_MAX_WORDS = {"1": 8, "2": 8, "3": 11, "4": 11, "5": 14, "6": 14}
_GRADE_KEYS = ("1", "2", "3", "4", "5", "6")


def _llm_client():
    """Build an LLMClient that adds OpenRouter to the inherited round-robin
    WITHOUT modifying the shared add_llm_examples_en.py. nebius / scaleway /
    groq come from the base PROVIDER_TABLE; OpenRouter is appended here.
    Clear unused keys at the env, e.g.:
        env CEREBRAS_API_KEY="" MISTRAL_API_KEY="" COHERE_API_KEY="" ...
    """
    from add_llm_examples_en import LLMClient as _BaseLLMClient

    class _PhrasalLLMClient(_BaseLLMClient):
        PROVIDER_TABLE = _BaseLLMClient.PROVIDER_TABLE + [
            (
                "OPENROUTER_API_KEY",
                "https://openrouter.ai/api/v1",
                "meta-llama/llama-3.3-70b-instruct",
                "meta-llama/llama-3.3-70b-instruct",
            ),
        ]

    return _PhrasalLLMClient()


def _phrasal_present(sentence: str, phrasal: str) -> bool:
    """Loose check: the particle appears as a whole word (the verb may be
    inflected, so we don't insist on the exact base form)."""
    s = sentence.lower()
    particle = phrasal.split()[-1]
    return re.search(rf"\b{re.escape(particle)}\b", s) is not None


def _valid_phrasal_block(block, phrasal: str):
    if not isinstance(block, dict):
        return None
    out = {}
    for g in _GRADE_KEYS:
        sents = block.get(g) or []
        if not isinstance(sents, list):
            return None
        good = [
            s.strip() for s in sents
            if isinstance(s, str) and s.strip()
            and len(s.split()) <= PHRASAL_MAX_WORDS[g] + 1
            and _phrasal_present(s, phrasal)
        ]
        if not good:
            return None
        out[g] = good[:2]
    return out


def run_grade(limit: int | None, dry_run: bool) -> int:
    from add_llm_examples_en import parse_json, load_dotenv
    load_dotenv()

    rows = _load_jsonl(RANKED_JSONL)
    if not rows:
        sys.exit(f"No ranked rows — run --rank first ({RANKED_JSONL.name}).")

    done = {r["phrasal"] for r in _load_jsonl(GRADE_JSONL)}
    if done:
        print(f"  resume: {len(done)} already in {GRADE_JSONL.name}")
    todo = [r for r in rows if r["phrasal"] not in done]
    if limit:
        todo = todo[:limit]
    print(f"  to grade: {len(todo)} phrasal verbs")

    if dry_run:
        for r in todo:
            print(f"  [dry-run] would grade {r['phrasal']!r} "
                  f"(meaning: {r['meaning'][:40]})")
        print(f"  [dry-run] {len(todo)} calls; providers not contacted.")
        return 0

    llm = _llm_client()
    ok = bad = 0
    for i, r in enumerate(todo, 1):
        user = (f'Phrasal verb: "{r["phrasal"]}"\n'
                f'Meaning: {r["meaning"]}')
        raw = llm.call(PHRASAL_GRADE_SYSTEM, user, mode="fill")
        data = parse_json(raw) if raw else None
        block = _valid_phrasal_block((data or {}).get("grade_examples"),
                                     r["phrasal"]) if isinstance(data, dict) else None
        if not block:
            bad += 1
            llm.record_invalid()
            continue
        rec = {
            "phrasal": r["phrasal"],
            "meaning_kid": str((data.get("meaning_kid") or r["meaning"])).strip(),
            "grade_examples": block,
            "provider": getattr(llm._tls, "last_provider", None),
        }
        with GRADE_JSONL.open("a") as jf:
            jf.write(json.dumps(rec, ensure_ascii=False) + "\n")
        ok += 1
        if i % 25 == 0:
            print(f"    {i}/{len(todo)}  ok={ok} bad={bad}")
    if llm:
        llm.print_stats()
    print(f"graded ok={ok} bad={bad} -> {GRADE_JSONL.name}")
    return 0


# ---------------------------------------------------------------------------
# Stage 3 — validate + LLM-correct (run after --grade)
# ---------------------------------------------------------------------------

def run_check(dry_run: bool) -> int:
    from add_llm_examples_en import parse_json, load_dotenv
    load_dotenv()

    graded = {r["phrasal"]: r for r in _load_jsonl(GRADE_JSONL)}
    if not graded:
        sys.exit(f"Nothing to check — run --grade first ({GRADE_JSONL.name}).")
    meaning_by = {r["phrasal"]: r["meaning"] for r in _load_jsonl(RANKED_JSONL)}

    done = {r["phrasal"] for r in _load_jsonl(CHECK_JSONL)}
    # rows whose stored block is now invalid (e.g. <2 sentences / missing PV)
    todo = [
        r for ph, r in graded.items()
        if ph not in done
        and not all(len(r["grade_examples"].get(g, [])) >= 2 for g in _GRADE_KEYS)
    ]
    print(f"  rows needing correction: {len(todo)}")
    if not todo:
        print("  all graded rows already complete.")
        return 0

    if dry_run:
        for r in todo:
            print(f"  [dry-run] would correct {r['phrasal']!r}")
        print(f"  [dry-run] {len(todo)} calls; providers not contacted.")
        return 0

    llm = _llm_client()
    fixed = 0
    for r in todo:
        ph = r["phrasal"]
        user = (f'Phrasal verb: "{ph}"\nMeaning: {meaning_by.get(ph, "")}\n'
                f'Current sentences (fill gaps, fix wrong ones, keep good ones):\n'
                f'{json.dumps(r["grade_examples"], ensure_ascii=False)}')
        raw = llm.call(PHRASAL_GRADE_SYSTEM, user, mode="fill")
        data = parse_json(raw) if raw else None
        block = _valid_phrasal_block((data or {}).get("grade_examples"),
                                     ph) if isinstance(data, dict) else None
        rec = {"phrasal": ph,
               "grade_examples": block or r["grade_examples"],
               "ok": bool(block)}
        with CHECK_JSONL.open("a") as jf:
            jf.write(json.dumps(rec, ensure_ascii=False) + "\n")
        fixed += 1 if block else 0
    if llm:
        llm.print_stats()
    print(f"corrected {fixed}/{len(todo)} -> {CHECK_JSONL.name}")
    return 0


# ---------------------------------------------------------------------------
# Stage 4 — load into grundwortschatz_en.db (non-LLM, idempotent)
# ---------------------------------------------------------------------------

_CREATE_TABLE = """
CREATE TABLE phrasal_verbs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    word_id INTEGER,
    phrasal TEXT NOT NULL,
    base_verb TEXT NOT NULL,
    particle TEXT NOT NULL,
    meaning TEXT,
    senses_json TEXT,
    distractors_json TEXT,
    examples_json TEXT,
    wiktionary_examples_json TEXT,
    synonyms_json TEXT,
    grade_band INTEGER,
    base_zipf REAL,
    source TEXT,
    license TEXT,
    FOREIGN KEY(word_id) REFERENCES words(id) ON DELETE CASCADE
)
"""


def load(compress: bool) -> int:
    ranked = _load_jsonl(RANKED_JSONL)
    if not ranked:
        sys.exit(f"No ranked rows — run --rank first ({RANKED_JSONL.name}).")

    # Fold in LLM results if present (check overrides grade).
    grade_by = {r["phrasal"]: r for r in _load_jsonl(GRADE_JSONL)}
    for r in _load_jsonl(CHECK_JSONL):
        if r.get("ok") and r["phrasal"] in grade_by:
            grade_by[r["phrasal"]]["grade_examples"] = r["grade_examples"]

    con = sqlite3.connect(SRC_DB)
    con.execute("DROP TABLE IF EXISTS phrasal_verbs")
    con.execute(_CREATE_TABLE)
    con.execute("CREATE INDEX IF NOT EXISTS idx_phrasal_word "
                "ON phrasal_verbs(word_id)")

    with_llm = 0
    for r in ranked:
        g = grade_by.get(r["phrasal"])
        examples = g["grade_examples"] if g else {}
        meaning = (g.get("meaning_kid") if g else None) or r["meaning"]
        if g:
            with_llm += 1
        con.execute(
            """INSERT INTO phrasal_verbs
               (word_id, phrasal, base_verb, particle, meaning, senses_json,
                distractors_json, examples_json, wiktionary_examples_json,
                synonyms_json, grade_band, base_zipf, source, license)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (r["word_id"], r["phrasal"], r["base_verb"], r["particle"], meaning,
             json.dumps(r["senses"], ensure_ascii=False),
             json.dumps(r["distractors"]),
             json.dumps(examples, ensure_ascii=False),
             json.dumps(r["wiktionary_examples"], ensure_ascii=False),
             json.dumps(r["synonyms"], ensure_ascii=False),
             r["grade_band"], r["base_zipf"], r["source"], r["license"]),
        )
    con.commit()
    n = con.execute("SELECT count(*) FROM phrasal_verbs").fetchone()[0]
    con.close()
    print(f"loaded {n} phrasal verbs into {SRC_DB.name} "
          f"({with_llm} with LLM grade examples, "
          f"{n - with_llm} with Wiktionary-example fallback only)")

    if compress:
        if not DB_GZ.parent.exists():
            sys.exit(f"asset dir missing: {DB_GZ.parent}")
        print(f"compressing -> {DB_GZ}")
        with SRC_DB.open("rb") as fi, gzip.open(DB_GZ, "wb", compresslevel=9) as fo:
            shutil.copyfileobj(fi, fo)
        print(f"  {DB_GZ.stat().st_size // 1024} KB written")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Phrasal-verb dataset builder (EN)")
    ap.add_argument("--extract", action="store_true",
                    help="Stage 0: extract candidates from Wiktionary")
    ap.add_argument("--rank", action="store_true",
                    help="Stage 1: rank/filter to a K-6 set (non-LLM)")
    ap.add_argument("--grade", action="store_true",
                    help="Stage 2: LLM grade-leveled examples (needs API keys)")
    ap.add_argument("--check", action="store_true",
                    help="Stage 3: validate + LLM-correct")
    ap.add_argument("--load", action="store_true",
                    help="Stage 4: load phrasal_verbs table into the DB")
    ap.add_argument("--wikt", default=WIKT_DB_PATH, help="Wiktionary DB path")
    ap.add_argument("--top", type=int, default=DEFAULT_TOP,
                    help=f"cap for --rank (default {DEFAULT_TOP})")
    ap.add_argument("--max-per-base", type=int, default=DEFAULT_MAX_PER_BASE,
                    help=f"diversity cap per base verb (default {DEFAULT_MAX_PER_BASE})")
    ap.add_argument("--compress", action="store_true",
                    help="with --load: refresh assets/grundwortschatz_en.db.gz")
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if args.extract:
        return extract(args.wikt, args.limit)
    if args.rank:
        return rank(args.top, args.max_per_base)
    if args.grade:
        return run_grade(args.limit, args.dry_run)
    if args.check:
        return run_check(args.dry_run)
    if args.load:
        return load(args.compress)
    ap.print_help()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
