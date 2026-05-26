"""Generate and/or review English example sentences via LLM (multi-provider).

Modes (combinable):
  --fill      For each word with no examples: generate 2–3 child-appropriate sentences.
              Single-sense → llm_examples; multi-sense → sense_examples.
  --grade     For each word: generate 2 sentences per school grade (1–6),
              stored as grade_examples {"1": [...], ..., "6": [...]}.
              Sentences increase in difficulty — app picks by learner grade level.
  --review    For each word with tatoeba_examples: rate child-appropriateness (1–5).
              Sentences scored ≤ 2 are replaced via llm_examples.
  --correct   Send full entry JSON to a capable LLM for semantic/definition
              improvement. Only allowlisted fields are written back; corrupt
              JSON or unexpected types are silently dropped (data-safe).
  --check     Review grade_examples: fix grammar/semantics, fill empty grades.
              Default: only words with structural gaps.
  --check-all Like --check but reviews every graded word.
  --cleanup   Wipe grade_examples with structural gaps (--wipe-partials: also purge JSONL).

Providers (round-robin, keys from ../../.env):
  1. Groq        (GROQ_API_KEY)
  2. Cerebras    (CEREBRAS_API_KEY)
  3. Nebius      (NEBIUS_API_KEY)
  4. Scaleway    (SCALEWAY_API_KEY)
  5. Mistral     (MISTRAL_API_KEY)
  6. Cohere      (COHERE_API_KEY)
  7. Anthropic   (ANTHROPIC_API_KEY)  direct fallback

Usage:
  python add_llm_examples_en.py [--fill] [--grade] [--review] [--correct]
                                 [--db grundwortschatz_en.db] [--dry-run]
                                 [--limit N] [--batch-size N] [--no-compress]
                                 [--workers N]
"""

from __future__ import annotations

import argparse
import gzip
import json
import os
import shutil
import sqlite3
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
GRADE_JSONL = HERE / "grade_results_en.jsonl"
CHECK_JSONL  = HERE / "check_results_en.jsonl"

def _find_env_file() -> Path:
    for candidate in [
        HERE / ".env",
        REPO / ".env",
        REPO.parent / ".env",
        Path.home() / ".env",
    ]:
        if candidate.exists():
            return candidate
    return HERE / ".env"
ENV_FILE = _find_env_file()

DEFAULT_DB = HERE / "grundwortschatz_en.db"
WORK_DB    = Path("/tmp/dbpatch_llm_en/working.db")
DB_GZ      = REPO / "assets" / "grundwortschatz_en.db.gz"

DEFAULT_BATCH       = 6
MAX_SENTENCE_WORDS  = 12
MULTI_SENSE_MIN     = 2
REVIEW_THRESHOLD    = 2
RATE_LIMIT_COOLDOWN = 60


# ---------------------------------------------------------------------------
# .env loader
# ---------------------------------------------------------------------------

def load_dotenv() -> None:
    if not ENV_FILE.exists():
        return
    with ENV_FILE.open() as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, _, v = line.partition("=")
            k = k.strip()
            v = v.strip().strip('"').strip("'")
            if k and k not in os.environ:
                os.environ[k] = v


# ---------------------------------------------------------------------------
# Multi-provider LLM client with cooldown round-robin
# ---------------------------------------------------------------------------

class LLMClient:
    PROVIDER_TABLE: list[tuple[str, str, str, str]] = [
        (
            "GROQ_API_KEY",
            "https://api.groq.com/openai/v1",
            "meta-llama/llama-4-scout-17b-16e-instruct",
            "meta-llama/llama-4-maverick-17b-128e-instruct",
        ),
        (
            "CEREBRAS_API_KEY",
            "https://api.cerebras.ai/v1",
            "llama-3.3-70b",
            "llama-3.3-70b",
        ),
        (
            "NEBIUS_API_KEY",
            "https://api.tokenfactory.nebius.com/v1",
            "meta-llama/Llama-3.3-70B-Instruct",
            "meta-llama/Llama-3.3-70B-Instruct",
        ),
        (
            "SCALEWAY_API_KEY",
            "https://api.scaleway.ai/v1",
            "llama-3.3-70b-instruct",
            "llama-3.3-70b-instruct",
        ),
        (
            "MISTRAL_API_KEY",
            "https://api.mistral.ai/v1",
            "open-mistral-nemo-2407",
            "mistral-large-latest",
        ),
        (
            "COHERE_API_KEY",
            "https://api.cohere.com/compatibility/v1",
            "command-a-03-2025",
            "command-a-03-2025",
        ),
    ]

    def __init__(self) -> None:
        import openai as _openai
        self._openai = _openai

        self.providers: list[dict] = []
        self._rr_index = 0
        self._rr_lock = threading.Lock()
        self._cooldown_until: dict[str, float] = {}
        self._disabled: set[str] = set()
        self._tls = threading.local()
        self._stats: dict[str, dict[str, int]] = {}

        for env_var, base_url, fill_model, review_model in self.PROVIDER_TABLE:
            key = os.environ.get(env_var)
            if not key:
                continue
            try:
                self.providers.append({
                    "name": env_var.replace("_API_KEY", "").lower(),
                    "type": "openai_compat",
                    "client": _openai.OpenAI(api_key=key, base_url=base_url),
                    "fill_model": fill_model,
                    "review_model": review_model,
                })
            except Exception as e:
                print(f"  [warn] {env_var}: {e}", file=sys.stderr)

        anthr_key = os.environ.get("ANTHROPIC_API_KEY")
        if anthr_key:
            try:
                import anthropic as _anthropic
                self.providers.append({
                    "name": "anthropic",
                    "type": "anthropic",
                    "client": _anthropic.Anthropic(api_key=anthr_key),
                    "fill_model": "claude-haiku-4-5-20251001",
                    "review_model": "claude-sonnet-4-6",
                    "correct_model": "claude-sonnet-4-6",
                })
            except ImportError:
                pass

        if not self.providers:
            raise RuntimeError(
                "No LLM provider available. Set at least one of: "
                + ", ".join(e for e, *_ in self.PROVIDER_TABLE)
                + ", ANTHROPIC_API_KEY"
            )
        names = [p["name"] for p in self.providers]
        print(f"LLM providers (round-robin): {names}")

    def _ordered(self) -> list[dict]:
        now = time.time()
        n = len(self.providers)
        idx = self._rr_index % n
        rotated = self.providers[idx:] + self.providers[:idx]
        available = [p for p in rotated
                     if p["name"] not in self._disabled
                     and now >= self._cooldown_until.get(p["name"], 0)]
        if not available:
            cooled = {k: v for k, v in self._cooldown_until.items()
                      if k not in self._disabled}
            if not cooled:
                raise RuntimeError(
                    "All LLM providers are permanently disabled. "
                    "Check API keys / account credits."
                )
            earliest = min(cooled.values())
            wait = max(1.0, earliest - now + 0.5)
            print(f"  [rr] all providers in cooldown — waiting {wait:.0f}s …",
                  file=sys.stderr)
            time.sleep(wait)
            return self._ordered()
        return available

    def _bump(self, provider: str, key: str) -> None:
        with self._rr_lock:
            s = self._stats.setdefault(provider, {"ok": 0, "invalid": 0, "empty": 0})
            s[key] = s.get(key, 0) + 1

    def record_invalid(self) -> None:
        prov = getattr(self._tls, "last_provider", None)
        if prov:
            self._bump(prov, "invalid")

    def print_stats(self) -> None:
        if not self._stats:
            return
        print("\nProvider stats (ok / invalid / empty):")
        rows = sorted(self._stats.items(),
                      key=lambda kv: kv[1].get("ok", 0), reverse=True)
        for name, s in rows:
            ok, inv, emp = s.get("ok", 0), s.get("invalid", 0), s.get("empty", 0)
            total = ok + inv + emp
            bad_pct = f"{(inv + emp) / total * 100:.0f}% bad" if total else ""
            print(f"  {name:<14} ok={ok:4d}  invalid={inv:3d}  empty={emp:3d}  {bad_pct}")

    def _set_cooldown(self, prov_name: str) -> None:
        until = time.time() + RATE_LIMIT_COOLDOWN
        self._cooldown_until[prov_name] = until
        print(f"  [{prov_name}] rate-limited — cooldown +{RATE_LIMIT_COOLDOWN}s",
              file=sys.stderr)

    def call(
        self,
        system: str,
        user: str,
        mode: str = "fill",
        dry_run: bool = False,
    ) -> str | None:
        if dry_run:
            print(f"  [dry-run] {mode} call ({len(user)} chars)")
            return None

        for prov in self._ordered():
            model = prov.get(f"{mode}_model") or prov.get("fill_model")
            try:
                if prov["type"] == "openai_compat":
                    create_kwargs: dict = dict(
                        model=model,
                        max_tokens=2048,
                        temperature=0.4,
                        messages=[
                            {"role": "system", "content": system},
                            {"role": "user", "content": user},
                        ],
                    )
                    if mode == "fill":
                        create_kwargs["response_format"] = {"type": "json_object"}
                    resp = prov["client"].chat.completions.create(**create_kwargs)
                    with self._rr_lock:
                        self._rr_index += 1
                    content = resp.choices[0].message.content
                    if not content:
                        print(f"  [{prov['name']}] empty response", file=sys.stderr)
                        self._bump(prov["name"], "empty")
                        continue
                    self._tls.last_provider = prov["name"]
                    self._bump(prov["name"], "ok")
                    return content.strip()
                elif prov["type"] == "anthropic":
                    resp = prov["client"].messages.create(
                        model=model,
                        max_tokens=2048,
                        system=[{
                            "type": "text",
                            "text": system,
                            "cache_control": {"type": "ephemeral"},
                        }],
                        messages=[{"role": "user", "content": user}],
                    )
                    with self._rr_lock:
                        self._rr_index += 1
                    self._tls.last_provider = prov["name"]
                    self._bump(prov["name"], "ok")
                    return resp.content[0].text.strip()
            except Exception as e:
                err = str(e).lower()
                if any(kw in err for kw in ("rate", "429", "too many", "quota")):
                    self._set_cooldown(prov["name"])
                elif any(kw in err for kw in (
                    "401", "402", "403", "disabled", "forbidden",
                    "model_not_available", "non-serverless",
                )):
                    self._disabled.add(prov["name"])
                    print(f"  [{prov['name']}] permanently disabled: {e}", file=sys.stderr)
                else:
                    print(f"  [{prov['name']}] {e}", file=sys.stderr)

        return None


# ---------------------------------------------------------------------------
# JSON parsing
# ---------------------------------------------------------------------------

def parse_json(text: str) -> Any:
    text = text.strip()
    if "```" in text:
        text = "\n".join(
            l for l in text.splitlines() if not l.startswith("```")
        ).strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    for s_char, e_char in [('{', '}'), ('[', ']')]:
        start = text.find(s_char)
        end = text.rfind(e_char)
        if start != -1 and end > start:
            try:
                return json.loads(text[start:end + 1])
            except json.JSONDecodeError:
                pass
    return None


# ---------------------------------------------------------------------------
# Sense extraction
# ---------------------------------------------------------------------------

def get_senses(enrichment_json_str: str | None) -> list[str]:
    if not enrichment_json_str:
        return []
    try:
        d = json.loads(enrichment_json_str)
    except (json.JSONDecodeError, TypeError):
        return []
    raw = d.get("definitions") or d.get("senses") or []
    result: list[str] = []
    for s in raw:
        if isinstance(s, str) and s.strip():
            result.append(s.strip())
        elif isinstance(s, dict):
            defn = s.get("definition") or s.get("gloss") or s.get("text") or ""
            if defn:
                result.append(str(defn).strip())
    return result


# ---------------------------------------------------------------------------
# Prompts
# ---------------------------------------------------------------------------

FILL_SYSTEM = """\
You are a primary school teacher (grades 1–6, ages 6–12).
Task: Write 2–3 short, child-appropriate English example sentences for each word.

Rules:
- Maximum 12 words per sentence
- Simple everyday language, no jargon
- The word must appear in the sentence (base form or common inflection)
- No sentence begins with a quote or citation
- Age-appropriate: no violence, alcohol, or politics

Reply ONLY with valid JSON (no Markdown):
{"word1": ["Sentence1", "Sentence2"], "word2": ["Sentence1", "Sentence2", "Sentence3"]}"""

FILL_SENSE_SYSTEM = """\
You are a primary school teacher (grades 1–6, ages 6–12).
Task: The word has multiple meanings. Write one short, child-appropriate example sentence \
(max. 12 words) for EACH meaning.

Rules:
- Each sentence illustrates exactly the given meaning
- Simple everyday language
- Age-appropriate: no violence, alcohol, or politics

Reply ONLY with valid JSON (no Markdown):
[{"definition": "<meaning>", "example": "<sentence>"}, ...]"""

GRADE_FILL_SYSTEM = """\
You are an English teacher (grades 1–6).
Task: Write exactly 2 example sentences per grade level (1–6) for each submitted word.

Grade 1–2: max 6 words; Grade 3–4: max 9 words; Grade 5–6: max 12 words.
Each word must appear in every sentence. Increase difficulty across grades.
Treat all words factually and age-appropriately — never refuse.

Reply ONLY with valid JSON (no Markdown). Each submitted word is a top-level key:
{"word1": {"1": ["Sent1","Sent2"], "2": [...], "3": [...], "4": [...], "5": [...], "6": [...]}, "word2": {...}}"""

GRADE_SENSE_SYSTEM = """\
You are an English teacher. The word has multiple meanings.
Write exactly 2 example sentences per grade level (1–6) for EACH meaning.

Grade 1–2: max 6 words; Grade 3–4: max 9 words; Grade 5–6: max 12 words.
Age-appropriate, the word must appear, increasing difficulty.

Reply ONLY with valid JSON:
[{"definition": "<meaning>", "grade_examples": {"1": ["Sent1","Sent2"], ..., "6": ["Sent1","Sent2"]}}, ...]"""

CHECK_SYSTEM = """\
You are an English teacher (grades 1–6). Review and correct example sentences.

For each word:
- Replace grammatically incorrect sentences with correct ones
- Replace semantically wrong sentences (word used with wrong meaning)
- Fill empty grade levels (2 sentences per grade)
- Return correct sentences unchanged

Grade 1–2: max 6 words; Grade 3–4: max 9; Grade 5–6: max 12.
Treat all words factually — never refuse.

Reply ONLY with JSON:
{"word": {"1": ["Sent1","Sent2"], "2": [...], "3": [...], "4": [...], "5": [...], "6": [...]}}"""

REVIEW_SYSTEM = """\
You are a primary school teacher rating example sentences for child-appropriateness.

For each sentence:
  score: 1–5 (1=inappropriate for children, 5=perfect)
  reason: brief reason ONLY when score ≤ 2

Criteria for low scores:
- Complex syntax or rare vocabulary
- Inappropriate topics (violence, alcohol, politics, sexuality)
- Quotes with citations
- Sentence does not match the word's meaning

Reply ONLY with valid JSON:
{"word": [{"sentence": "...", "score": 4}, ...]}"""

REPLACE_SYSTEM = """\
You are a primary school teacher. Replace unsuitable sentences with child-appropriate \
alternatives (max. 12 words, simple language).
Reply ONLY with valid JSON:
{"word": ["Sent1", "Sent2"]}"""

CORRECT_ENRICH_FIELDS = {"definitions", "synonyms", "antonyms", "relatedWords"}

CORRECT_SYSTEM = """\
You are an experienced English teacher and lexicographer (primary school, grades 1–6).
You receive a dictionary entry as JSON. Your task:

1. Improve definitions: child-appropriate, clear, max 15 words per definition.
2. Add or correct synonyms and antonyms if present.
3. Leave all other fields unchanged.

Reply ONLY with valid JSON with exactly these possible fields:
{
  "definitions": ["<improved definition 1>", ...],
  "synonyms": ["<synonym>", ...],
  "antonyms": ["<antonym>", ...]
}

Omit fields that are not present or don't need improvement.
If the entry is already good, reply with {}."""


# ---------------------------------------------------------------------------
# Fill pass (flat llm_examples / sense_examples)
# ---------------------------------------------------------------------------

def run_fill(
    con: sqlite3.Connection,
    llm: LLMClient,
    rows: list[dict],
    batch_size: int,
    dry_run: bool,
    limit: int | None,
) -> tuple[int, int]:
    candidates = [
        r for r in rows
        if not _meta(r).get("tatoeba_examples")
        and not _meta(r).get("llm_examples")
        and not _meta(r).get("sense_examples")
        and not _meta(r).get("grade_examples")
        and not _meta(r).get("grade_sense_examples")
    ]
    if limit:
        candidates = candidates[:limit]
    print(f"Fill pass: {len(candidates)} words need LLM sentences")
    if not candidates:
        return 0, 0

    single: list[dict] = []
    multi: list[dict] = []
    for r in candidates:
        senses = get_senses(r.get("enrichment_json"))
        if len(senses) >= MULTI_SENSE_MIN:
            r["_senses"] = senses
            multi.append(r)
        else:
            single.append(r)

    print(f"  single-sense: {len(single)}, multi-sense: {len(multi)}")
    updated = stored = 0

    for i in range(0, len(single), batch_size):
        batch = single[i: i + batch_size]
        words = [r["word"] for r in batch]
        user_msg = (
            "Write 2–3 child-appropriate example sentences for:\n"
            + json.dumps(words, ensure_ascii=False)
        )
        print(f"  [single] batch {i // batch_size + 1}: {words}")
        raw = llm.call(FILL_SYSTEM, user_msg, mode="fill", dry_run=dry_run)
        if not raw:
            continue
        parsed = parse_json(raw)
        if not isinstance(parsed, dict):
            print(f"  [warn] bad response: {raw[:80]}", file=sys.stderr)
            continue
        for r in batch:
            word = r["word"]
            sents = _find_key(parsed, word)
            if not sents:
                continue
            clean = [s for s in sents if isinstance(s, str)
                     and len(s.split()) <= MAX_SENTENCE_WORDS]
            if not clean:
                continue
            meta = _meta(r)
            meta["llm_examples"] = clean
            _tag_source(meta)
            _write(con, r, meta, dry_run)
            updated += 1
            stored += len(clean)
        if not dry_run:
            con.commit()
        time.sleep(0.3)

    for r in multi:
        word = r["word"]
        senses = r["_senses"]
        sense_list = "\n".join(f"- {s}" for s in senses[:6])
        user_msg = (
            f"Word: {word}\n"
            f"Meanings:\n{sense_list}\n\n"
            f"Write one child-appropriate example sentence for each meaning."
        )
        print(f"  [multi]  {word} ({len(senses)} senses)")
        raw = llm.call(FILL_SENSE_SYSTEM, user_msg, mode="fill", dry_run=dry_run)
        if not raw:
            continue
        parsed = parse_json(raw)
        if not isinstance(parsed, list):
            print(f"  [warn] bad multi-sense response for {word}: {raw[:80]}",
                  file=sys.stderr)
            continue
        sense_examples = [
            {"definition": item.get("definition", ""), "example": item.get("example", "")}
            for item in parsed
            if isinstance(item, dict)
            and item.get("definition") and item.get("example")
            and len(item["example"].split()) <= MAX_SENTENCE_WORDS
        ]
        if not sense_examples:
            continue
        meta = _meta(r)
        meta["sense_examples"] = sense_examples
        _tag_source(meta)
        _write(con, r, meta, dry_run)
        updated += 1
        stored += len(sense_examples)
        time.sleep(0.3)

    if not dry_run:
        con.commit()
    return updated, stored


# ---------------------------------------------------------------------------
# Grade fill pass (grade_examples)
# ---------------------------------------------------------------------------

GRADE_KEYS = ("1", "2", "3", "4", "5", "6")
GRADE_MAX_WORDS = {"1": 6, "2": 6, "3": 9, "4": 9, "5": 12, "6": 12}


def _valid_grade_block(block: Any) -> dict[str, list[str]] | None:
    if not isinstance(block, dict):
        return None
    out: dict[str, list[str]] = {}
    for g in GRADE_KEYS:
        sents = block.get(g) or block.get(int(g))
        if not isinstance(sents, list):
            continue
        clean = [s for s in sents
                 if isinstance(s, str)
                 and 1 <= len(s.split()) <= GRADE_MAX_WORDS[g]]
        if clean:
            out[g] = clean[:2]
    return out if len(out) >= 3 else None


def run_grade_fill(
    con: sqlite3.Connection,
    llm: LLMClient,
    rows: list[dict],
    dry_run: bool,
    limit: int | None,
    workers: int = 1,
) -> tuple[int, int]:
    """Generate per-grade examples for all words."""
    jsonl_done: dict[int, dict] = {}
    if GRADE_JSONL.exists():
        with GRADE_JSONL.open() as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                    jsonl_done[rec["id"]] = rec
                except Exception:
                    pass
        print(f"  Loaded {len(jsonl_done)} results from {GRADE_JSONL.name}")
        # Apply checkpoint entries not yet in DB
        jsonl_applied = 0
        row_by_id = {r["id"]: r for r in rows}
        for row_id, rec in jsonl_done.items():
            r = row_by_id.get(row_id)
            if not r:
                continue
            meta = _meta(r)
            if rec.get("grade_examples") and not meta.get("grade_examples"):
                meta["grade_examples"] = rec["grade_examples"]
                _tag_source(meta)
                _write(con, r, meta, dry_run)
                jsonl_applied += 1
        if jsonl_applied:
            if not dry_run:
                con.commit()
            print(f"  Applied {jsonl_applied} checkpoint results to working DB")
            raw_rows = con.execute(
                "SELECT id, word, lemma, metadata_json, enrichment_json FROM words"
            ).fetchall()
            rows[:] = [dict(r) for r in raw_rows]

    candidates = [
        r for r in rows
        if not _meta(r).get("grade_examples")
    ]
    if limit:
        candidates = candidates[:limit]
    print(f"Grade fill pass: {len(candidates)} words need grade examples")
    if not candidates:
        return 0, 0

    GRADE_BATCH = 1   # words per LLM request (keep small to avoid JSON truncation)

    jsonl_lock = threading.Lock()
    counter = [0]
    results: list[tuple[int, str, dict]] = []

    def grade_batch(batch: list[dict]) -> tuple[int, int]:
        words = [r["word"] for r in batch]
        words_str = ", ".join(words)
        with jsonl_lock:
            counter[0] += 1
            idx = counter[0]
        total_batches = (len(candidates) + GRADE_BATCH - 1) // GRADE_BATCH
        print(f"  [grade] batch {idx}/{total_batches}: {words_str}")
        user_msg = (
            "Write 2 example sentences per grade level (1–6) for each word:\n"
            + json.dumps(words, ensure_ascii=False)
        )
        raw = llm.call(GRADE_FILL_SYSTEM, user_msg, mode="fill", dry_run=dry_run)
        provider = getattr(llm._tls, "last_provider", None)
        if not raw:
            return 0, 0
        parsed = parse_json(raw)
        if not isinstance(parsed, dict):
            print(f"  [warn] grade response not dict for {words_str}: {raw[:80]}",
                  file=sys.stderr)
            llm.record_invalid()
            return 0, 0
        # Unwrap single-key wrapper (e.g. LLM adds outer {"words": {...}})
        if len(parsed) == 1:
            only_key = next(iter(parsed))
            if only_key not in words and isinstance(parsed[only_key], dict):
                parsed = parsed[only_key]

        u = s = 0
        for r in batch:
            word = r["word"]
            block = _find_key(parsed, word)
            grade_block = _valid_grade_block(block)
            if not grade_block:
                print(f"  [warn] invalid grade block for {word}", file=sys.stderr)
                llm.record_invalid()
                continue
            if not dry_run:
                with jsonl_lock:
                    with GRADE_JSONL.open("a") as jf:
                        jf.write(json.dumps({"id": r["id"], "word": word,
                                             "grade_examples": grade_block,
                                             "provider": provider},
                                            ensure_ascii=False) + "\n")
            with jsonl_lock:
                results.append((r["id"], word, grade_block))
            u += 1
            s += sum(len(v) for v in grade_block.values())
        return u, s

    batches = [candidates[i:i + GRADE_BATCH]
               for i in range(0, len(candidates), GRADE_BATCH)]

    with ThreadPoolExecutor(max_workers=workers) as pool:
        updated = stored = 0
        for u, s in pool.map(grade_batch, batches):
            updated += u
            stored += s

    if not dry_run and results:
        print(f"  Applying {len(results)} results to DB …")
        row_by_id = {r["id"]: r for r in candidates}
        for row_id, word, grade_block in results:
            r = row_by_id.get(row_id)
            if not r:
                continue
            meta = _meta(r)
            meta["grade_examples"] = grade_block
            _tag_source(meta)
            _write(con, r, meta, dry_run=False)
        con.commit()

    return updated, stored


# ---------------------------------------------------------------------------
# Check pass — grammar/semantics review + gap fill
# ---------------------------------------------------------------------------

CHECK_BATCH = 3


def _needs_check(meta: dict) -> bool:
    ge = meta.get("grade_examples")
    if not ge:
        return False
    return any(len(ge.get(g, [])) < 2 for g in GRADE_KEYS)


def run_check(
    con: sqlite3.Connection,
    llm: LLMClient,
    rows: list[dict],
    dry_run: bool,
    limit: int | None,
    workers: int = 1,
    all_words: bool = False,
) -> tuple[int, int]:
    check_done: set[int] = set()
    if CHECK_JSONL.exists():
        with CHECK_JSONL.open() as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                    row_id = rec.get("id")
                    if row_id is not None:
                        r = next((r for r in rows if r["id"] == row_id), None)
                        if r and rec.get("grade_examples"):
                            meta = _meta(r)
                            meta["grade_examples"] = rec["grade_examples"]
                            _tag_source(meta)
                            _write(con, r, meta, dry_run)
                        check_done.add(row_id)
                except Exception:
                    pass
        if check_done and not dry_run:
            con.commit()
        print(f"  Check checkpoint: {len(check_done)} already done")

    candidates = [
        r for r in rows
        if r["id"] not in check_done
        and _meta(r).get("grade_examples")
        and (all_words or _needs_check(_meta(r)))
    ]
    if limit:
        candidates = candidates[:limit]
    print(f"Check pass: {len(candidates)} words to review "
          f"({'all' if all_words else 'gaps only'})")
    if not candidates:
        return 0, 0

    jsonl_lock = threading.Lock()
    counter = [0]
    results: list[tuple[int, str, dict]] = []

    def check_one_batch(batch: list[dict]) -> tuple[int, int]:
        payload = {r["word"]: _meta(r).get("grade_examples", {}) for r in batch}
        words_str = ", ".join(r["word"] for r in batch)
        with jsonl_lock:
            counter[0] += 1
            idx = counter[0]
        total_batches = (len(candidates) + CHECK_BATCH - 1) // CHECK_BATCH
        print(f"  [check] batch {idx}/{total_batches}: {words_str}")

        raw = llm.call(CHECK_SYSTEM, json.dumps(payload, ensure_ascii=False),
                       mode="fill", dry_run=dry_run)
        if not raw:
            return 0, 0

        parsed = parse_json(raw)
        if not isinstance(parsed, dict):
            print(f"  [warn] check response not dict for {words_str}: {raw[:80]}",
                  file=sys.stderr)
            return 0, 0

        # Unwrap {"Word": {actual_words...}} wrapper some LLMs emit
        if len(parsed) == 1:
            only_key = next(iter(parsed))
            if only_key not in payload and isinstance(parsed[only_key], dict):
                parsed = parsed[only_key]

        u = s = 0
        for r in batch:
            word = r["word"]
            block = _find_key(parsed, word)
            grade_block = _valid_grade_block(block)
            if not grade_block:
                print(f"  [warn] invalid check block for {word}", file=sys.stderr)
                with jsonl_lock:
                    check_done.add(r["id"])
                if not dry_run:
                    with jsonl_lock:
                        with CHECK_JSONL.open("a") as jf:
                            jf.write(json.dumps({"id": r["id"], "word": word,
                                                 "grade_examples": None},
                                                ensure_ascii=False) + "\n")
                continue
            if not dry_run:
                with jsonl_lock:
                    with CHECK_JSONL.open("a") as jf:
                        jf.write(json.dumps({"id": r["id"], "word": word,
                                             "grade_examples": grade_block},
                                            ensure_ascii=False) + "\n")
            with jsonl_lock:
                results.append((r["id"], word, grade_block))
                check_done.add(r["id"])
            u += 1
            s += sum(len(v) for v in grade_block.values())
        return u, s

    batches = [candidates[i:i + CHECK_BATCH]
               for i in range(0, len(candidates), CHECK_BATCH)]

    updated = stored = 0
    with ThreadPoolExecutor(max_workers=workers) as pool:
        for u, s in pool.map(check_one_batch, batches):
            updated += u
            stored += s

    if not dry_run and results:
        print(f"  Applying {len(results)} check results to DB …")
        row_by_id = {r["id"]: r for r in candidates}
        for row_id, word, grade_block in results:
            r = row_by_id.get(row_id)
            if not r:
                continue
            meta = _meta(r)
            meta["grade_examples"] = grade_block
            _tag_source(meta)
            _write(con, r, meta, dry_run=False)
        con.commit()

    return updated, stored


# ---------------------------------------------------------------------------
# Review pass
# ---------------------------------------------------------------------------

def run_review(
    con: sqlite3.Connection,
    llm: LLMClient,
    rows: list[dict],
    batch_size: int,
    dry_run: bool,
    limit: int | None,
) -> tuple[int, int]:
    candidates = [
        r for r in rows
        if _meta(r).get("tatoeba_examples") and not _meta(r).get("llm_review")
    ]
    if limit:
        candidates = candidates[:limit]
    print(f"Review pass: {len(candidates)} words to check")
    if not candidates:
        return 0, 0

    reviewed = replaced = 0

    for i in range(0, len(candidates), batch_size):
        batch = candidates[i: i + batch_size]
        review_input = {
            r["word"]: _meta(r).get("tatoeba_examples", []) for r in batch
        }
        user_msg = (
            "Rate the child-appropriateness of these sentences:\n"
            + json.dumps(review_input, ensure_ascii=False)
        )
        print(f"  [review] batch {i // batch_size + 1} ({len(batch)} words)")
        raw = llm.call(REVIEW_SYSTEM, user_msg, mode="review", dry_run=dry_run)
        if not raw:
            continue
        parsed = parse_json(raw)
        if not isinstance(parsed, dict):
            continue

        to_replace: list[str] = []
        for r in batch:
            word = r["word"]
            review_data = _find_key(parsed, word)
            if not review_data:
                continue
            meta = _meta(r)
            meta["llm_review"] = review_data
            bad = [x for x in review_data
                   if isinstance(x, dict) and x.get("score", 5) <= REVIEW_THRESHOLD]
            if bad:
                to_replace.append(word)
            _write(con, r, meta, dry_run)
            reviewed += 1

        if to_replace:
            rep_msg = (
                "Write child-appropriate replacement sentences (max 12 words) for:\n"
                + json.dumps(to_replace, ensure_ascii=False)
            )
            raw2 = llm.call(REPLACE_SYSTEM, rep_msg, mode="fill", dry_run=dry_run)
            if raw2:
                rep_parsed = parse_json(raw2)
                if isinstance(rep_parsed, dict):
                    for r in batch:
                        if r["word"] not in to_replace:
                            continue
                        new_sents = _find_key(rep_parsed, r["word"])
                        if new_sents and isinstance(new_sents, list):
                            meta = _meta(r)
                            meta["llm_examples"] = [
                                s for s in new_sents
                                if isinstance(s, str)
                                and len(s.split()) <= MAX_SENTENCE_WORDS
                            ]
                            _write(con, r, meta, dry_run)
                            replaced += 1

        if not dry_run:
            con.commit()
        time.sleep(0.3)

    return reviewed, replaced


# ---------------------------------------------------------------------------
# Correct pass
# ---------------------------------------------------------------------------

def run_correct(
    con: sqlite3.Connection,
    llm: LLMClient,
    rows: list[dict],
    dry_run: bool,
    limit: int | None,
) -> tuple[int, int]:
    candidates = [
        r for r in rows
        if r.get("enrichment_json") and not _meta(r).get("llm_corrected")
    ]
    if limit:
        candidates = candidates[:limit]
    print(f"Correct pass: {len(candidates)} entries to improve")
    if not candidates:
        return 0, 0

    updated = changed_fields = 0

    for r in candidates:
        word = r["word"]
        try:
            enrich = json.loads(r["enrichment_json"])
        except (json.JSONDecodeError, TypeError):
            continue

        context: dict = {"word": word}
        for f in CORRECT_ENRICH_FIELDS:
            val = enrich.get(f)
            if val:
                context[f] = val

        user_msg = json.dumps(context, ensure_ascii=False)
        print(f"  [correct] {word}")
        raw = llm.call(CORRECT_SYSTEM, user_msg, mode="correct", dry_run=dry_run)
        if not raw:
            continue

        parsed = parse_json(raw)
        if not isinstance(parsed, dict):
            print(f"  [warn] corrupt JSON for {word}: {raw[:80]}", file=sys.stderr)
            continue

        patch: dict = {}
        bad = False
        for field in CORRECT_ENRICH_FIELDS:
            val = parsed.get(field)
            if val is None:
                continue
            if not isinstance(val, list) or not all(isinstance(s, str) for s in val):
                print(f"  [warn] bad type for {field} in {word} — skipping",
                      file=sys.stderr)
                bad = True
                break
            if val:
                patch[field] = val

        if bad or not patch:
            continue

        enrich.update(patch)
        meta = _meta(r)
        meta["llm_corrected"] = True
        _tag_source(meta)

        if not dry_run:
            con.execute(
                "UPDATE words SET enrichment_json = ?, metadata_json = ? WHERE id = ?",
                (json.dumps(enrich, ensure_ascii=False),
                 json.dumps(meta, ensure_ascii=False),
                 r["id"]),
            )
        updated += 1
        changed_fields += len(patch)
        time.sleep(0.3)

    if not dry_run:
        con.commit()
    return updated, changed_fields


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _meta(r: dict) -> dict:
    try:
        return json.loads(r.get("metadata_json") or "{}") or {}
    except (json.JSONDecodeError, TypeError):
        return {}


def _find_key(d: dict, word: str) -> Any:
    val = d.get(word)
    if val is not None:
        return val
    wl = word.lower()
    for k, v in d.items():
        if k.lower() == wl:
            return v
    return None


def _tag_source(meta: dict) -> None:
    sources = list(meta.get("sources") or [])
    if "LLM_GENERATED" not in sources:
        sources.append("LLM_GENERATED")
        meta["sources"] = sources


def _write(con: sqlite3.Connection, r: dict, meta: dict, dry_run: bool) -> None:
    if not dry_run:
        con.execute(
            "UPDATE words SET metadata_json = ? WHERE id = ?",
            (json.dumps(meta, ensure_ascii=False), r["id"]),
        )


# ---------------------------------------------------------------------------
# Cleanup pass
# ---------------------------------------------------------------------------

def run_cleanup(src_db: Path, wipe_partials: bool = False, dry_run: bool = False) -> None:
    """Wipe structurally incomplete grade_examples from source DB.

    With wipe_partials: also remove entries with any grade having < 2 sentences
    and purge those IDs from grade_results_en.jsonl so the next --grade regenerates.
    """
    con = sqlite3.connect(str(src_db))
    rows = con.execute("SELECT id, metadata_json FROM words").fetchall()

    partial_wiped = 0
    partial_ids: set[int] = set()

    for row_id, m in rows:
        meta = json.loads(m) if m else {}
        ge = meta.get("grade_examples")
        if not ge:
            continue
        if wipe_partials:
            counts = [len(ge.get(g, [])) for g in "123456"]
            if not all(c >= 2 for c in counts):
                if not dry_run:
                    del meta["grade_examples"]
                    con.execute("UPDATE words SET metadata_json=? WHERE id=?",
                                (json.dumps(meta, ensure_ascii=False), row_id))
                partial_wiped += 1
                partial_ids.add(row_id)

    if not dry_run:
        con.commit()
    con.close()

    if wipe_partials:
        print(f"Cleanup: wiped {partial_wiped} partial entries")
    else:
        print("Cleanup: nothing to do (use --wipe-partials to wipe incomplete grade blocks)")

    if partial_ids and not dry_run:
        kept, removed = [], 0
        if GRADE_JSONL.exists():
            with GRADE_JSONL.open() as fh:
                for line in fh:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        rec = json.loads(line)
                        if rec.get("id") in partial_ids:
                            removed += 1
                        else:
                            kept.append(line)
                    except Exception:
                        kept.append(line)
            with GRADE_JSONL.open("w") as fh:
                fh.write("\n".join(kept) + "\n")
        print(f"  Removed {removed} partial entries from {GRADE_JSONL.name} "
              f"({len(kept)} remaining)")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    load_dotenv()

    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--db", default=str(DEFAULT_DB))
    ap.add_argument("--fill", action="store_true",
                    help="Generate flat llm_examples / sense_examples for gap words")
    ap.add_argument("--grade", action="store_true",
                    help="Generate grade_examples (2 sentences × 6 grades) for all words")
    ap.add_argument("--review", action="store_true",
                    help="Rate tatoeba_examples for child-appropriateness, replace bad ones")
    ap.add_argument("--correct", action="store_true",
                    help="Improve definitions/synonyms via capable LLM (data-safe)")
    ap.add_argument("--check", action="store_true",
                    help="Review grade_examples: fix grammar/semantics, fill empty grades.")
    ap.add_argument("--check-all", action="store_true",
                    help="Like --check but reviews every graded word.")
    ap.add_argument("--cleanup", action="store_true",
                    help="Cleanup mode (use with --wipe-partials to remove incomplete blocks)")
    ap.add_argument("--wipe-partials", action="store_true",
                    help="Combined with --cleanup: wipe incomplete grade blocks and "
                         "remove from grade_results_en.jsonl")
    ap.add_argument("--no-compress", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--batch-size", type=int, default=DEFAULT_BATCH)
    ap.add_argument("--workers", type=int, default=1)
    args = ap.parse_args()

    if not any([args.fill, args.grade, args.review, args.correct,
                args.check, args.check_all, args.cleanup]):
        args.fill = True

    src_db = Path(args.db)
    if not src_db.exists():
        sys.exit(f"ERROR: DB not found: {src_db}")

    if args.cleanup:
        run_cleanup(src_db, wipe_partials=args.wipe_partials, dry_run=args.dry_run)
        if not any([args.fill, args.grade, args.review, args.correct,
                    args.check, args.check_all]):
            print("Done.")
            return 0

    needs_llm = any([args.fill, args.grade, args.review, args.correct,
                     args.check, args.check_all])
    llm: LLMClient | None = None
    if needs_llm:
        try:
            llm = LLMClient()
        except RuntimeError as e:
            sys.exit(f"ERROR: {e}")

    WORK_DB.parent.mkdir(parents=True, exist_ok=True)

    def _grade_count(db_path: Path) -> int:
        try:
            c = sqlite3.connect(str(db_path))
            n = c.execute(
                "SELECT COUNT(*) FROM words "
                "WHERE json_extract(metadata_json,'$.grade_examples') IS NOT NULL"
            ).fetchone()[0]
            c.close()
            return n
        except Exception:
            return 0

    if WORK_DB.exists() and src_db.resolve() != WORK_DB.resolve():
        if WORK_DB.stat().st_mtime > src_db.stat().st_mtime:
            work_grades = _grade_count(WORK_DB)
            src_grades  = _grade_count(src_db)
            print(f"Resuming from existing {WORK_DB} "
                  f"({work_grades} grades) rather than {src_db} ({src_grades} grades)")
        else:
            print(f"Copying {src_db} → {WORK_DB} (src_db is newer)")
            shutil.copy2(src_db, WORK_DB)
    elif not WORK_DB.exists():
        print(f"Copying {src_db} → {WORK_DB}")
        shutil.copy2(src_db, WORK_DB)
    else:
        sys.exit(f"ERROR: --db path and working DB are the same file: {WORK_DB}")

    con = sqlite3.connect(str(WORK_DB))
    con.row_factory = sqlite3.Row
    raw_rows = con.execute(
        "SELECT id, word, lemma, metadata_json, enrichment_json FROM words"
    ).fetchall()
    rows = [dict(r) for r in raw_rows]
    print(f"Loaded {len(rows)} entries")

    total_updated = 0

    if args.fill:
        n, s = run_fill(con, llm, rows, args.batch_size, args.dry_run, args.limit)
        print(f"\nFill: {n} entries updated, {s} sentences stored")
        total_updated += n

    if args.grade:
        raw_rows = con.execute(
            "SELECT id, word, lemma, metadata_json, enrichment_json FROM words"
        ).fetchall()
        rows = [dict(r) for r in raw_rows]
        n, s = run_grade_fill(con, llm, rows, args.dry_run, args.limit, args.workers)
        print(f"\nGrade fill: {n} entries updated, {s} sentences stored")
        total_updated += n

    if args.check or args.check_all:
        raw_rows = con.execute(
            "SELECT id, word, lemma, metadata_json, enrichment_json FROM words"
        ).fetchall()
        rows = [dict(r) for r in raw_rows]
        n, s = run_check(con, llm, rows, args.dry_run, args.limit,
                         args.workers, all_words=args.check_all)
        print(f"\nCheck: {n} entries corrected, {s} sentences stored")
        total_updated += n

    if args.review:
        raw_rows = con.execute(
            "SELECT id, word, lemma, metadata_json, enrichment_json FROM words"
        ).fetchall()
        rows = [dict(r) for r in raw_rows]
        n, r = run_review(con, llm, rows, args.batch_size, args.dry_run, args.limit)
        print(f"\nReview: {n} checked, {r} sentences replaced")
        total_updated += r

    if args.correct:
        raw_rows = con.execute(
            "SELECT id, word, lemma, metadata_json, enrichment_json FROM words"
        ).fetchall()
        rows = [dict(r) for r in raw_rows]
        n, f = run_correct(con, llm, rows, args.dry_run, args.limit)
        print(f"\nCorrect: {n} entries improved, {f} fields updated")
        total_updated += n

    con.close()

    if not args.dry_run and total_updated > 0:
        print(f"Copying {WORK_DB} → {src_db}")
        shutil.copy2(WORK_DB, src_db)
        if not args.no_compress and DB_GZ.exists():
            print(f"Compressing → {DB_GZ}")
            with src_db.open("rb") as fi, gzip.open(DB_GZ, "wb", compresslevel=9) as fo:
                shutil.copyfileobj(fi, fo)
            print(f"  {DB_GZ.stat().st_size // 1024} KB written")

    if llm:
        llm.print_stats()
    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
