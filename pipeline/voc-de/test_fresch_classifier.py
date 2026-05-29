"""Regression tests for the v2 spelling-strategy classifier (PLAN §6.6).

Run:  cd pipeline/voc-de && python3 -m pytest test_fresch_classifier.py -q
 (or: python3 test_fresch_classifier.py  — falls back to a bare runner)

Two layers:
  1. Unit assertions on anchor words — each exercises one §6.3 rule, so a
     regression in (say) the Auslautverhärtung detector trips a named test.
  2. An aggregate gold-agreement guard against 532Strategien.csv.

On the aggregate targets: PLAN §6.6 originally aimed for ">=50% exact,
>=80% subset". Building the harness revealed that FRESCH and our 6-category
scheme partition the space differently (FRESCH "Weiterschwingen" = our
doppelkonsonant OR verwandt; it is also internally inconsistent — alle/essen
are "Mitsprechen" despite doubled consonants). The >=50% exact target is met
and guarded here; the >=80% subset target is NOT pursued because reaching it
would require suppressing linguistically-correct tags to match an
inconsistent fixture. We guard the achieved, defensible thresholds instead.
"""
from __future__ import annotations

import sqlite3
from pathlib import Path

from fresch_classifier_v2 import (
    WordFeatures, classify, KLANGTREU, DOPPELKONSONANT, VERWANDT, MERKWORT,
    MORPHEM, GROSSSCHREIBUNG,
)
from fresch_db_features import features_from_row
from validate_fresch import load_gold, score, primary_match

HERE = Path(__file__).parent
DB = HERE / "grundwortschatz.db"


# ── 1. anchor-word unit assertions ──────────────────────────────────────────

def test_grossschreibung_for_nouns():
    c = classify(WordFeatures(word="Haus", word_type="substantiv", article="das"))
    assert GROSSSCHREIBUNG in c.detailed


def test_doppelkonsonant_on_closed_syllable():
    # Bett → [bɛt]: doubling is word-final/closed, not audible → Weiterschwingen
    c = classify(WordFeatures(word="Bett", lemma="Bett", word_type="substantiv",
                              article="das"))
    assert DOPPELKONSONANT in c.detailed


def test_doppelkonsonant_NOT_on_intervocalic_doubling():
    # rennen / alle / Wasser: ll/nn/ss followed by a vowel → audible short
    # vowel → Mitsprechen (klangtreu), NOT a Weiterschwingen doubling case
    for w in ("rennen", "alle", "Wasser"):
        c = classify(WordFeatures(word=w, lemma=w))
        assert DOPPELKONSONANT not in c.detailed, w


def test_verwandt_fires_on_final_devoicing():
    # Berg → [bɛʁk]: g spelled, k sound → Auslautverhärtung
    c = classify(WordFeatures(word="Berg", lemma="Berg", word_type="substantiv",
                              article="der", ipa="[bɛʁk]"))
    assert VERWANDT in c.detailed


def test_verwandt_does_NOT_fire_on_umlaut_alone():
    # Ball → Bälle: the umlaut is AUDIBLE (ä ≠ a), so FRESCH treats it as
    # Mitsprechen (klangtreu), not Ableiten/verwandt. Keying verwandt off
    # umlaut was only ~28% precise against the gold.
    c = classify(WordFeatures(word="Ball", lemma="Ball", word_type="substantiv",
                              article="der", inflected_forms=["die Bälle", "des Balls"]))
    assert VERWANDT not in c.detailed


def test_merkwort_NOT_from_error_rate_alone():
    # 'kennen' is a high-child-error but regular (Mitsprechen) word — a high
    # litkey_error_rate must NOT force merkwort.
    c = classify(WordFeatures(word="kennen", lemma="kennen", word_type="verb",
                              litkey_error_rate=0.9))
    assert MERKWORT not in c.detailed


def test_morphem_does_NOT_false_match_ge_root():
    # geben is NOT ge+ben; the short ambiguous prefixes were removed
    c = classify(WordFeatures(word="geben", lemma="geben", word_type="verb"))
    assert MORPHEM not in c.detailed


def test_morphem_fires_on_separable_particle_in_inflections():
    c = classify(WordFeatures(word="abbauen", lemma="abbauen", word_type="verb",
                              inflected_forms=["baue ab", "baust ab", "baute ab"]))
    assert MORPHEM in c.detailed


def test_morphem_fires_on_real_inseparable_prefix():
    c = classify(WordFeatures(word="verstehen", lemma="verstehen", word_type="verb"))
    assert MORPHEM in c.detailed


def test_morphem_fires_on_derivational_suffix():
    c = classify(WordFeatures(word="Freundschaft", lemma="Freundschaft",
                              word_type="substantiv", article="die"))
    assert MORPHEM in c.detailed


def test_merkwort_on_dehnungs_h():
    # silent lengthening h cannot be sounded out → Merkwort
    c = classify(WordFeatures(word="Bahn", lemma="Bahn", word_type="substantiv",
                              article="die", ipa="[baːn]"))
    assert MERKWORT in c.detailed


def test_merkwort_on_ch_pronounced_k():
    # Chor → [koːɐ̯]: 'ch' read as [k] is irregular (German 'ch' is normally
    # [ç]/[x]) → Merkwort. (experiment_fresch_levers.py "L2")
    c = classify(WordFeatures(word="Chor", lemma="Chor", word_type="substantiv",
                              article="der", ipa="[koːɐ̯]"))
    assert MERKWORT in c.detailed


def test_merkwort_on_initial_c_pronounced_ts():
    # Cent → [t͡sɛnt]: word-initial 'c' as [ts] is irregular → Merkwort
    c = classify(WordFeatures(word="Cent", lemma="Cent", word_type="substantiv",
                              article="der", ipa="[t͡sɛnt]"))
    assert MERKWORT in c.detailed


def test_merkwort_NOT_on_regular_ch():
    # 'ich'/'machen': medial/final 'ch' as [ç]/[x] is the regular realisation —
    # must NOT fire the ch→[k] Merkwort rule.
    for w, ipa in (("ich", "[ɪç]"), ("machen", "[ˈmaxn̩]")):
        c = classify(WordFeatures(word=w, lemma=w, ipa=ipa))
        assert MERKWORT not in c.detailed, w


def test_function_word_is_NOT_forced_to_merkwort():
    # 'auf' is Mitsprechen in the gold — must stay klangtreu, not merkwort
    c = classify(WordFeatures(word="auf", lemma="auf", word_type="praeposition",
                              ipa="[aʊ̯f]", is_function_word=True))
    assert MERKWORT not in c.detailed
    assert c.detailed_primary == KLANGTREU


def test_klangtreu_is_residual_only():
    # a plain regular word with no special feature → klangtreu alone
    c = classify(WordFeatures(word="malen", lemma="malen", word_type="verb",
                              ipa="[ˈmaːlən]"))
    assert c.detailed == [KLANGTREU]


# ── 2. aggregate gold-agreement guard ───────────────────────────────────────

def _aggregate():
    gold = load_gold()
    con = sqlite3.connect(DB)
    cur = con.cursor()
    n = clean = primary = 0
    cat_tp = {MERKWORT: 0}; cat_fn = {MERKWORT: 0}
    morph_tp = morph_fp = 0
    for word, toks in gold:
        cur.execute("SELECT word, word_type, article, enrichment_json, "
                    "metadata_json FROM words WHERE word=? COLLATE NOCASE LIMIT 1",
                    (word,))
        row = cur.fetchone()
        if not row:
            continue
        n += 1
        c = classify(features_from_row(*row))
        pred = set(c.detailed)
        s = score(pred, toks)
        clean += s["clean"]
        primary += primary_match(c.detailed_primary, toks)
    con.close()
    return n, clean, primary


def test_aggregate_thresholds():
    n, clean, primary = _aggregate()
    assert n >= 380, f"expected ~389 gold words present in DB, got {n}"
    clean_pct = 100 * clean / n
    primary_pct = 100 * primary / n
    # achieved 64.3% clean / 82.5% primary — guard a small margin below
    assert clean_pct >= 60.0, f"clean agreement regressed: {clean_pct:.1f}%"
    assert primary_pct >= 78.0, f"primary agreement regressed: {primary_pct:.1f}%"


if __name__ == "__main__":
    # bare runner (no pytest dependency)
    import traceback
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    passed = failed = 0
    for fn in fns:
        try:
            fn(); passed += 1; print(f"  PASS {fn.__name__}")
        except Exception:
            failed += 1; print(f"  FAIL {fn.__name__}"); traceback.print_exc()
    print(f"\n{passed} passed, {failed} failed")
    raise SystemExit(1 if failed else 0)
