"""Add a per-word `gradeLevelEstimate` and evidence to metadata_json.

The existing `words.grade_level` column can have different upstream origins.
Its numeric value alone does not identify NRW, BW, or any other source.
Explicit `gradeLevelSource` and `gradeLevelEvidence` metadata are preserved
when supplied; an old estimate-source label is not evidence of that origin.

This script retains the existing numeric decision rules. Its childLex and
DWDS mappings are frequency-based heuristics, not calibrated school-grade
measurements or official curriculum assignments.

Algorithm:
  - If grade_level ∈ {1,2,3,4}: copy it; estimate = grade_level.
  - Else:
      Look at the earliest childLex age band where lemma.freq.norm >= 5.0
      (a "substantive presence" cutoff, occurrences per million):
        Age 1 (ages 6–8 / Kl 1–2): split → Kl 1 if freq ≥ 50, else Kl 2
        Age 2 (ages 9–10 / Kl 3–4): split → Kl 3 if freq ≥ 30, else Kl 4
        Age 3 (ages 11–12 / Kl 5–6): split → Kl 5 if freq ≥ 10, else Kl 6
      If no substantive childLex presence (or word not in childLex):
        Use DWDS frequenzklasse as fallback:
          integer fk ≥ 5  → Kl 2
          integer fk = 3-4 → Kl 4
          other integer fk → Kl 6
        If no DWDS data either: keep an integer original grade_level,
        otherwise use the existing default of 5.

The heuristic rules produce grades 1–6; the fallback preserves an existing
integer without changing its value. `gradeLevelEstimateSource` is one of:
  "existing_grade_level" — copied from words.grade_level 1–4
  "childlex_age1"     — derived from childLex Age 1 frequency
  "childlex_age2"     — derived from childLex Age 2 frequency
  "childlex_age3"     — derived from childLex Age 3 frequency
  "dwds_fallback"     — derived from DWDS frequenzklasse (no childLex)
  "original"          — kept an integer grade or defaulted to 5 (no signals)

`gradeLevelEstimateEvidence` distinguishes inherited values, heuristic
frequency mappings, and the generic default. It records explicit upstream
evidence for inherited grades without guessing provenance from membership.
"""

from __future__ import annotations

from copy import deepcopy
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


def _inherited_evidence(metadata: dict, reason: str) -> dict:
    evidence = {
        "status": "inherited",
        "sourceField": "words.grade_level",
        "reason": reason,
    }
    # These explicit upstream fields are independent of prior estimate labels.
    # In particular, gradeLevelEstimateSource='nrw' does not prove NRW origin.
    for upstream, target in (("gradeLevelSource", "upstreamSource"),
                             ("gradeLevelEvidence", "upstreamEvidence")):
        if upstream in metadata:
            evidence[target] = deepcopy(metadata[upstream])
    return evidence


def decide_grade_estimate(grade, frequency: dict | None = None,
                          metadata: dict | None = None) -> dict:
    """Return estimate metadata without modifying the supplied source records.

    Numeric precedence and thresholds match the original implementation.
    Provenance describes the selected field or heuristic, not inferred origin.
    """
    frequency = frequency if isinstance(frequency, dict) else {}
    metadata = metadata if isinstance(metadata, dict) else {}

    if isinstance(grade, int) and 1 <= grade <= 4:
        estimate = grade
        source = "existing_grade_level"
        evidence = _inherited_evidence(metadata, "existing_grade_1_to_4")
    else:
        estimate, source = estimate_from_childlex(frequency.get("childlex"))
        if estimate is not None:
            age = source.removeprefix("childlex_")
            field = f"{age}_freq_norm"
            evidence = {
                "status": "heuristic",
                "sourceField": f"frequency_json.childlex.{field}",
                "value": frequency["childlex"][field],
                "method": "earliest_age_band_meeting_presence_threshold",
                "presenceThreshold": PRESENCE_THRESHOLD,
                "withinBandThreshold": {"age1": AGE1_HIGH, "age2": AGE2_HIGH,
                                        "age3": AGE3_HIGH}[age],
                "frequencyUnit": "occurrences_per_million",
            }
        else:
            estimate, source = estimate_from_dwds(frequency.get("dwds"))
            if estimate is not None:
                evidence = {
                    "status": "heuristic",
                    "sourceField": "frequency_json.dwds.frequenzklasse",
                    "value": frequency["dwds"]["frequenzklasse"],
                    "method": "existing_dwds_frequency_class_thresholds",
                    "rules": {"atLeast5": 2, "classes3Or4": 4, "otherInteger": 6},
                }
            else:
                estimate = grade if isinstance(grade, int) else 5
                source = "original"
                evidence = (_inherited_evidence(metadata, "no_usable_frequency_signal")
                            if isinstance(grade, int) else {
                                "status": "default",
                                "reason": "no_integer_grade_or_usable_frequency_signal",
                                "defaultValue": 5,
                            })
    return {
        "gradeLevelEstimate": estimate,
        "gradeLevelEstimateSource": source,
        "gradeLevelEstimateEvidence": evidence,
    }


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

        decision = decide_grade_estimate(r["grade_level"], freq, meta)
        estimate = decision["gradeLevelEstimate"]
        source = decision["gradeLevelEstimateSource"]
        if source == "original":
            grade_level_unchanged += 1
        meta.update(decision)

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
