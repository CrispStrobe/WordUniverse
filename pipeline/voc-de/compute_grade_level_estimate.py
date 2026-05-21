"""Add a per-word `gradeLevelEstimate` (1–6) to metadata_json,
algorithmically derived from childLex age-presence + DWDS
Häufigkeitsklasse + existing NRW-derived grade_level.

The existing `words.grade_level` column is NRW/Goethe-derived and
authoritative for the ~1500 words it covers cleanly; the remaining
~9000 words sit at `grade_level=5` (placeholder default for "above
primary core") or `grade_level=6` (Sekundarstufe-tier vocabulary). For
those, this script computes a finer-grained estimate using the
childLex age-graded norms integrated in commit b6d084d.

Algorithm:
  - If grade_level ∈ {1,2,3,4} (NRW-derived): trust it; estimate = grade_level.
  - Else (grade_level ∈ {5,6}):
      Look at the earliest childLex age band where lemma.freq.norm >= 5.0
      (a "substantive presence" cutoff, occurrences per million):
        Age 1 (ages 6–8 / Kl 1–2): split → Kl 1 if freq ≥ 50, else Kl 2
        Age 2 (ages 9–10 / Kl 3–4): split → Kl 3 if freq ≥ 30, else Kl 4
        Age 3 (ages 11–12 / Kl 5–6): split → Kl 5 if freq ≥ 10, else Kl 6
      If no substantive childLex presence (or word not in childLex):
        Use DWDS frequenzklasse as fallback:
          fk ≥ 5  → Kl 2  (very common in adult corpus, would be Kl 1-2)
          fk = 3-4 → Kl 4  (medium frequency)
          fk = 0-2 → Kl 6  (rare; specialized vocabulary)
        If no DWDS data either: keep the original grade_level.

The estimate is stored in `metadata_json.gradeLevelEstimate` as an
integer 1–6. `metadata_json.gradeLevelEstimateSource` is one of:
  "nrw"               — copied from authoritative NRW grade_level 1–4
  "childlex_age1"     — derived from childLex Age 1 frequency
  "childlex_age2"     — derived from childLex Age 2 frequency
  "childlex_age3"     — derived from childLex Age 3 frequency
  "dwds_fallback"     — derived from DWDS frequenzklasse (no childLex)
  "original"          — kept original grade_level (no signals)
"""

from __future__ import annotations

import gzip
import json
import sqlite3
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DB_GZ = REPO / "assets" / "grundwortschatz.db.gz"
WORK = Path("/tmp/dbpatch/working.db")

# childLex "substantive presence" threshold (occ. per million).
PRESENCE_THRESHOLD = 5.0

# Within-age-band sub-thresholds (occ. per million).
AGE1_HIGH = 50.0  # Age 1 high → Kl 1, low → Kl 2
AGE2_HIGH = 30.0  # Age 2 high → Kl 3, low → Kl 4
AGE3_HIGH = 10.0  # Age 3 high → Kl 5, low → Kl 6


def estimate_from_childlex(cl: dict | None) -> tuple[int | None, str | None]:
    if not isinstance(cl, dict):
        return None, None
    a1 = cl.get("age1_freq_norm")
    a2 = cl.get("age2_freq_norm")
    a3 = cl.get("age3_freq_norm")
    # Earliest age band with substantive presence wins.
    if isinstance(a1, (int, float)) and a1 >= PRESENCE_THRESHOLD:
        return (1 if a1 >= AGE1_HIGH else 2), "childlex_age1"
    if isinstance(a2, (int, float)) and a2 >= PRESENCE_THRESHOLD:
        return (3 if a2 >= AGE2_HIGH else 4), "childlex_age2"
    if isinstance(a3, (int, float)) and a3 >= PRESENCE_THRESHOLD:
        return (5 if a3 >= AGE3_HIGH else 6), "childlex_age3"
    return None, None


def estimate_from_dwds(d: dict | None) -> tuple[int | None, str | None]:
    if not isinstance(d, dict):
        return None, None
    fk = d.get("frequenzklasse")
    if not isinstance(fk, int):
        return None, None
    if fk >= 5:
        return 2, "dwds_fallback"
    if fk in (3, 4):
        return 4, "dwds_fallback"
    return 6, "dwds_fallback"


def main() -> int:
    if not DB_GZ.exists():
        print(f"ERROR: shipped DB not found: {DB_GZ}", file=sys.stderr)
        return 1

    WORK.parent.mkdir(parents=True, exist_ok=True)
    if WORK.exists():
        WORK.unlink()
    print(f"Decompressing {DB_GZ} -> {WORK}")
    with gzip.open(DB_GZ, "rb") as fi, WORK.open("wb") as fo:
        fo.write(fi.read())

    con = sqlite3.connect(str(WORK))
    con.row_factory = sqlite3.Row
    cur = con.cursor()
    cur.execute(
        "SELECT id, word, lemma, grade_level, frequency_json, metadata_json FROM words"
    )
    rows = cur.fetchall()

    update_cur = con.cursor()
    estimate_dist: dict[int, int] = {}
    source_dist: dict[str, int] = {}
    grade_level_unchanged = 0

    for r in rows:
        try:
            meta = json.loads(r["metadata_json"]) if r["metadata_json"] else {}
        except json.JSONDecodeError:
            meta = {}
        if not isinstance(meta, dict):
            meta = {}
        try:
            freq = json.loads(r["frequency_json"]) if r["frequency_json"] else {}
        except json.JSONDecodeError:
            freq = {}

        grade = r["grade_level"]
        estimate: int | None
        source: str

        if isinstance(grade, int) and 1 <= grade <= 4:
            estimate = grade
            source = "nrw"
        else:
            est, src = estimate_from_childlex(freq.get("childlex"))
            if est is None:
                est, src = estimate_from_dwds(freq.get("dwds"))
            if est is None:
                estimate = grade if isinstance(grade, int) else 5
                source = "original"
                grade_level_unchanged += 1
            else:
                estimate = est
                source = src or "unknown"

        meta["gradeLevelEstimate"] = estimate
        meta["gradeLevelEstimateSource"] = source

        update_cur.execute(
            "UPDATE words SET metadata_json = ? WHERE id = ?",
            (json.dumps(meta, ensure_ascii=False), r["id"]),
        )
        estimate_dist[estimate] = estimate_dist.get(estimate, 0) + 1
        source_dist[source] = source_dist.get(source, 0) + 1

    con.commit()
    con.close()

    print(f"Processed {len(rows)} words")
    print("gradeLevelEstimate distribution:")
    for k in sorted(estimate_dist.keys()):
        print(f"  Kl {k}: {estimate_dist[k]}")
    print("source distribution:")
    for k, v in sorted(source_dist.items(), key=lambda x: -x[1]):
        print(f"  {k}: {v}")

    print(f"Compressing {WORK} -> {DB_GZ}")
    with WORK.open("rb") as fi, gzip.open(DB_GZ, "wb", compresslevel=9) as fo:
        fo.write(fi.read())
    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
