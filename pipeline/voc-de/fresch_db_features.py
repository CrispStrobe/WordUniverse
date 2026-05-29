"""Extract a `WordFeatures` from a DB row — shared by the validation harness
and the `--patch-db` applier so both see identical inputs."""
from __future__ import annotations

import json
from typing import Optional

from fresch_classifier_v2 import WordFeatures

# word_types that are closed-class function words (informational only; the
# classifier no longer keys merkwort off this — see fresch_classifier_v2).
FUNCTION_WORD_TYPES = {
    "artikel", "pronomen", "praeposition", "präposition", "konjunktion",
}


def _first_ipa(enrich: dict) -> Optional[str]:
    pr = enrich.get("pronunciation") or []
    if isinstance(pr, list):
        for p in pr:
            if isinstance(p, dict) and p.get("ipa"):
                return p["ipa"]
    return None


def _inflected_forms(enrich: dict, limit: int = 24) -> list[str]:
    out: list[str] = []
    infl = enrich.get("inflections") or []
    if isinstance(infl, list):
        for it in infl:
            if isinstance(it, dict):
                t = it.get("form_text")
                if isinstance(t, str) and t.strip():
                    out.append(t.strip())
            elif isinstance(it, str):
                out.append(it)
    return out[:limit]


def features_from_row(word: str, word_type: Optional[str], article: Optional[str],
                      enrichment_json: Optional[str],
                      metadata_json: Optional[str]) -> WordFeatures:
    enrich = json.loads(enrichment_json) if enrichment_json else {}
    meta = json.loads(metadata_json) if metadata_json else {}
    if not isinstance(enrich, dict):
        enrich = {}
    if not isinstance(meta, dict):
        meta = {}

    lemma = enrich.get("primary_lemma") or word
    hyph = enrich.get("hyphenation") or meta.get("hyphenation") or []
    if isinstance(hyph, str):
        hyph = [hyph]

    ler = meta.get("litkey_error_rate")
    try:
        ler = float(ler) if ler is not None else None
    except (TypeError, ValueError):
        ler = None

    grade = meta.get("gradeLevelEstimate")
    try:
        grade = int(grade) if grade is not None else None
    except (TypeError, ValueError):
        grade = None

    wt = (word_type or "").lower() or None
    return WordFeatures(
        word=word,
        lemma=lemma if isinstance(lemma, str) else word,
        word_type=wt,
        article=article,
        hyphenation=[str(h) for h in hyph][:4],
        inflected_forms=_inflected_forms(enrich),
        ipa=_first_ipa(enrich),
        litkey_error_rate=ler,
        grade_level=grade,
        is_function_word=(wt in FUNCTION_WORD_TYPES),
    )
