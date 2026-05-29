"""Regression tests for the science-grounded spelling-strategy classifier.

Run:  cd pipeline/voc-de && python3 -m pytest test_spelling_strategy.py -q
 (or: python3 test_spelling_strategy.py  — bare runner, no pytest needed)

Layer 1: anchor-word unit assertions, each pinning one rule from
SPELLING_STRATEGY_SPEC.md. Layer 2: exact agreement against the literature-
sourced gold (spelling_strategy_gold.csv), which is internally consistent and
principle-tagged, so we demand 100% exact (the classifier operationalizes the
same rules that tagged the gold).
"""
from __future__ import annotations

import csv
import sqlite3
from pathlib import Path

from spelling_strategy_classifier import (
    WordFeatures, classify, KLANGTREU, DOPPELKONSONANT, DEHNUNG, VERWANDT,
    MORPHEM, MERKWORT, GROSSSCHREIBUNG,
)
from spelling_db_features import features_from_row

HERE = Path(__file__).parent
DB = HERE / "grundwortschatz.db"
GOLD = HERE / "spelling_strategy_gold.csv"


def WF(word, **kw):
    return WordFeatures(word=word, lemma=kw.pop("lemma", word), **kw)


# ── 1. anchor-word unit assertions ──────────────────────────────────────────

def test_intervocalic_doubling_is_doppelkonsonant_not_klangtreu():
    # KEY reversal: Tasse/Wasser/alle are Schärfung (Orthographem), not klangtreu
    for w in ("Tasse", "Wasser", "alle"):
        c = classify(WF(w))
        assert DOPPELKONSONANT in c.detailed, w
        assert KLANGTREU not in c.detailed, w


def test_monosyllabic_doubling_same_category_as_intervocalic():
    # Thomé framework: Mann == Tasse (both doppelkonsonant), not verwandt
    c = classify(WF("Mann", word_type="substantiv", article="der"))
    assert c.detailed_primary == DOPPELKONSONANT


def test_dehnung_dehnungs_h():
    c = classify(WF("Stuhl", word_type="substantiv", article="der", ipa="[ʃtuːl]"))
    assert DEHNUNG in c.detailed


def test_dehnung_silbentrennendes_h_when_silent():
    c = classify(WF("gehen", word_type="verb", ipa="[ˈɡeːən]"))
    assert c.detailed == [DEHNUNG]


def test_silbentrennendes_h_NOT_on_pronounced_suffix_h():
    # Freiheit: the -heit h is a pronounced onset [h], not a length marker
    c = classify(WF("Freiheit", word_type="substantiv", article="die",
                    ipa="[ˈfʁaɪ̯haɪ̯t]"))
    assert DEHNUNG not in c.detailed
    assert MORPHEM in c.detailed


def test_verwandt_on_auslautverhaertung():
    c = classify(WF("Tag", word_type="substantiv", article="der", ipa="[taːk]",
                    inflected_forms=["der Tag", "die Tage"]))
    assert VERWANDT in c.detailed


def test_verwandt_on_ig():
    c = classify(WF("lustig", word_type="adjektiv", ipa="[ˈlʊstɪç]"))
    assert VERWANDT in c.detailed


def test_merkwort_v_to_f():
    c = classify(WF("Vater", word_type="substantiv", article="der", ipa="[ˈfaːtɐ]"))
    assert MERKWORT in c.detailed


def test_merkwort_NOT_on_ver_prefix():
    # verkaufen's ver- v→[f] is systematic, not a lexical merkwort
    c = classify(WF("verkaufen", word_type="verb", ipa="[fɛɐ̯ˈkaʊ̯fn̩]"))
    assert MERKWORT not in c.detailed
    assert MORPHEM in c.detailed


def test_merkwort_ch_to_k():
    c = classify(WF("Chor", word_type="substantiv", article="der", ipa="[koːɐ̯]"))
    assert MERKWORT in c.detailed


def test_klangtreu_is_residual():
    c = classify(WF("malen", word_type="verb", ipa="[ˈmaːlən]"))
    assert c.detailed == [KLANGTREU]


def test_grossschreibung_primary_only_when_otherwise_regular():
    # Nase: noun, otherwise regular → gross is primary
    c1 = classify(WF("Nase", word_type="substantiv", article="die", ipa="[ˈnaːzə]"))
    assert c1.detailed_primary == GROSSSCHREIBUNG
    # Mann: noun WITH a doubling → doubling leads, gross secondary
    c2 = classify(WF("Mann", word_type="substantiv", article="der", ipa="[man]"))
    assert c2.detailed_primary == DOPPELKONSONANT
    assert GROSSSCHREIBUNG in c2.detailed


def test_apfel_base_not_verwandt():
    # base word whose plural umlauts (Apfel→Äpfel) is NOT verwandt — the base
    # is easy to spell; only Auslautverhärtung/own-umlaut triggers verwandt
    c = classify(WF("Apfel", word_type="substantiv", article="der", ipa="[ˈap͡fl̩]"))
    assert VERWANDT not in c.detailed


def test_every_word_gets_an_explanation():
    for w in ("malen", "Tasse", "Stuhl", "Tag", "verkaufen", "Vater", "Nase"):
        c = classify(WF(w, word_type="substantiv"))
        assert c.explanation and len(c.explanation) > 10, w


# ── 2. exact agreement against the literature gold ───────────────────────────

def test_gold_exact_agreement():
    con = sqlite3.connect(DB)
    cur = con.cursor()
    n = prim_ok = set_ok = 0
    with GOLD.open(encoding="utf-8") as f:
        for r in csv.DictReader(f):
            word = r["word"].strip()
            cur.execute("SELECT word, word_type, article, enrichment_json, "
                        "metadata_json FROM words WHERE word=? COLLATE NOCASE LIMIT 1",
                        (word,))
            row = cur.fetchone()
            if not row:
                continue
            n += 1
            c = classify(features_from_row(*row))
            prim_ok += c.detailed_primary == r["primary"].strip()
            set_ok += set(c.detailed) == set(r["all"].split())
    con.close()
    assert n >= 50, f"expected ~54 gold words in DB, got {n}"
    assert prim_ok == n, f"primary agreement {prim_ok}/{n} (expected all)"
    assert set_ok == n, f"set agreement {set_ok}/{n} (expected all)"


if __name__ == "__main__":
    import traceback
    fns = [v for k, v in sorted(globals().items())
           if k.startswith("test_") and callable(v)]
    passed = failed = 0
    for fn in fns:
        try:
            fn(); passed += 1; print(f"  PASS {fn.__name__}")
        except Exception:
            failed += 1; print(f"  FAIL {fn.__name__}"); traceback.print_exc()
    print(f"\n{passed} passed, {failed} failed")
    raise SystemExit(1 if failed else 0)
