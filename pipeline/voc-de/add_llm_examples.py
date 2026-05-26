"""Generate and/or review German example sentences via LLM (multi-provider).

Modes (combinable):
  --fill      For each word with no examples: generate 2–3 kindgerecht sentences.
              Single-sense → llm_examples; multi-sense → sense_examples.
  --grade     For each word: generate 3 sentences per school grade (1–6),
              stored as grade_examples {"1": [...], ..., "6": [...]}.
              Sentences increase in difficulty — app picks by learner grade level.
  --review    For each word with tatoeba_examples: rate child-appropriateness (1–5).
              Sentences scored ≤ 2 are replaced via llm_examples.
  --correct   Send full entry JSON to a capable LLM for semantic/definition
              improvement. Only allowlisted fields are written back; corrupt
              JSON or unexpected types are silently dropped (data-safe).

Rate-limit handling (CrispSorter-inspired):
  On HTTP 429 the offending provider is placed in a 60-second cooldown and
  the request immediately falls through to the next provider in the round-robin.
  All providers in cooldown → wait for the earliest to recover, then retry.

Providers (round-robin, keys from ../../.env):
  1. OpenRouter  (OPENROUTER_API_KEY)   claude-haiku-4-5 / claude-sonnet-4-6
  2. Groq        (GROQ_API_KEY)         llama-4-scout / llama-4-maverick
  3. Together    (TOGETHER_API_KEY)     Llama-3.3-70B-Instruct-Turbo-Free
  4. Cerebras    (CEREBRAS_API_KEY)     llama-3.3-70b
  5. Nebius      (NEBIUS_API_KEY)       Llama-3.3-70B-Instruct
  6. Scaleway    (SCALEWAY_API_KEY)     llama-3.3-70b-instruct
  7. Mistral     (MISTRAL_API_KEY)      open-mistral-nemo-2407 / mistral-large-latest
  8. Anthropic   (ANTHROPIC_API_KEY)    claude-haiku-4-5-20251001 (direct fallback)
Providers without a key are silently skipped. Providers returning 401/403/
model_not_available are permanently self-disabled after the first failure.

Usage:
  python add_llm_examples.py [--fill] [--grade] [--review] [--correct]
                              [--db grundwortschatz.db] [--dry-run]
                              [--limit N] [--batch-size N] [--no-compress]
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
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
GRADE_JSONL = HERE / "grade_results.jsonl"   # crash-safe checkpoint
CHECK_JSONL = HERE / "check_results.jsonl"   # checker pass checkpoint
# Resolve .env from several candidate locations (local dev, VPS)
def _find_env_file() -> Path:
    for candidate in [
        HERE / ".env",
        REPO / ".env",
        REPO.parent / ".env",
        Path.home() / ".env",
    ]:
        if candidate.exists():
            return candidate
    return HERE / ".env"  # fallback (may not exist)
ENV_FILE = _find_env_file()

DEFAULT_DB = HERE / "grundwortschatz.db"
WORK_DB = Path("/tmp/dbpatch_llm/working.db")
DB_GZ = REPO / "assets" / "grundwortschatz.db.gz"

DEFAULT_BATCH = 6
MAX_SENTENCE_WORDS = 12
MULTI_SENSE_MIN = 2
REVIEW_THRESHOLD = 2
RATE_LIMIT_COOLDOWN = 60   # seconds to exclude a rate-limited provider


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
    # Model names verified against /Users/christianstrobele/code/AIToolkit/config.py
    # (env_var, base_url, fill_model, review_model)
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
        self._cooldown_until: dict[str, float] = {}   # provider_name → epoch
        self._disabled: set[str] = set()              # permanently disabled providers
        self._tls = threading.local()                 # per-thread last_provider
        self._stats: dict[str, dict[str, int]] = {}  # provider → {ok, invalid, empty}

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
        """Return providers starting from round-robin cursor, skipping disabled/cooled-down."""
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
        """Call after call() returned content but it failed validation."""
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
        print(f"  [{prov_name}] rate-limited — cooldown until "
              f"+{RATE_LIMIT_COOLDOWN}s", file=sys.stderr)

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
                code = getattr(getattr(e, "status_code", None), "real", None) or 0
                try:
                    code = int(code) if code else 0
                except (TypeError, ValueError):
                    code = 0
                if any(kw in err for kw in ("rate", "429", "too many", "quota")):
                    self._set_cooldown(prov["name"])
                    # Fall through immediately to next provider
                elif any(kw in err for kw in (
                    "401", "402", "403", "disabled", "forbidden",
                    "model_not_available", "non-serverless",
                )):
                    self._disabled.add(prov["name"])
                    print(f"  [{prov['name']}] permanently disabled: {e}", file=sys.stderr)
                else:
                    print(f"  [{prov['name']}] {e}", file=sys.stderr)
                # Try next provider regardless

        return None


# ---------------------------------------------------------------------------
# JSON parsing
# ---------------------------------------------------------------------------

def parse_json(text: str) -> Any:
    text = text.strip()
    # Strip markdown fences
    if "```" in text:
        text = "\n".join(
            l for l in text.splitlines() if not l.startswith("```")
        ).strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    # Fallback: extract first {...} or [...] block (handles preamble prose)
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
    """Return list of sense definitions from enrichment_json."""
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
Du bist ein Grundschullehrer (Klasse 1–6, Alter 6–12).
Aufgabe: Schreibe für jedes Wort 2–3 kurze, kindgerechte deutsche Beispielsätze.

Regeln:
- Maximal 12 Wörter pro Satz
- Einfache Alltagssprache, kein Fachjargon
- Das Wort muss im Satz vorkommen (Grundform oder gebräuchliche Flexion)
- Kein Satz beginnt mit einem Zitat oder einer Quellenangabe
- Kindgerecht: keine Gewalt, kein Alkohol, keine Politik

Antworte NUR mit validem JSON (kein Markdown):
{"Wort1": ["Satz1", "Satz2"], "Wort2": ["Satz1", "Satz2", "Satz3"]}"""

FILL_SENSE_SYSTEM = """\
Du bist ein Grundschullehrer (Klasse 1–6, Alter 6–12).
Aufgabe: Das Wort hat mehrere Bedeutungen. Schreibe für JEDE Bedeutung \
einen kurzen, kindgerechten Beispielsatz (max. 12 Wörter).

Regeln:
- Jeder Satz illustriert genau die angegebene Bedeutung
- Einfache Alltagssprache
- Kindgerecht: keine Gewalt, kein Alkohol, keine Politik

Antworte NUR mit validem JSON (kein Markdown):
[{"definition": "<Bedeutung>", "example": "<Satz>"}, ...]"""

GRADE_FILL_SYSTEM = """\
Du bist ein Deutschlehrer (Klasse 1–6).
Aufgabe: Schreibe für jedes Wort genau 2 Beispielsätze pro Klassenstufe (1–6).

Klasse 1–2: max. 6 Wörter; Klasse 3–4: max. 9 Wörter; Klasse 5–6: max. 12 Wörter.
Das Wort muss in jedem Satz vorkommen. Zunehmende Schwierigkeit.
Auch schwierige Wörter (Tod, Strafe, Gefahr, Imperative) werden sachlich und altersstufengerecht verwendet — niemals ablehnen.

Antworte NUR mit validem JSON (kein Markdown):
{"Wort": {"1": ["Satz1","Satz2"], "2": ["Satz1","Satz2"], "3": [...], "4": [...], "5": [...], "6": [...]}}"""

GRADE_SENSE_SYSTEM = """\
Du bist ein Deutschlehrer. Das Wort hat mehrere Bedeutungen.
Schreibe für JEDE Bedeutung genau 2 Beispielsätze pro Klassenstufe (1–6).

Klasse 1–2: max. 6 Wörter; Klasse 3–4: max. 9 Wörter; Klasse 5–6: max. 12 Wörter.
Kindgerecht, das Wort muss vorkommen, zunehmende Schwierigkeit.

Antworte NUR mit validem JSON:
[{"definition": "<Bedeutung>", "grade_examples": {"1": ["Satz1","Satz2"], ..., "6": ["Satz1","Satz2"]}}, ...]"""

CHECK_SYSTEM = """\
Du bist ein Deutschlehrer (Klasse 1–6). Prüfe und korrigiere Beispielsätze.

Je Wort:
- Ersetze grammatisch falsche Sätze durch korrekte
- Ersetze semantisch falsche Sätze (Wort in falscher Bedeutung verwendet)
- Fülle leere Klassenstufen auf (2 Sätze je Stufe)
- Korrekte Sätze unverändert zurückgeben

Klasse 1–2: max 6 Wörter; Klasse 3–4: max 9; Klasse 5–6: max 12.
Auch schwierige Wörter sachlich behandeln — niemals ablehnen.

Antworte NUR mit JSON:
{"Wort": {"1": ["Satz1","Satz2"], "2": [...], "3": [...], "4": [...], "5": [...], "6": [...]}}"""

REVIEW_SYSTEM = """\
Du bist ein Grundschullehrer und bewertest Beispielsätze auf Kindgerechtheit.

Für jeden Satz:
  score: 1–5 (1=für Kinder ungeeignet, 5=perfekt)
  reason: kurze Begründung NUR wenn score ≤ 2

Kriterien für niedrige Wertung:
- Komplexe Syntax oder Fremdwörter
- Unangemessene Themen (Gewalt, Alkohol, Politik, Sexualität)
- Zitate mit Quellenangaben
- Satz passt nicht zum Wort

Antworte NUR mit validem JSON:
{"Wort": [{"sentence": "...", "score": 4}, ...]}"""

REPLACE_SYSTEM = """\
Du bist ein Grundschullehrer. Ersetze ungeeignete Sätze durch kindgerechte \
Alternativen (max. 12 Wörter, einfache Sprache).
Antworte NUR mit validem JSON:
{"Wort": ["Satz1", "Satz2"]}"""

# Allowlisted fields the correct pass may update in enrichment_json
CORRECT_ENRICH_FIELDS = {"definitions", "synonyms", "antonyms", "relatedWords"}

CORRECT_SYSTEM = """\
Du bist ein erfahrener Deutschlehrer und Lexikograf (Grundschule Klasse 1–6).
Du erhältst einen Wörterbucheintrag als JSON. Deine Aufgabe:

1. Verbessere die Definitionen: kindgerecht, klar, max. 15 Wörter pro Definition.
2. Ergänze oder korrigiere Synonyme und Antonyme, falls vorhanden.
3. Lass alle anderen Felder unverändert.

Antworte NUR mit validem JSON mit genau diesen möglichen Feldern:
{
  "definitions": ["<verbesserte Definition 1>", ...],
  "synonyms": ["<Synonym>", ...],
  "antonyms": ["<Antonym>", ...]
}

Felder die NICHT vorhanden sind oder nicht verbessert werden können weglassen.
Wenn der Eintrag bereits gut ist, antworte mit {}."""


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
        and "VORNAME_STANDESAMT" not in (_meta(r).get("sources") or [])
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
            "Schreibe je 2–3 kindgerechte Beispielsätze für:\n"
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
            f"Wort: {word}\n"
            f"Bedeutungen:\n{sense_list}\n\n"
            f"Schreibe für jede Bedeutung einen kindgerechten Beispielsatz."
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
# Grade fill pass (grade_examples / grade_sense_examples)
# ---------------------------------------------------------------------------

GRADE_KEYS = ("1", "2", "3", "4", "5", "6")
GRADE_MAX_WORDS = {"1": 10, "2": 10, "3": 14, "4": 14, "5": 18, "6": 18}

def _valid_grade_block(block: Any) -> dict[str, list[str]] | None:
    """Validate and clean a grade_examples block from the LLM.

    Returns a clean {"1": [...], ..., "6": [...]} or None if invalid.
    """
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
    # Accept block if at least 3 grades present
    return out if len(out) >= 3 else None


def run_grade_fill(
    con: sqlite3.Connection,
    llm: LLMClient,
    rows: list[dict],
    dry_run: bool,
    limit: int | None,
    workers: int = 1,
) -> tuple[int, int]:
    """Generate per-grade examples for all words (including those with tatoeba)."""
    # Load JSONL checkpoint — words already graded in a previous interrupted run
    jsonl_done: dict[int, dict] = {}   # row_id → full record
    if GRADE_JSONL.exists():
        with GRADE_JSONL.open() as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                    # Last entry wins if a word appears twice (e.g. re-run)
                    jsonl_done[rec["id"]] = rec
                except Exception:
                    pass
        print(f"  Loaded {len(jsonl_done)} results from {GRADE_JSONL.name}")
        # Apply checkpoint entries that aren't yet in the DB
        jsonl_applied = 0
        row_by_id = {r["id"]: r for r in rows}
        for row_id, rec in jsonl_done.items():
            r = row_by_id.get(row_id)
            if not r:
                continue
            srcs = set(_meta(r).get("sources") or [])
            if any(s.startswith("VORNAME") for s in srcs):
                continue
            meta = _meta(r)
            changed = False
            if rec.get("grade_examples") and not meta.get("grade_examples"):
                meta["grade_examples"] = rec["grade_examples"]
                changed = True
            if changed:
                _tag_source(meta)
                _write(con, r, meta, dry_run)
                jsonl_applied += 1
        if jsonl_applied:
            if not dry_run:
                con.commit()
            print(f"  Applied {jsonl_applied} checkpoint results to working DB")
            # Re-read rows so candidates list sees the applied results
            raw_rows = con.execute(
                "SELECT id, word, lemma, metadata_json, enrichment_json FROM words"
            ).fetchall()
            rows[:] = [dict(r) for r in raw_rows]

    candidates = [
        r for r in rows
        if not _meta(r).get("grade_examples")
        and not any(s.startswith("VORNAME") for s in (_meta(r).get("sources") or []))
    ]
    if limit:
        candidates = candidates[:limit]
    print(f"Grade fill pass: {len(candidates)} words need grade examples")
    if not candidates:
        return 0, 0

    jsonl_lock = threading.Lock()
    counter = [0]  # mutable for closure
    results: list[tuple[int, str, dict]] = []  # (id, word, grade_block)

    def grade_one(r: dict) -> tuple[int, int]:
        word = r["word"]
        user_msg = (
            "Schreibe je 2 Beispielsätze pro Klassenstufe (1–6) für:\n"
            + json.dumps([word], ensure_ascii=False)
        )
        with jsonl_lock:
            counter[0] += 1
            idx = counter[0]
        print(f"  [grade] {idx}/{len(candidates)}: {word}")
        raw = llm.call(GRADE_FILL_SYSTEM, user_msg, mode="fill", dry_run=dry_run)
        provider = getattr(llm._tls, "last_provider", None)
        if not raw:
            return 0, 0
        parsed = parse_json(raw)
        if not isinstance(parsed, dict):
            print(f"  [warn] grade response not dict for {word}: {raw[:100]}", file=sys.stderr)
            llm.record_invalid()
            return 0, 0
        block = _find_key(parsed, word)
        grade_block = _valid_grade_block(block)
        if not grade_block:
            print(f"  [warn] invalid grade block for {word}", file=sys.stderr)
            llm.record_invalid()
            return 0, 0
        # Write only to JSONL — DB apply happens in one pass after the pool finishes
        if not dry_run:
            with jsonl_lock:
                with GRADE_JSONL.open("a") as jf:
                    jf.write(json.dumps({"id": r["id"], "word": word,
                                         "grade_examples": grade_block,
                                         "provider": provider},
                                        ensure_ascii=False) + "\n")
        with jsonl_lock:
            results.append((r["id"], word, grade_block))
        return 1, sum(len(v) for v in grade_block.values())

    with ThreadPoolExecutor(max_workers=workers) as pool:
        updated = stored = 0
        for u, s in pool.map(grade_one, candidates):
            updated += u
            stored += s

    # Apply all results to DB in one single-threaded pass
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
# Check pass — grammar/semantics review + gap fill for grade_examples
# ---------------------------------------------------------------------------

CHECK_BATCH = 1   # words per LLM request (keep small to avoid JSON truncation)


def _needs_check(meta: dict) -> bool:
    """True if grade_examples is missing any grade or has < 2 sentences anywhere."""
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
    """Review and correct grade_examples: fix grammar/semantics, fill gaps.

    By default only processes words with structural gaps (empty/short grades).
    Pass all_words=True to review every graded word.
    """
    # Load checkpoint
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
                        # Apply to DB if not already there
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
        and not any(s.startswith("VORNAME") for s in (_meta(r).get("sources") or []))
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
        # Build user message: current grade_examples for each word in batch
        payload = {
            r["word"]: _meta(r).get("grade_examples", {}) for r in batch
        }
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

        # Unwrap {"Wort": {actual_words...}} wrapper some LLMs emit
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
                # Still mark as done so we don't retry forever
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

    # Chunk candidates into batches of CHECK_BATCH
    batches = [candidates[i:i + CHECK_BATCH]
               for i in range(0, len(candidates), CHECK_BATCH)]

    updated = stored = 0
    with ThreadPoolExecutor(max_workers=workers) as pool:
        for u, s in pool.map(check_one_batch, batches):
            updated += u
            stored += s

    # Apply results to DB in one pass
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
            "Bewerte die Kindgerechtheit dieser Sätze:\n"
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
                "Schreibe kindgerechte Ersatzsätze (max. 12 Wörter) für:\n"
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
# Correct pass — full-entry LLM improvement (data-safe)
# ---------------------------------------------------------------------------

def run_correct(
    con: sqlite3.Connection,
    llm: LLMClient,
    rows: list[dict],
    dry_run: bool,
    limit: int | None,
) -> tuple[int, int]:
    """Send enrichment_json to a capable LLM for semantic/definition improvement.

    Only writes back fields in CORRECT_ENRICH_FIELDS. If the LLM returns
    corrupt JSON or the wrong type for any field, the entry is skipped entirely.
    Original data is never destroyed — we copy first, validate, then write.
    """
    # Prefer entries that have definitions to improve
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

        # Build a minimal context for the LLM (strip large/noisy fields)
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

        # Validate and allowlist — any type error → skip whole entry
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

        # Apply patch
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
    """Case-insensitive key lookup in LLM response dict."""
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
# Vorname fill — no LLM needed
# ---------------------------------------------------------------------------

def run_fill_vornamen(
    con: sqlite3.Connection,
    rows: list[dict],
    dry_run: bool,
    limit: int | None,
) -> int:
    """Populate grade_examples for VORNAME entries without LLM.

    Builds a shared pool of sentences from ALL Vorname gutenberg_examples,
    replacing each name with ``[Name]`` so any sentence works for any name.
    Each entry gets up to 6 sentences from the pool (same across all grade
    levels — reading-level distinction is meaningless for proper nouns).
    """
    import re as _re
    import random as _random

    all_vornamen = [
        r for r in rows
        if "VORNAME_STANDESAMT" in (_meta(r).get("sources") or [])
    ]
    candidates = [
        r for r in all_vornamen
        if not _meta(r).get("grade_examples")
    ]
    if limit:
        candidates = candidates[:limit]
    print(f"Vorname fill pass: {len(candidates)} names need examples "
          f"(pool built from {len(all_vornamen)} total Vornamen)")
    if not candidates:
        return 0

    # Build a shared pool: for each Vorname that has gutenberg_examples,
    # replace the name with [Name] and collect the sentence.
    pool: list[str] = []
    seen: set[str] = set()
    for r in all_vornamen:
        word = r["word"]
        gutenberg = _meta(r).get("gutenberg_examples") or []
        pat = _re.compile(r'\b' + _re.escape(word) + r'\b')
        for sent in gutenberg:
            if pat.search(sent):
                generic = pat.sub("[Name]", sent)
                if generic not in seen:
                    seen.add(generic)
                    pool.append(generic)

    print(f"  Shared pool: {len(pool)} generic sentences")
    if not pool:
        print("  No pool — no Vorname entries have gutenberg_examples yet. "
              "Run add_gutenberg_examples.py first.")
        return 0

    _random.shuffle(pool)
    POOL_PER_NAME = 6

    updated = 0
    for r in candidates:
        sents = pool[:POOL_PER_NAME]
        # All grade levels share the same sentences
        grade_examples = {str(g): sents for g in range(1, 7)}
        meta = _meta(r)
        meta["grade_examples"] = grade_examples
        _write(con, r, meta, dry_run)
        updated += 1

    print(f"Vorname fill: {updated} entries updated")
    return updated


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

_TASCHENMESSER = "gab ihm ein nagelneues Taschenmesser"


def run_cleanup(src_db: Path, wipe_partials: bool = False, dry_run: bool = False) -> None:
    """Wipe garbage grade_examples from the source DB directly (no working.db needed).

    - Always: remove Taschenmesser-fingerprint entries (Vorname garbage from corpus).
    - With wipe_partials: also remove structurally incomplete grade blocks and
      purge those IDs from grade_results.jsonl so the next --grade pass re-generates.
    """
    con = sqlite3.connect(str(src_db))
    rows = con.execute("SELECT id, metadata_json FROM words").fetchall()

    dupe_wiped = partial_wiped = 0
    partial_ids: set[int] = set()

    for row_id, m in rows:
        meta = json.loads(m) if m else {}
        ge = meta.get("grade_examples")
        if not ge:
            continue
        first_sents = [ge.get(g, [""])[0] for g in "123456" if ge.get(g)]
        if first_sents and _TASCHENMESSER in first_sents[0]:
            if not dry_run:
                del meta["grade_examples"]
                con.execute("UPDATE words SET metadata_json=? WHERE id=?",
                            (json.dumps(meta, ensure_ascii=False), row_id))
            dupe_wiped += 1
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

    print(f"Cleanup: wiped {dupe_wiped} dupe (Taschenmesser) entries"
          + (f", {partial_wiped} partial entries" if wipe_partials else ""))

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
                    help="Review grade_examples: fix grammar/semantics, fill empty grades. "
                         "Default: only words with structural gaps.")
    ap.add_argument("--check-all", action="store_true",
                    help="Like --check but reviews every graded word, not just gap words.")
    ap.add_argument("--fill-vornamen", action="store_true",
                    help="Populate grade_examples for VORNAME entries from their "
                         "gutenberg_examples (no LLM — replaces name with [Name] placeholder)")
    ap.add_argument("--cleanup", action="store_true",
                    help="Wipe grade_examples that are Taschenmesser-fingerprint dupes "
                         "(Vorname garbage). Safe to run after any grade pass.")
    ap.add_argument("--wipe-partials", action="store_true",
                    help="Combined with --cleanup: also wipe grade_examples for words "
                         "with structural gaps, and remove them from grade_results.jsonl "
                         "so the next --grade pass regenerates them fresh.")
    ap.add_argument("--no-compress", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--batch-size", type=int, default=DEFAULT_BATCH)
    ap.add_argument("--workers", type=int, default=1,
                    help="Worker pool size for grade pass (default 1)")
    args = ap.parse_args()

    if not any([args.fill, args.grade, args.review, args.correct,
                args.fill_vornamen, args.check, args.check_all, args.cleanup]):
        args.fill = True   # default

    src_db = Path(args.db)
    if not src_db.exists():
        sys.exit(f"ERROR: DB not found: {src_db}")

    if args.cleanup:
        run_cleanup(src_db, wipe_partials=args.wipe_partials, dry_run=args.dry_run)
        if not any([args.fill, args.grade, args.review, args.correct,
                    args.fill_vornamen, args.check, args.check_all]):
            print("Done.")
            return 0

    needs_llm = any([args.fill, args.grade, args.review, args.correct,
                     args.check, args.check_all])
    needs_work_db = needs_llm or args.fill_vornamen
    llm: LLMClient | None = None
    if needs_llm:
        try:
            llm = LLMClient()
        except RuntimeError as e:
            sys.exit(f"ERROR: {e}")

    WORK_DB.parent.mkdir(parents=True, exist_ok=True)

    # Safety: if working.db already exists and has more grade_examples than
    # the source DB, it's an interrupted run — resume from it rather than
    # wiping it.  Only replace if src_db has equal-or-more progress, or if
    # the source IS the working db (would self-delete).
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
        # Resume from working.db only if it is NEWER than src_db (interrupted run).
        # If src_db is newer, user modified it (e.g. wiped entries) — start fresh.
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

    if args.fill_vornamen:
        n = run_fill_vornamen(con, rows, args.dry_run, args.limit)
        print(f"\nVorname fill: {n} entries updated")
        total_updated += n

    if args.fill:
        n, s = run_fill(con, llm, rows, args.batch_size, args.dry_run, args.limit)
        print(f"\nFill: {n} entries updated, {s} sentences stored")
        total_updated += n

    if args.grade:
        # Re-read rows so fill results are visible to grade pass
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
