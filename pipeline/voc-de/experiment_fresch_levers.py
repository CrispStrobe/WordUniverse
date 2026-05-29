"""Empirically test candidate FRESCH-classifier refinements (PLAN §6).

Each "lever" is a small, *principled* rule change. We re-classify the 389 gold
words with the lever applied and report the net change in clean% / primary% /
per-category P,R vs the shipped v2 baseline. A lever ships only if it is a
clear net win driven by a linguistic signal (not by memorising gold words).

Levers tested:
  L1  verwandt requires INFLECTION EVIDENCE — a final voiced consonant (b/d/g)
      that reappears before a vowel/schwa in an inflected form (Hund→Hunde).
      Suppresses verwandt on function words with no derivable related form
      (und, ob, sind, bald) → predicted to cut verwandt FPs.
  L2  merkwort detects IPA-confirmed irregular consonant graphemes:
      'ch'→[k] (Chor), word-initial 'c'→[ts]/[s] (Cent). Adds principled
      merkwort recall.
  L3  morphem re-includes be/ge/er/zer/emp prefixes GATED on word_type=verb,
      to recover prefix-verb Wortbausteine (belohnen, gewinnen, erschrecken).
"""
from __future__ import annotations

import json
import re
import sqlite3
from collections import Counter
from pathlib import Path

import fresch_classifier_v2 as fc
from fresch_classifier_v2 import (
    classify, WordFeatures, Classification, KLANGTREU, DOPPELKONSONANT,
    VERWANDT, MERKWORT, MORPHEM, GROSSSCHREIBUNG, DETAILED_TO_THOME,
    PRIMARY_PRIORITY_DETAILED, PRIMARY_PRIORITY_THOME, BASISGRAPHEM, _pick,
)
from fresch_db_features import features_from_row
from validate_fresch import load_gold, FRESCH_TO_ACCEPT, score, primary_match

HERE = Path(__file__).parent
VOW = set("aeiouäöü")


# ── candidate predicates ──────────────────────────────────────────────────
def verwandt_with_inflection_evidence(f: WordFeatures) -> bool:
    """L1: IPA-confirmed devoicing AND an inflected form reveals the voiced
    consonant before a vowel/schwa (Hund→Hunde, Berg→Berge)."""
    if not fc._detect_final_devoicing(f.lemma, f.ipa or ""):
        return False
    low = f.lemma.lower().rstrip()
    if low.endswith("ig"):
        return True  # -ig→[ɪç] is regular, keep as before
    end = low[-1] if low else ""
    if end not in ("b", "d", "g"):
        return False
    # look for the voiced consonant followed by a vowel in some inflected form
    stem = low[:-1]
    for form in f.inflected_forms:
        fl = form.lower()
        # strip leading article
        fl = re.sub(r"^(der|die|das|des|dem|den)\s+", "", fl)
        m = re.search(re.escape(stem) + end + r"[aeiouäöüe]", fl)
        if m:
            return True
    return False


RE_CH_K = re.compile(r"ch", re.IGNORECASE)


def irregular_with_ch_c(lemma: str, ipa: str) -> bool:
    """L2: ch→[k] (Chor, Chaos) or initial c→[ts]/[s] (Cent), IPA-confirmed."""
    bare = fc._strip_ipa(ipa)
    low = lemma.lower()
    if low.startswith("ch") and bare[:1] in ("k", "ç") and "k" in bare[:2]:
        return True
    # ch anywhere mapping to [k] (not the regular [x]/[ç]) — only initial is safe
    if low.startswith("c") and not low.startswith("ch") and bare[:2] in ("t͡", "ts", "s", "t"):
        return True
    return False


PREFIXES_VERB = ("be", "ge", "er", "zer", "emp", "ent", "ver")


def has_verb_prefix(f: WordFeatures) -> bool:
    """L3: be/ge/er/... prefix on a verb (word_type=verb)."""
    if not (f.word_type and "verb" in f.word_type):
        return False
    low = f.lemma.lower()
    for p in PREFIXES_VERB:
        if low.startswith(p) and len(low) > len(p) + 2:
            return True
    return False


# ── parametrised classifier ────────────────────────────────────────────────
def classify_variant(f: WordFeatures, *, L1=False, L2=False, L3=False) -> Classification:
    lemma = (f.lemma or f.word or "").strip()
    cats: set[str] = set()

    is_noun = bool(f.word_type and "substantiv" in f.word_type.lower())
    if is_noun or f.article in ("der", "die", "das"):
        cats.add(GROSSSCHREIBUNG)

    if fc._closed_syllable_doubling(lemma):
        cats.add(DOPPELKONSONANT)

    if L1:
        if verwandt_with_inflection_evidence(f):
            cats.add(VERWANDT)
    else:
        if fc._detect_final_devoicing(lemma, f.ipa or ""):
            cats.add(VERWANDT)

    morphem_fire = (fc._has_prefix(lemma) or fc._has_suffix(lemma)
                    or fc._separable_particle_in_forms(f.inflected_forms))
    if L3 and has_verb_prefix(f):
        morphem_fire = True
    if morphem_fire:
        cats.add(MORPHEM)

    irregular = fc._detect_irregular_spelling(lemma, f.ipa or "")
    if L2 and irregular_with_ch_c(lemma, f.ipa or ""):
        irregular = True
    if irregular:
        cats.add(MERKWORT)

    if not (cats - {GROSSSCHREIBUNG}):
        cats.add(KLANGTREU)

    thome = {DETAILED_TO_THOME[c] for c in cats if c in DETAILED_TO_THOME}
    return Classification(
        detailed=sorted(cats),
        detailed_primary=_pick(cats, PRIMARY_PRIORITY_DETAILED, KLANGTREU),
        thome=sorted(thome),
        thome_primary=_pick(thome, PRIMARY_PRIORITY_THOME, BASISGRAPHEM),
    )


def run(db, levers: dict) -> dict:
    gold = load_gold()
    con = sqlite3.connect(db); cur = con.cursor()
    clean = primary = n = 0
    cat_tp = Counter(); cat_fp = Counter(); cat_fn = Counter()
    for word, toks in gold:
        cur.execute("SELECT word, word_type, article, enrichment_json, metadata_json "
                    "FROM words WHERE word=? COLLATE NOCASE LIMIT 1", (word,))
        row = cur.fetchone()
        if not row:
            continue
        feats = features_from_row(*row)
        c = classify_variant(feats, **levers)
        pred = set(c.detailed)
        n += 1
        s = score(pred, toks)
        clean += s["clean"]
        primary += primary_match(c.detailed_primary, toks)
        accept = set().union(*(FRESCH_TO_ACCEPT[t] for t in toks))
        for cc in pred:
            (cat_tp if cc in accept else cat_fp)[cc] += 1
        for req in (FRESCH_TO_ACCEPT[t] for t in toks):
            if not (req & pred):
                for cc in req:
                    cat_fn[cc] += 1
    con.close()
    return {"n": n, "clean": clean, "primary": primary,
            "tp": cat_tp, "fp": cat_fp, "fn": cat_fn}


def show(name, r, base=None):
    n = r["n"]
    cl = 100 * r["clean"] / n
    pr = 100 * r["primary"] / n
    d = ""
    if base:
        d = f"   (Δclean {cl - 100*base['clean']/n:+.1f}  Δprimary {pr - 100*base['primary']/n:+.1f})"
    print(f"\n=== {name} ===  clean {r['clean']}/{n} ({cl:.1f}%)  primary {r['primary']}/{n} ({pr:.1f}%){d}")
    for c in (KLANGTREU, DOPPELKONSONANT, VERWANDT, MERKWORT, MORPHEM, GROSSSCHREIBUNG):
        tp, fp, fn = r["tp"][c], r["fp"][c], r["fn"][c]
        p = tp/(tp+fp) if tp+fp else float("nan")
        rec = tp/(tp+fn) if tp+fn else float("nan")
        print(f"    {c:16s} P={p*100:5.1f}% R={rec*100:5.1f}%  (tp={tp} fp={fp} fn={fn})")


if __name__ == "__main__":
    db = str(HERE / "grundwortschatz.db")
    base = run(db, {})
    show("BASELINE v2", base)
    for name, lv in [
        ("L1 verwandt+inflection-evidence", {"L1": True}),
        ("L2 merkwort+ch/c", {"L2": True}),
        ("L3 morphem+verb-prefix", {"L3": True}),
        ("L1+L2+L3 combined", {"L1": True, "L2": True, "L3": True}),
    ]:
        show(name, run(db, lv), base)
