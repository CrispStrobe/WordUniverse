"""fresch_classifier_v2 — principled German spelling-strategy classifier.

This is the v2 of the spelling-strategy derivation described in
`pipeline/PLAN.md §6`. v1 (`04b_derive_spelling_patterns.py`) covered the
~533 NRW Grundwortschatz words well (from NRW xlsx feature flags) but fell
back to a crude surface-regex heuristic for the other ~9,500 words, which:

  • over-applied `klangtreu` (any multi-letter grapheme → klangtreu)
  • over-applied `verwandt` (any lemma ending in b/d/g → verwandt)
  • under-detected `morphem` (regex prefixes only — no compound/suffix signal)
  • under-detected `merkwort` (no irregular-spelling or error-rate signal)

v2 keeps the SAME six neutral category labels (klangtreu / doppelkonsonant /
verwandt / merkwort / morphem / grossschreibung — see v1 for the licensing
rationale) and the SAME five-category Thomé view, but recomputes the tags
from the *rich enrichment already present in the shipped DB* rather than
from surface regex:

  • `hyphenation`     → morpheme / prefix / suffix structure  (morphem)
  • `inflections`     → umlaut + Auslautverhärtung alternation (verwandt)
  • `pronunciation`   → IPA, confirms final devoicing           (verwandt)
  • surface doubling  → ss/ll/.../ck/tz                          (doppelkonsonant)
  • irregular spelling markers + litkey_error_rate + freq        (merkwort)
  • word_type / article / capitalisation                         (grossschreibung)
  • residual                                                      (klangtreu)

This module is PURE (no I/O, no DB): `classify(features)` takes a small
dataclass and returns a `Classification`. The DB patcher and the validation
harness both call it. See `validate_fresch.py` and the `--patch-db` path.

The §6.3 tuning goals are realised here:
  - `verwandt` fires only on *evidence of alternation* (inflection table or
    IPA-confirmed devoicing), not on a bare final b/d/g  → precision up.
  - `morphem` fires on hyphenation-derived prefix/suffix/compound  → recall up.
  - `merkwort` fires on irregular grapheme markers + high child-error-rate +
    top-frequency function words  → recall up.
  - `klangtreu` is the *residual* class — it is assigned only when no
    sound/letter strategy fired, so it stops over-tagging.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Optional

# ── Category tokens (identical to v1 — do not rename; the DB + app rely on them) ──
KLANGTREU = "klangtreu"
DOPPELKONSONANT = "doppelkonsonant"
VERWANDT = "verwandt"
MERKWORT = "merkwort"
MORPHEM = "morphem"
GROSSSCHREIBUNG = "grossschreibung"

# 5-cat Thomé view
BASISGRAPHEM = "basisgraphem"
ORTHOGRAPHEM = "orthographem"
MORPHEM_BROAD = "morphem"  # same token, broad meaning

# Primary-pick priority (PLAN §6.2): Großschreibung first if it applies, then
# the highest-leverage sound/letter strategy, with klangtreu (regular) last.
PRIMARY_PRIORITY_DETAILED = [
    GROSSSCHREIBUNG, MERKWORT, DOPPELKONSONANT, VERWANDT, MORPHEM, KLANGTREU,
]
PRIMARY_PRIORITY_THOME = [
    GROSSSCHREIBUNG, MERKWORT, ORTHOGRAPHEM, MORPHEM_BROAD, BASISGRAPHEM,
]

DETAILED_TO_THOME = {
    KLANGTREU: BASISGRAPHEM,
    DOPPELKONSONANT: ORTHOGRAPHEM,
    VERWANDT: MORPHEM_BROAD,
    MERKWORT: MERKWORT,
    MORPHEM: MORPHEM_BROAD,
    GROSSSCHREIBUNG: GROSSSCHREIBUNG,
}

# ── Lexical resources ──────────────────────────────────────────────────────
# Doubled-consonant / short-vowel orthographic markers (the "Weiterschwingen
# → double" signal). ck and tz are the functional doublings of k and z.
DOUBLED = ("bb", "dd", "ff", "gg", "ll", "mm", "nn", "pp", "rr", "ss",
           "tt", "ck", "tz")

# High-confidence inseparable derivational prefixes. Longest first so the match
# is greedy. The short/ambiguous prefixes (ge, be, er, an, ab, auf, aus, zu, …)
# are deliberately EXCLUDED here — they produce false positives on roots that
# merely start with those letters (geben≠ge+ben, gehen, gerade, antworten).
# Separable-prefix verbs are caught precisely via inflection-table evidence
# instead (see `_separable_particle_in_forms`).
PREFIXES = sorted([
    "ver", "vor", "ent", "emp", "miss", "zer", "über", "unter", "zwischen",
    "durch", "hinter", "wieder", "gegen", "voran", "vorbei", "zurück",
    "zusammen", "empor", "wider", "anti", "auseinander",
], key=len, reverse=True)

# Separable verb particles — detected when an inflected form_text places the
# particle at the END ("baue ab", "biege ab"), a precise morphem signal.
SEP_PARTICLES = ("ab", "an", "auf", "aus", "ein", "mit", "nach", "vor", "zu",
                 "zurück", "weg", "bei", "los", "her", "hin", "empor", "fort",
                 "zusammen", "voran", "vorbei", "durch", "über", "um")
RE_SEP_PARTICLE = re.compile(
    r"\s(" + "|".join(sorted(SEP_PARTICLES, key=len, reverse=True)) + r")$",
    re.IGNORECASE)

# Derivational suffixes — strong "Wortbausteine / morphem" signal.
SUFFIXES = ("ung", "heit", "keit", "schaft", "nis", "tum", "ling", "chen",
            "lein", "lich", "bar", "sam", "haft", "los", "voll", "ig", "isch")

# Irregular-spelling markers that cannot be sounded out by the regular
# grapheme rules (→ merkwort / "Merken"):
#   - long-vowel digraphs aa/ee/oo (Saal, Meer, Boot)
#   - Dehnungs-h: vowel + h + consonant (Bahn, mehr, ohne, Stuhl)
#   - silbentrennendes/Dehnungs special: ieh (sieht), ih (ihn)
#   - v pronounced [f] (Vogel, Vater), but NOT in foreign -v- words → handled via IPA
#   - th / rh / ph / y / chs→[ks] (Theater, Rhythmus, Physik, Typ, Fuchs)
RE_VOWEL_DIGRAPH = re.compile(r"(aa|ee|oo)", re.IGNORECASE)
RE_DEHNUNGS_H = re.compile(r"[aeiouäöü]h(?:[bcdfgjklmnpqrstvwxzß]|\b)", re.IGNORECASE)
RE_IEH_IH = re.compile(r"(ieh|ih)", re.IGNORECASE)
RE_TH_PH_RH_Y = re.compile(r"(th|ph|rh|chs)|y", re.IGNORECASE)

RE_DOUBLED = re.compile("(" + "|".join(DOUBLED) + ")", re.IGNORECASE)
RE_UMLAUT = re.compile(r"[äöüÄÖÜ]")

# IPA voiceless obstruents that signal final devoicing of a voiced grapheme.
DEVOICE_MAP = {"b": "p", "d": "t", "g": "k"}


@dataclass
class WordFeatures:
    """All the inputs the classifier needs — extracted from the DB row."""
    word: str
    lemma: str = ""
    word_type: Optional[str] = None       # 'substantiv' / 'verb' / ...
    article: Optional[str] = None          # 'der' / 'die' / 'das' / None
    hyphenation: list[str] = field(default_factory=list)   # ["Ab-bau"]
    inflected_forms: list[str] = field(default_factory=list)  # form_text strings
    ipa: Optional[str] = None              # "[ˈapˌbaʊ̯]" (brackets ok)
    litkey_error_rate: Optional[float] = None
    grade_level: Optional[int] = None
    is_function_word: bool = False         # very high frequency closed-class


@dataclass
class Classification:
    detailed: list[str]
    detailed_primary: str
    thome: list[str]
    thome_primary: str


# ── helpers ─────────────────────────────────────────────────────────────────

def _strip_ipa(ipa: Optional[str]) -> str:
    if not ipa:
        return ""
    return ipa.strip().strip("[]/").strip()


def _deumlaut(s: str) -> str:
    return (s.replace("ä", "a").replace("ö", "o").replace("ü", "u")
             .replace("Ä", "A").replace("Ö", "O").replace("Ü", "U")
             .replace("äu", "au"))


def _has_prefix(lemma: str) -> bool:
    low = lemma.lower()
    for p in PREFIXES:
        if low.startswith(p) and len(low) > len(p) + 2:
            return True
    return False


def _has_suffix(lemma: str) -> bool:
    low = lemma.lower()
    return any(low.endswith(s) and len(low) > len(s) + 2 for s in SUFFIXES)


def _separable_particle_in_forms(forms: list[str]) -> bool:
    """True if any inflected form places a separable particle at the end
    ("baue ab") — precise evidence of a separable-prefix (morphem) verb."""
    return any(RE_SEP_PARTICLE.search(f or "") for f in forms)


def _morpheme_parts(hyph: list[str]) -> int:
    """Count hyphenation parts of the first variant (rough syllable count)."""
    if not hyph:
        return 0
    return len([p for p in str(hyph[0]).split("-") if p])


def _detect_umlaut_alternation(lemma: str, forms: list[str]) -> bool:
    """True if an inflected form introduces an umlaut the lemma lacks, where
    de-umlauting the form maps it back onto the lemma stem (so we know it is a
    morphological relative, not a different lexeme). E.g. Ball→Bälle,
    Boot→Böte, fahren→fährt, Arzt→Ärzte."""
    low = lemma.lower()
    # If the lemma is ALREADY umlauted (böse, grün, Tür, fünf), the umlaut is
    # not an alternation a child derives from a related form — skip. This was
    # the v2.0 over-firing bug (böse, schön → spurious verwandt).
    if RE_UMLAUT.search(low):
        return False
    base = _deumlaut(low)
    for f in forms:
        fl = f.lower()
        # strip leading articles the form_text often carries
        fl = re.sub(r"^(der|die|das|den|dem|des)\s+", "", fl).strip()
        if not RE_UMLAUT.search(fl):
            continue
        fd = _deumlaut(fl)
        # the de-umlauted form must share a real stem with the lemma, so we
        # know it is a morphological relative (Ball→Bälle), not a homograph.
        stem = base[:max(3, len(base) - 3)]
        if stem and fd.startswith(stem):
            return True
    return False


def _detect_final_devoicing(lemma: str, ipa: str) -> bool:
    """Auslautverhärtung confirmed: lemma ends in b/d/g and the IPA ends in the
    voiceless counterpart p/t/k (e.g. ab→[ap], Berg→[bɛʁk]). Also -ig→[ɪç]."""
    low = lemma.lower().rstrip()
    if not low:
        return False
    bare = _strip_ipa(ipa)
    if not bare:
        # No IPA → conservative: only fire on -ig (very regular devoicing) to
        # keep precision; bare final b/d/g without IPA is too noisy.
        return low.endswith("ig") and len(low) > 3
    # remove trailing IPA diacritics / length marks to find the last consonant
    bare = bare.rstrip("ːˑ̯̩̆")
    last = bare[-1] if bare else ""
    if low.endswith("ig") and last == "ç":
        return True
    if low and low[-1] in DEVOICE_MAP and last == DEVOICE_MAP[low[-1]]:
        return True
    return False


def _detect_irregular_spelling(lemma: str, ipa: str) -> bool:
    """Markers a child cannot derive by the regular grapheme rules."""
    if RE_VOWEL_DIGRAPH.search(lemma):
        return True
    if RE_DEHNUNGS_H.search(lemma):
        return True
    if RE_IEH_IH.search(lemma):
        return True
    if RE_TH_PH_RH_Y.search(lemma):
        return True
    # v pronounced [f] in a native word (Vogel, Vater, viel, von) — confirm via IPA
    bare = _strip_ipa(ipa)
    if "v" in lemma.lower() and "f" in bare and "v" not in bare:
        return True
    return False


# ── core classifier ──────────────────────────────────────────────────────────

def classify(f: WordFeatures) -> Classification:
    lemma = (f.lemma or f.word or "").strip()
    cats: set[str] = set()

    # 1. grossschreibung — capitalisation rule (cross-cutting)
    is_noun = bool(f.word_type and "substantiv" in f.word_type.lower())
    if is_noun or f.article in ("der", "die", "das"):
        cats.add(GROSSSCHREIBUNG)

    # 2. doppelkonsonant — explicit doubled-consonant / ck / tz marker
    if RE_DOUBLED.search(lemma):
        cats.add(DOPPELKONSONANT)

    # 3. verwandt — ONLY on real morphological alternation (§6.3 precision fix)
    if _detect_umlaut_alternation(lemma, f.inflected_forms) or \
       _detect_final_devoicing(lemma, f.ipa or ""):
        cats.add(VERWANDT)

    # 4. morphem — prefix / suffix / separable-verb evidence (§6.3 recall fix,
    #    with precision guard: only high-confidence inseparable prefixes, plus
    #    separable particles read off the inflection table).
    if (_has_prefix(lemma) or _has_suffix(lemma)
            or _separable_particle_in_forms(f.inflected_forms)):
        cats.add(MORPHEM)

    # 5. merkwort — irregular spelling / empirically hard (§6.3 recall fix).
    #    NOTE: we deliberately do NOT key merkwort off "is a function word" —
    #    many short function words (als, auf, bei) are regular sound-it-out
    #    (Mitsprechen) in the gold, so that heuristic over-tagged badly.
    irregular = _detect_irregular_spelling(lemma, f.ipa or "")
    very_hard = (f.litkey_error_rate is not None and f.litkey_error_rate >= 0.6)
    if irregular:
        cats.add(MERKWORT)
    elif very_hard and not (cats - {GROSSSCHREIBUNG}):
        # high child-error words with no other letter/sound strategy → memorize
        cats.add(MERKWORT)

    # 6. klangtreu — RESIDUAL only (§6.3 over-tagging fix). Assigned when no
    #    sound/letter strategy fired (grossschreibung is orthogonal).
    if not (cats - {GROSSSCHREIBUNG}):
        cats.add(KLANGTREU)

    detailed = cats
    thome = {DETAILED_TO_THOME[c] for c in detailed if c in DETAILED_TO_THOME}

    return Classification(
        detailed=sorted(detailed),
        detailed_primary=_pick(detailed, PRIMARY_PRIORITY_DETAILED, KLANGTREU),
        thome=sorted(thome),
        thome_primary=_pick(thome, PRIMARY_PRIORITY_THOME, BASISGRAPHEM),
    )


def _pick(cats: set[str], priority: list[str], default: str) -> str:
    for c in priority:
        if c in cats:
            return c
    return default
