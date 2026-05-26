"""Tag EN DB entries with UK primary school statutory word lists and compute gradeLevelEstimate.

Sources:
  - UK National Curriculum statutory word lists (DfE, published under OGL v3)
    Year 1-2 common exception words, Year 3-4 word list, Year 5-6 word list.
    OGL v3: commercial use permitted. https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/

Tags added to metadata_json["tags"]:
  source:uk_y1_y2   — Year 1-2 common exception words
  source:uk_y3_y4   — Year 3-4 statutory word list
  source:uk_y5_y6   — Year 5-6 statutory word list

Computes metadata_json["gradeLevelEstimate"] (int 1-6) using decision tree:
  Priority 1: curriculum caps (Y1-Y2 → ≤2, Starters → ≤2, Y3-Y4/Movers → ≤3,
                               Y5-Y6/Flyers → ≤4, A1 → ≤2, A2 → ≤3, B1 → ≤4, B2 → ≤5)
  Priority 2: frequency band baseline (band 1→1, 2→2, 3→3, 4→5, 5→6)
  Result: min(cap, freq_baseline)

Usage:
  python add_uk_curriculum.py [--db grundwortschatz_en.db] [--no-compress] [--dry-run]
"""

from __future__ import annotations

import argparse
import gzip
import json
import shutil
import sqlite3
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
DEFAULT_DB = HERE / "grundwortschatz_en.db"
WORK_DB    = Path("/tmp/dbpatch_uk_curriculum_en/working.db")
DB_GZ      = REPO / "assets" / "grundwortschatz_en.db.gz"

# ---------------------------------------------------------------------------
# UK DfE Statutory word lists (OGL v3 — commercial use permitted)
# https://www.gov.uk/government/publications/letters-and-sounds
# ---------------------------------------------------------------------------

UK_Y1_Y2: set[str] = {
    # Year 1 common exception words
    "the", "a", "do", "to", "today", "of", "said", "says", "are", "were",
    "was", "is", "his", "has", "I", "you", "your", "they", "be", "he",
    "she", "we", "me", "no", "go", "so", "by", "my", "here", "there",
    "where", "love", "come", "some", "one", "once", "ask", "friend",
    "school", "put", "push", "pull", "full", "house", "our",
    # Year 2 common exception words
    "could", "would", "should", "door", "floor", "poor", "because", "find",
    "kind", "mind", "behind", "child", "children", "wild", "climb", "most",
    "only", "both", "old", "cold", "gold", "hold", "told", "every", "even",
    "great", "break", "steak", "pretty", "beautiful", "after", "fast",
    "last", "past", "class", "grass", "pass", "plant", "path", "bath",
    "hour", "move", "prove", "improve", "sure", "sugar", "eye", "could",
    "water", "want", "watch", "what", "why", "when", "which", "who",
    "whole", "any", "many", "again", "half", "money", "people", "oh",
    "their", "father", "Christmas",
}

UK_Y3_Y4: set[str] = {
    "accident", "actually", "address", "answer", "appear", "arrive",
    "believe", "bicycle", "breath", "breathe", "build", "busy", "calendar",
    "caught", "centre", "century", "certain", "circle", "complete",
    "consider", "continue", "decide", "describe", "different", "difficult",
    "disappear", "early", "earth", "eight", "enough", "exercise",
    "experience", "experiment", "extreme", "famous", "favourite", "February",
    "forward", "fruit", "grammar", "group", "guard", "guide", "heard",
    "heart", "height", "history", "imagine", "increase", "important",
    "interest", "island", "knowledge", "learn", "length", "library",
    "material", "medicine", "mention", "minute", "natural", "naughty",
    "notice", "occasion", "often", "opposite", "ordinary", "particular",
    "peculiar", "perhaps", "popular", "position", "possess", "possible",
    "potatoes", "pressure", "probably", "promise", "purpose", "quarter",
    "question", "recent", "regular", "reign", "remember", "sentence",
    "separate", "special", "straight", "strange", "strength", "suppose",
    "surprise", "therefore", "though", "thought", "through", "various",
    "weight", "woman", "women",
}

UK_Y5_Y6: set[str] = {
    "accommodate", "accompany", "aggressive", "amateur", "ancient",
    "apparent", "appreciate", "attached", "available", "average", "awkward",
    "bargain", "bruise", "category", "cemetery", "committee", "communicate",
    "community", "competition", "conscience", "conscious", "controversy",
    "convenience", "correspond", "criticise", "curiosity", "definite",
    "desperate", "determined", "develop", "dictionary", "disastrous",
    "embarrass", "environment", "equip", "especially", "exaggerate",
    "excellent", "existence", "explanation", "familiar", "foreign",
    "frequently", "government", "guarantee", "harass", "hindrance",
    "identity", "immediate", "individual", "interfere", "interrupt",
    "language", "leisure", "lightning", "marvellous", "mischievous",
    "muscle", "necessary", "neighbour", "nuisance", "occupy", "occur",
    "parliament", "persuade", "physical", "prejudice", "privilege",
    "profession", "programme", "pronunciation", "queue", "recognise",
    "recommend", "relevant", "restaurant", "rhyme", "rhythm", "sacrifice",
    "secretary", "shoulder", "signature", "sincere", "soldier", "stomach",
    "sufficient", "suggest", "symbol", "system", "temperature", "thorough",
    "twelfth", "variety", "vegetable", "vehicle", "yacht",
}

_Y1_Y2_LOWER = {w.lower() for w in UK_Y1_Y2}
_Y3_Y4_LOWER = {w.lower() for w in UK_Y3_Y4}
_Y5_Y6_LOWER = {w.lower() for w in UK_Y5_Y6}

TAG_Y1_Y2 = "source:uk_y1_y2"
TAG_Y3_Y4 = "source:uk_y3_y4"
TAG_Y5_Y6 = "source:uk_y5_y6"

# CEFR caps: max grade for a word at this level
_CEFR_CAPS = {"A1": 2, "A2": 3, "B1": 4, "B2": 5, "C1": 6, "C2": 6}
# Frequency band → baseline grade
_BAND_GRADE = {1: 1, 2: 2, 3: 3, 4: 5, 5: 6}
# Dolch sight-word grade groups → cap
_DOLCH_CAPS = {"dolch_g1": 2, "dolch_g2": 3, "dolch_g3": 3}
# Fry 1k word batches (each = 100 words, ranked by frequency) → cap
_FRY_CAPS = {
    "fry_b1": 1, "fry_b2": 2, "fry_b3": 2, "fry_b4": 3,
    "fry_b5": 3, "fry_b6": 4, "fry_b7": 4, "fry_b8": 4,
    "fry_b9": 5, "fry_b10": 5,
}


def compute_grade_estimate(meta: dict, frequency_json: str | None) -> int:
    freq = json.loads(frequency_json or "{}")
    band = freq.get("frequency_band", 4)
    freq_baseline = _BAND_GRADE.get(band, 4)

    tags = meta.get("tags") or []
    cap = 6

    # Curriculum/YLE caps (take the lowest/easiest)
    if TAG_Y1_Y2 in tags or "source:cambridge_yle_starters" in tags:
        cap = min(cap, 2)
    elif TAG_Y3_Y4 in tags or "source:cambridge_yle_movers" in tags:
        cap = min(cap, 3)
    elif TAG_Y5_Y6 in tags or "source:cambridge_yle_flyers" in tags:
        cap = min(cap, 4)

    # CEFR cap
    cefr = meta.get("cefr_level", "")
    if cefr in _CEFR_CAPS:
        cap = min(cap, _CEFR_CAPS[cefr])

    # Dolch + Fry caps (based on tags already in DB from step 00_fetch_sources)
    for tag in tags:
        if tag in _DOLCH_CAPS:
            cap = min(cap, _DOLCH_CAPS[tag])
        if tag in _FRY_CAPS:
            cap = min(cap, _FRY_CAPS[tag])

    return min(cap, freq_baseline)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--db",           default=str(DEFAULT_DB))
    ap.add_argument("--no-compress",  action="store_true")
    ap.add_argument("--dry-run",      action="store_true")
    ap.add_argument("--overwrite",    action="store_true",
                    help="Re-tag and re-compute even if already done")
    ap.add_argument("--grade-only",   action="store_true",
                    help="Only recompute gradeLevelEstimate, skip curriculum tagging")
    args = ap.parse_args()

    src_db = Path(args.db)
    if not src_db.exists():
        sys.exit(f"ERROR: DB not found: {src_db}")

    WORK_DB.parent.mkdir(parents=True, exist_ok=True)
    if WORK_DB.exists():
        WORK_DB.unlink()
    shutil.copy2(src_db, WORK_DB)

    con = sqlite3.connect(str(WORK_DB))
    con.row_factory = sqlite3.Row

    rows = con.execute(
        "SELECT id, word, lemma, metadata_json, frequency_json FROM words"
    ).fetchall()
    rows = [dict(r) for r in rows]
    print(f"Loaded {len(rows)} DB entries")

    y_counts = {TAG_Y1_Y2: 0, TAG_Y3_Y4: 0, TAG_Y5_Y6: 0}
    grade_dist: dict[int, int] = {}
    tagged = 0
    updated = 0

    for r in rows:
        meta = json.loads(r["metadata_json"] or "{}")

        if not args.overwrite and not args.grade_only and meta.get("gradeLevelEstimate"):
            # Already processed — just skip
            continue

        word  = (r.get("word")  or "").strip().lower()
        lemma = (r.get("lemma") or "").strip().lower()

        tags: list[str] = list(meta.get("tags") or [])
        changed = False

        if not args.grade_only:
            for words_set, tag in [
                (_Y1_Y2_LOWER, TAG_Y1_Y2),
                (_Y3_Y4_LOWER, TAG_Y3_Y4),
                (_Y5_Y6_LOWER, TAG_Y5_Y6),
            ]:
                in_list = word in words_set or (lemma and lemma != word and lemma in words_set)
                if in_list and tag not in tags:
                    tags.append(tag)
                    y_counts[tag] += 1
                    changed = True

        meta["tags"] = tags
        grade = compute_grade_estimate(meta, r.get("frequency_json"))
        meta["gradeLevelEstimate"] = grade
        grade_dist[grade] = grade_dist.get(grade, 0) + 1
        updated += 1

        if not args.dry_run:
            con.execute(
                "UPDATE words SET metadata_json = ?, grade_level = ? WHERE id = ?",
                (json.dumps(meta, ensure_ascii=False), grade, r["id"]),
            )

    if not args.dry_run:
        con.commit()
    con.close()

    print(f"Updated:   {updated}")
    print(f"UK Y1-Y2:  {y_counts[TAG_Y1_Y2]}")
    print(f"UK Y3-Y4:  {y_counts[TAG_Y3_Y4]}")
    print(f"UK Y5-Y6:  {y_counts[TAG_Y5_Y6]}")
    print("Grade level estimate distribution:")
    for g in sorted(grade_dist):
        print(f"  Grade {g}: {grade_dist[g]}")

    if not args.dry_run:
        print(f"Copying {WORK_DB} → {src_db}")
        shutil.copy2(WORK_DB, src_db)
        if not args.no_compress and DB_GZ.exists():
            print(f"Compressing → {DB_GZ}")
            with src_db.open("rb") as fi, gzip.open(DB_GZ, "wb", compresslevel=9) as fo:
                shutil.copyfileobj(fi, fo)
            print(f"  {DB_GZ.stat().st_size // 1024} KB")

    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
