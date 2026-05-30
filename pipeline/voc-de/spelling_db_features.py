"""Extract a `WordFeatures` from a DB row — shared by the validator, the tests
and the DB patcher so all three see identical inputs."""
from __future__ import annotations

import json
from typing import Optional

from spelling_strategy_classifier import WordFeatures


def load_stems(con, min_len: int = 4) -> set:
    """Build the compound-splitting stem lexicon: lowercased non-Vorname
    headwords of length ≥ min_len. Pass the result to `classify(f, stems=...)`
    to enable noun-compound detection."""
    stems = set()
    for word, wt in con.execute("SELECT word, word_type FROM words"):
        if wt and str(wt).strip() and word and len(word) >= min_len:
            stems.add(word.lower())
    return stems


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
                      metadata_json: Optional[str] = None) -> WordFeatures:
    enrich = json.loads(enrichment_json) if enrichment_json else {}
    if not isinstance(enrich, dict):
        enrich = {}
    lemma = enrich.get("primary_lemma") or word
    hyph = enrich.get("hyphenation") or []
    if isinstance(hyph, str):
        hyph = [hyph]
    return WordFeatures(
        word=word,
        lemma=lemma if isinstance(lemma, str) else word,
        word_type=(word_type or "").lower() or None,
        article=article,
        hyphenation=[str(h) for h in hyph][:4],
        inflected_forms=_inflected_forms(enrich),
        ipa=_first_ipa(enrich),
    )
