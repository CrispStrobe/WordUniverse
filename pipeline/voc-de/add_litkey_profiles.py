"""Compute per-lemma LiTKey spelling-difficulty profiles and store in DE DB.

For each vocabulary entry matched in LiTKey we aggregate and write to
metadata_json:

  litkey_error_rate: float        — erroneous tokens / total tokens (0.0–1.0)
  litkey_error_profile: dict      — fraction of erroneous tokens per error type
                                    (only non-zero categories; keys match NRW
                                    morphematisches Prinzip names)
  litkey_grade_first_correct: int — lowest grade (2/3/4) with ≥1 correct token
  litkey_word_features: dict      — word-level phonological/orthographic features
                                    that apply to this word regardless of errors
                                    (e.g. devoice_final=1 means the word has
                                    Auslautverhärtung)
  litkey_orth_neighbourhood: dict — orthographic neighbourhood metrics from
                                    childLex: bigram_sum and old20 (Levenshtein
                                    distance to 20 nearest neighbours; lower =
                                    more confusable)

Additionally, spellingDifficulty (enum index 0–3) is recomputed from
litkey_error_rate when LiTKey data is available:
  0.00–0.25 → easy   (0)
  0.25–0.50 → medium (1)
  0.50–0.75 → hard   (2)
  0.75–1.00 → expert (3)

LiTKey error-type columns (err_* prefix stripped in output):
  graph_comb   — grapheme combinations (ch/sch/ng/ck)
  graph_marked — marked graphemes (special spelling rules)
  ie           — ie/ieh distinction
  schwa_silent — schwa deletion / silent vowels
  doubleC_syl  — doubled consonants (syllabic: Halle/halle)
  doubleC_other— doubled consonants (other: agg/ball)
  doubleV      — doubled vowels (aa/ee/oo)
  h_length     — Dehnungs-h (Wal/Wahl)
  h_sep        — Silbentrennungs-h (gehen/sehen)
  r_voc        — vocalic r (er→ä pronunciation)
  devoice_final— Auslautverhärtung (d→t, b→p at word end)
  g_spirant    — g-spirantisation (tag→tage)
  morph_bound  — morpheme boundary errors
  hyp          — hyphenation errors
  other        — residual errors

Word-level feature columns (no err_ prefix — properties of the word itself):
  graph_comb, graph_marked, ie, schwa_silent, doubleC_syl, doubleC_other,
  doubleV, h_length, h_sep, r_voc, devoice_final, g_spirant, morph_bound

Orthographic neighbourhood columns from childLex:
  chl_bigram.sum  — sum of bigram frequencies (higher = easier to type)
  chl_nei.old20   — mean Levenshtein distance to 20 nearest neighbours
                    (lower = more confusable with other words)

Idempotent: safe to re-run; existing litkey_* fields are overwritten.

Usage:
  python add_litkey_profiles.py [--db grundwortschatz.db] [--no-compress]
"""

from __future__ import annotations

import argparse
import csv
import gzip
import json
import shutil
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]

DEFAULT_DB = HERE / "grundwortschatz.db"
WORK_DB = Path("/tmp/dbpatch_litkey_profiles/working.db")
DB_GZ = REPO / "assets" / "grundwortschatz.db.gz"
CSV_LOCAL = HERE / "sources" / "Litkey-Tab.csv"

# Error-type flags (err_<col> in CSV)
ERR_COLS = [
    "graph_comb", "graph_marked", "ie", "schwa_silent",
    "doubleC_syl", "doubleC_other", "doubleV",
    "h_length", "h_sep", "r_voc",
    "devoice_final", "g_spirant", "morph_bound",
    "hyp", "other",
]

# Word-level phonological feature flags (same names, no err_ prefix)
FEAT_COLS = [
    "graph_comb", "graph_marked", "ie", "schwa_silent",
    "doubleC_syl", "doubleC_other", "doubleV",
    "h_length", "h_sep", "r_voc",
    "devoice_final", "g_spirant", "morph_bound",
]

# childLex neighbourhood columns
CHL_BIGRAM = "chl_bigram.sum"
CHL_OLD20 = "chl_nei.old20"


def _parse_float(s: str) -> float | None:
    s = s.strip()
    if not s or s == "NA":
        return None
    try:
        return float(s)
    except ValueError:
        return None


def _parse_int(s: str) -> int | None:
    s = s.strip()
    if not s or s == "NA":
        return None
    try:
        return int(s)
    except ValueError:
        return None


def error_rate_to_difficulty(rate: float) -> int:
    if rate < 0.25:
        return 0  # easy
    if rate < 0.50:
        return 1  # medium
    if rate < 0.75:
        return 2  # hard
    return 3      # expert


# ---------------------------------------------------------------------------
# Parse LiTKey CSV → per-target aggregates
# ---------------------------------------------------------------------------

def aggregate_litkey(csv_path: Path) -> dict[str, dict]:
    """Return {target_lower: aggregate_dict} for all targets in the corpus."""
    total: dict[str, int] = defaultdict(int)
    errors: dict[str, int] = defaultdict(int)
    grade_correct: dict[str, set] = defaultdict(set)
    err_counts: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))

    # Word-level features: take majority vote across all tokens for this target
    feat_votes: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    feat_total: dict[str, int] = defaultdict(int)

    # childLex neighbourhood: constant per target — collect first non-NA value
    chl_bigram: dict[str, float] = {}
    chl_old20: dict[str, float] = {}

    with csv_path.open(encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        for row in reader:
            target = (row.get("target") or "").strip()
            if not target:
                continue
            tl = target.lower()

            try:
                erroneous = int(row.get("erroneous", "0") or "0")
            except ValueError:
                continue

            try:
                grade = int(row.get("grade", "0") or "0")
            except ValueError:
                grade = 0

            total[tl] += 1

            # Error-type flags — only from erroneous rows
            if erroneous == 1:
                errors[tl] += 1
                for col in ERR_COLS:
                    try:
                        val = int(row.get(f"err_{col}", "0") or "0")
                    except ValueError:
                        val = 0
                    if val:
                        err_counts[tl][col] += 1
            else:
                if grade:
                    grade_correct[tl].add(grade)

            # Word-level feature flags — all rows (majority vote)
            feat_total[tl] += 1
            for col in FEAT_COLS:
                try:
                    val = int(row.get(col, "0") or "0")
                except ValueError:
                    val = 0
                if val:
                    feat_votes[tl][col] += 1

            # childLex neighbourhood — first non-NA value wins
            if tl not in chl_bigram:
                v = _parse_float(row.get(CHL_BIGRAM, "NA") or "NA")
                if v is not None:
                    chl_bigram[tl] = v
            if tl not in chl_old20:
                v = _parse_float(row.get(CHL_OLD20, "NA") or "NA")
                if v is not None:
                    chl_old20[tl] = v

    result: dict[str, dict] = {}
    for tl in total:
        n_total = total[tl]
        n_err = errors.get(tl, 0)
        error_rate = n_err / n_total if n_total else 0.0

        # Error-type profile (fraction of erroneous tokens per category)
        profile: dict[str, float] = {}
        if n_err:
            for col, cnt in err_counts.get(tl, {}).items():
                profile[col] = round(cnt / n_err, 4)

        # Word-level features (majority vote: flag set in >50% of tokens)
        n_feat = feat_total.get(tl, 0)
        word_features: dict[str, int] = {}
        if n_feat:
            for col, cnt in feat_votes.get(tl, {}).items():
                if cnt / n_feat > 0.5:
                    word_features[col] = 1

        # childLex neighbourhood
        orth_neighbourhood: dict[str, float] = {}
        if tl in chl_bigram:
            orth_neighbourhood["bigram_sum"] = chl_bigram[tl]
        if tl in chl_old20:
            orth_neighbourhood["old20"] = chl_old20[tl]

        correct_grades = grade_correct.get(tl)

        result[tl] = {
            "litkey_error_rate": round(error_rate, 4),
            "litkey_error_profile": profile,
            "litkey_grade_first_correct": min(correct_grades) if correct_grades else None,
            "litkey_word_features": word_features,
            "litkey_orth_neighbourhood": orth_neighbourhood,
            "litkey_total_tokens": n_total,
            "litkey_error_tokens": n_err,
        }

    return result


# ---------------------------------------------------------------------------
# Inflection-aware index
# ---------------------------------------------------------------------------

def build_index(rows: list[sqlite3.Row]) -> dict[str, int]:
    idx: dict[str, int] = {}
    for i, r in enumerate(rows):
        w = (r["word"] or "").strip()
        if w:
            idx.setdefault(w.lower(), i)
    for i, r in enumerate(rows):
        lm = (r["lemma"] or "").strip()
        if lm:
            idx.setdefault(lm.lower(), i)
    for i, r in enumerate(rows):
        try:
            meta = json.loads(r["metadata_json"]) if r["metadata_json"] else {}
        except (json.JSONDecodeError, TypeError):
            meta = {}
        for infl in meta.get("wiktionaryInflections") or []:
            if isinstance(infl, dict):
                ft = (infl.get("form_text") or "").strip()
                if ft:
                    idx.setdefault(ft.lower(), i)
    return idx


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--db", default=str(DEFAULT_DB))
    ap.add_argument("--no-compress", action="store_true")
    args = ap.parse_args()

    if not CSV_LOCAL.exists():
        print(f"ERROR: {CSV_LOCAL} not found — run add_litkey_errors.py first",
              file=sys.stderr)
        return 1

    src_db = Path(args.db)
    if not src_db.exists():
        print(f"ERROR: DB not found: {src_db}", file=sys.stderr)
        return 1

    print("Aggregating LiTKey profiles …")
    profiles = aggregate_litkey(CSV_LOCAL)
    print(f"  {len(profiles)} distinct targets in corpus")

    WORK_DB.parent.mkdir(parents=True, exist_ok=True)
    if WORK_DB.exists():
        WORK_DB.unlink()
    print(f"Copying {src_db} → {WORK_DB}")
    shutil.copy2(src_db, WORK_DB)

    con = sqlite3.connect(str(WORK_DB))
    con.row_factory = sqlite3.Row
    rows = con.execute("SELECT id, word, lemma, metadata_json FROM words").fetchall()
    print(f"Loaded {len(rows)} DB entries")

    idx = build_index(rows)
    print(f"  inflection index has {len(idx)} keys")

    # Accumulate per row-index (multiple targets can share the same headword)
    row_profiles: dict[int, dict] = {}
    skipped = 0
    for target_l, prof in profiles.items():
        i = idx.get(target_l)
        if i is None:
            skipped += 1
            continue
        existing = row_profiles.get(i)
        if existing is None or prof["litkey_total_tokens"] > existing["litkey_total_tokens"]:
            row_profiles[i] = prof

    updated = 0
    difficulty_changed = 0
    row_list = [dict(r) for r in rows]

    for i, prof in row_profiles.items():
        r = row_list[i]
        try:
            meta = json.loads(r["metadata_json"]) if r["metadata_json"] else {}
        except (json.JSONDecodeError, TypeError):
            meta = {}

        meta["litkey_error_rate"] = prof["litkey_error_rate"]
        meta["litkey_error_profile"] = prof["litkey_error_profile"]
        meta["litkey_grade_first_correct"] = prof["litkey_grade_first_correct"]
        if prof["litkey_word_features"]:
            meta["litkey_word_features"] = prof["litkey_word_features"]
        if prof["litkey_orth_neighbourhood"]:
            meta["litkey_orth_neighbourhood"] = prof["litkey_orth_neighbourhood"]

        new_diff = error_rate_to_difficulty(prof["litkey_error_rate"])
        old_diff = meta.get("spellingDifficulty", 0)
        if old_diff != new_diff:
            meta["spellingDifficulty"] = new_diff
            difficulty_changed += 1

        con.execute(
            "UPDATE words SET metadata_json = ? WHERE id = ?",
            (json.dumps(meta, ensure_ascii=False), r["id"]),
        )
        updated += 1

    con.commit()
    con.close()

    print()
    print(f"Updated {updated} entries with LiTKey profiles.")
    print(f"  spellingDifficulty updated: {difficulty_changed}")
    print(f"  targets not in vocab:       {skipped}")

    print(f"Copying {WORK_DB} → {src_db}")
    shutil.copy2(WORK_DB, src_db)

    if not args.no_compress:
        if DB_GZ.exists():
            print(f"Compressing {src_db} → {DB_GZ}")
            with src_db.open("rb") as fi, gzip.open(DB_GZ, "wb", compresslevel=9) as fo:
                shutil.copyfileobj(fi, fo)
            print(f"  {DB_GZ.stat().st_size // 1024} KB written")
        else:
            print(f"  [warn] {DB_GZ} not found", file=sys.stderr)

    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
