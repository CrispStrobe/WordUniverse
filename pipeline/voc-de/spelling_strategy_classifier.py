"""spelling_strategy_classifier — science-grounded German spelling-strategy tagger.

Implements the spec in `SPELLING_STRATEGY_SPEC.md`: each word is assigned one or
more of seven categories grounded in the orthographic principles of German
(Eisenberg/Fuhrhop, Maas, Gallmann, Schmidt/Fuhrhop, the amtliches Regelwerk,
and Günther Thomé's Basisgrapheme-vs-Orthographeme inventory). The taxonomy is
deliberately the function-based Thomé reading for consonant doubling: ALL
short-vowel doublings are one category (`doppelkonsonant`), `Tasse` = `Mann`;
the Eisenberg/Maas silbisch-vs-morphological refinement lives in the per-word
*explanation*, not in the category.

Seven categories (neutral linguistic terms — no method-brand jargon anywhere):

  klangtreu        phonographisches Prinzip / Basisgraphem (default, residual)
  doppelkonsonant  Schärfung: short stressed vowel + doubled consonant / ck / tz
  dehnung          long-vowel marking: Dehnungs-h, aa/ee/oo, ie, silbentrennendes-h
  verwandt         morphologisches Prinzip / Stammkonstanz: Auslautverhärtung + Umlaut
  morphem          morphematisches Prinzip: prefix / suffix / compound / particle
  merkwort         genuine exception (sonstige Orthographeme): v→[f], ch→[k], th/ph
  grossschreibung  syntaktisches Prinzip: nouns

Pure module (no I/O): `classify(features)` → `Classification`. The DB patcher,
the validator and the tests all call it.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Optional

# ── category tokens (neutral; the DB + app rely on these strings) ──
KLANGTREU = "klangtreu"
DOPPELKONSONANT = "doppelkonsonant"
DEHNUNG = "dehnung"
VERWANDT = "verwandt"
MORPHEM = "morphem"
MERKWORT = "merkwort"
GROSSSCHREIBUNG = "grossschreibung"

ALL_CATEGORIES = [
    KLANGTREU, DOPPELKONSONANT, DEHNUNG, VERWANDT, MORPHEM, MERKWORT,
    GROSSSCHREIBUNG,
]

# Primary pick (SPEC §primary): most-marked teaching point first; klangtreu is
# the residual. grossschreibung is handled specially in `_pick_primary`
# (primary only when the noun is otherwise regular).
PRIMARY_PRIORITY = [
    MERKWORT, VERWANDT, DOPPELKONSONANT, DEHNUNG, MORPHEM, KLANGTREU,
]

# ── lexical resources ──
DOUBLED = ("bb", "dd", "ff", "gg", "ll", "mm", "nn", "pp", "rr", "ss",
           "tt", "ck", "tz")
RE_DOUBLED = re.compile("(" + "|".join(DOUBLED) + ")", re.IGNORECASE)
VOWELS = set("aeiouäöüyAEIOUÄÖÜY")

# Dehnung / long-vowel markers
RE_DEHNUNGS_H = re.compile(r"[aeiouäöü]h[lmnr]", re.IGNORECASE)      # Stuhl, Bahn, mehr
RE_SILBEN_H = re.compile(r"[aeiouäöü]h[aeiouäöü]", re.IGNORECASE)    # gehen, Ruhe
RE_DOPPELVOKAL = re.compile(r"(aa|ee|oo)", re.IGNORECASE)           # Saal, Meer, Boot
RE_IE = re.compile(r"ie", re.IGNORECASE)                            # Brief, Tier

# morphem
PREFIXES = sorted([
    "ver", "vor", "ent", "emp", "miss", "zer", "über", "unter", "zwischen",
    "durch", "hinter", "wieder", "gegen", "voran", "vorbei", "zurück",
    "zusammen", "empor", "wider", "anti", "auseinander",
], key=len, reverse=True)
SUFFIXES = ("ung", "heit", "keit", "schaft", "nis", "tum", "ling", "chen",
            "lein", "lich", "bar", "sam", "haft", "los", "voll", "ig", "isch")
SEP_PARTICLES = ("ab", "an", "auf", "aus", "ein", "mit", "nach", "vor", "zu",
                 "zurück", "weg", "bei", "los", "her", "hin", "empor", "fort",
                 "zusammen", "voran", "vorbei", "durch", "über", "um")
RE_SEP_PARTICLE = re.compile(
    r"\s(" + "|".join(sorted(SEP_PARTICLES, key=len, reverse=True)) + r")$",
    re.IGNORECASE)

# merkwort (etymological / foreign irregular grapheme→phoneme)
RE_TH_PH_RH = re.compile(r"(th|ph|rh)", re.IGNORECASE)
DEVOICE_MAP = {"b": "p", "d": "t", "g": "k"}

UMLAUT_BACK = {"ä": "a", "ö": "o", "ü": "u"}  # äu↔au handled separately


@dataclass
class WordFeatures:
    word: str
    lemma: str = ""
    word_type: Optional[str] = None
    article: Optional[str] = None
    hyphenation: list = field(default_factory=list)
    inflected_forms: list = field(default_factory=list)
    ipa: Optional[str] = None


@dataclass
class Classification:
    detailed: list
    detailed_primary: str
    explanation: str          # per-word, science-grounded (SPEC §explanation)


# ── feature predicates ──────────────────────────────────────────────────────

def _strip_ipa(ipa: Optional[str]) -> str:
    return ipa.strip().strip("[]/").strip() if ipa else ""


def _strip_article(form: str) -> str:
    return re.sub(r"^(der|die|das|des|dem|den)\s+", "", (form or "").strip(),
                  flags=re.IGNORECASE)


def _is_noun(f: "WordFeatures") -> bool:
    return bool(f.word_type and "substantiv" in f.word_type.lower()) or \
        f.article in ("der", "die", "das")


def _doppelkonsonant(lemma: str) -> bool:
    """Short-vowel consonant doubling (Schärfung) — any position. The doubling
    is the orthographic signal; in German a doubled consonant grapheme marks a
    preceding short stressed vowel by rule, so the doubling itself suffices."""
    return bool(RE_DOUBLED.search(lemma))


def _dehnung(lemma: str, ipa: str) -> bool:
    """Long-vowel marking: Dehnungs-h (+l/m/n/r), silbentrennendes-h (intervocalic),
    Doppelvokal aa/ee/oo, or `ie` confirmed long by IPA [iː]."""
    bare = _strip_ipa(ipa)
    if RE_DEHNUNGS_H.search(lemma) or RE_DOPPELVOKAL.search(lemma):
        return True
    # silbentrennendes-h only counts when the h is SILENT (gehen/Ruhe). A
    # pronounced [h] in the IPA means it is a consonant onset / morpheme boundary
    # (Frei-heit, Wild-heit), not a length/boundary marker.
    if RE_SILBEN_H.search(lemma) and (not bare or "h" not in bare):
        return True
    if RE_IE.search(lemma) and "iː" in bare:
        return True
    return False


def _final_devoicing(lemma: str, ipa: str) -> bool:
    """Auslautverhärtung: lemma ends b/d/g and IPA ends voiceless p/t/k, or
    -ig → [ɪç]/[ç]."""
    low = lemma.lower().rstrip()
    if not low:
        return False
    bare = _strip_ipa(ipa).rstrip("ːˑ̯̩̆")
    last = bare[-1] if bare else ""
    if low.endswith("ig"):
        return (last == "ç") or (not bare and len(low) > 3)
    if not bare:
        return False
    return low[-1] in DEVOICE_MAP and last == DEVOICE_MAP[low[-1]]


def _fold_umlaut(s: str) -> str:
    return (s.replace("äu", "au").replace("ä", "a").replace("ö", "o")
            .replace("ü", "u"))


def _umlaut_alternation(lemma: str, forms: list[str]) -> bool:
    """Stammkonstanz via Umlaut, headword-applicable case only: the HEADWORD
    itself contains an umlaut (ä/äu/ö/ü) whose plain counterpart (a/au/o/u)
    appears in a related form sharing the same stem — i.e. the headword IS the
    umlauted variant and its spelling is recovered from the base (e.g. a
    headword like `Bäcker`←`backen`). We deliberately do NOT fire when the
    headword is the PLAIN base whose plural/diminutive merely umlauts
    (`Ball`→`Bälle`, `Tasse`→`Tässchen`): the base is easy to spell, so that
    would flood `verwandt`. Auslautverhärtung is the other (reliable) trigger.

    Limitation: derivational bases (backen for Bäcker) are usually NOT in the
    inflection table, so most umlaut-derivation headwords fall through to their
    other strategy — acceptable; Umlaut-constancy is pedagogically about the
    derived forms, surfaced in the explanation."""
    low = lemma.lower()
    if not re.search(r"[äöü]", low):       # headword must itself be umlauted
        return False
    folded = _fold_umlaut(low)
    for f in forms:
        s = _strip_article(f).lower()
        if not s or s == low:
            continue
        fs = _fold_umlaut(s)
        n = min(4, len(folded), len(fs))
        # folded stems agree, raw stems differ → the difference is an umlaut,
        # and the related form carries the PLAIN vowel (s has fewer umlauts here)
        if n >= 3 and folded[:n] == fs[:n] and low[:n] != s[:n] \
                and not re.search(r"[äöü]", s[:n]):
            return True
    return False


def _has_prefix(lemma: str) -> bool:
    low = lemma.lower()
    return any(low.startswith(p) and len(low) > len(p) + 2 for p in PREFIXES)


def _has_suffix(lemma: str) -> bool:
    low = lemma.lower()
    return any(low.endswith(s) and len(low) > len(s) + 2 for s in SUFFIXES)


def _separable_particle(forms: list[str]) -> bool:
    return any(RE_SEP_PARTICLE.search(f or "") for f in forms)


# Linking morphemes (Fugenelemente) between compound parts.
FUGEN = ("", "s", "es", "n", "en", "er", "e", "ns")

# Curated unambiguous 3-letter compound HEADS (concrete nouns). The general
# stem set requires ≥4 chars to avoid junk heads (articles der/die/den, stray
# fragments); these short, very common heads are safe to allow explicitly so we
# still catch Haus-tür / Bahn-hof / Frei-tag / Hand-tuch etc.
HEAD3_ALLOW = frozenset({
    "tag", "tür", "hof", "weg", "zug", "rad", "uhr", "bad", "see", "tor",
    "amt", "ohr", "arm", "hut", "bus", "eis", "öl", "kuh",
})


def _split_compound(low: str, stems: set):
    """Split a (lowercased) NOUN lemma into modifier + head where both are known
    stems (DB headwords ≥3 chars), allowing a Fugenelement between them. Returns
    (modifier, head) or None. Caller restricts this to nouns; suffix-derived
    words (romantisch, Freundschaft) are excluded so the suffix rule handles
    them. Heuristic — favours the longest modifier; occasional imperfect part
    splits on inflected heads (Nachnamen→nach+amen) but the morphem CATEGORY is
    correct. Not run when stems is None (keeps classify() pure-by-default)."""
    if not stems or len(low) < 7:
        return None
    if any(low.endswith(s) and len(low) > len(s) + 2 for s in SUFFIXES):
        return None  # derivation, not a compound
    for i in range(len(low) - 3, 3, -1):
        head = low[i:]
        head_ok = (len(head) >= 4 and head in stems) or head in HEAD3_ALLOW
        if not head_ok:
            continue
        mod = low[:i]
        for fz in FUGEN:
            if fz and not mod.endswith(fz):
                continue
            base = mod[:len(mod) - len(fz)] if fz else mod
            if len(base) >= 4 and base in stems:   # modifier ≥4 (no die/and/ins junk)
                return (base, head)
    return None


def _merkwort(lemma: str, ipa: str) -> bool:
    """Genuine etymological/foreign exception, IPA-confirmed where possible."""
    low = lemma.lower()
    bare = _strip_ipa(ipa)
    # v → [f] in a LEXICAL word (Vater, Vogel, viel). Strip a leading ver-/vor-
    # prefix first: its v→[f] is systematic (verkaufen, vorlesen) — not a
    # merkwort. A bare grammatical word (von) keeps its v.
    v_stem = re.sub(r"^(ver|vor)(?=.{2})", "", low)
    if "v" in v_stem and "f" in bare and "v" not in bare:
        return True
    # word-initial ch → [k] (Chor, Charakter, Christ)
    if low.startswith("ch") and bare[:1] in ("k", "ç") and "k" in bare[:2]:
        return True
    # word-initial c → [ts]/[s]/[t͡s] (Cent, Celsius)
    if low.startswith("c") and not low.startswith("ch") and bare[:2] in ("t͡", "ts", "t", "s"):
        return True
    # th / ph / rh (Theater, Physik, Rhythmus)
    if RE_TH_PH_RH.search(lemma):
        return True
    return False


# ── explanation generation (SPEC §explanation; per-word with template fallback) ──

def _find_lengthening(lemma: str, forms: list[str]) -> Optional[str]:
    """A 'Verlängerung' form that reveals a word-final consonant before a vowel:
    Tag→Tage, Berg→Berge, Mann→Männer. Returns the form text or None."""
    low = lemma.lower().rstrip()
    if not low:
        return None
    last = low[-1]
    stem = low[:-1]
    best = None
    for f in forms:
        s = _strip_article(f)
        sl = s.lower()
        if not sl or sl == low:
            continue
        # final consonant now followed by a vowel (Auslautverhärtung reveal)
        if re.search(re.escape(stem) + last + r"[aeiouäöü]", sl):
            if best is None or len(s) < len(best):
                best = s
    return best


def _find_double_reveal(lemma: str, forms: list[str]) -> Optional[str]:
    """For a monosyllabic doubling, a form that shows the doubling between
    syllables: Mann→Männer/Männchen, Ball→Bälle."""
    m = RE_DOUBLED.search(lemma)
    if not m:
        return None
    dbl = m.group(0).lower()
    low = lemma.lower()
    for f in forms:
        s = _strip_article(f)
        sl = s.lower()
        if sl and sl != low and dbl in sl and len(sl) > len(low):
            # share a (umlaut-folded) 2-char stem so we pick a real relative
            if _fold_umlaut(sl)[:2] == _fold_umlaut(low)[:2]:
                return s
    return None


def _explain(cats: set, primary: str, f: "WordFeatures", compound=None) -> str:
    lemma = f.lemma or f.word
    forms = f.inflected_forms
    hy = f.hyphenation[0] if f.hyphenation else lemma

    if primary == DOPPELKONSONANT:
        syl = (f.hyphenation[0].count("-") + 1) if f.hyphenation else 1
        if syl >= 2:
            return (f"Nach einem kurzen Selbstlaut steht der doppelte Mitlaut "
                    f"zwischen den Silben: „{hy}“. Du hörst ihn nur einmal.")
        reveal = _find_double_reveal(lemma, forms)
        if reveal:
            return (f"Nach einem kurzen Selbstlaut schreibst du den Mitlaut "
                    f"doppelt. Verlängere, um es zu hören: „{lemma}“ → „{reveal}“.")
        return ("Nach einem kurzen, betonten Selbstlaut schreibst du den "
                "folgenden Mitlaut doppelt (oder ck/tz). Du hörst ihn nur einmal.")

    if primary == DEHNUNG:
        if RE_SILBEN_H.search(lemma):
            return (f"Das stille „h“ trennt die Silben: „{hy}“ — du schreibst es, "
                    f"hörst es aber nicht.")
        if RE_DEHNUNGS_H.search(lemma):
            return ("Der lang gesprochene Selbstlaut wird mit einem stillen "
                    "Dehnungs-h markiert.")
        if RE_DOPPELVOKAL.search(lemma):
            return ("Der lange Selbstlaut wird durch einen doppelten Selbstlaut "
                    "markiert (aa/ee/oo).")
        return "Der lange [iː]-Laut wird mit „ie“ geschrieben."

    if primary == VERWANDT:
        reveal = _find_lengthening(lemma, forms)
        if lemma.lower().endswith("ig"):
            return ("Am Wortende klingt „-ig“ wie „-ich“. Du erkennst das „g“ "
                    "über die Verlängerung (z. B. „-ige“).")
        if reveal:
            return (f"Am Wortende klingt es hart, aber du schreibst den "
                    f"Stamm-Buchstaben: „{lemma}“ → „{reveal}“.")
        if _umlaut_alternation(lemma, forms):
            return ("Du schreibst „ä/äu“ wegen des verwandten Stammworts mit "
                    "„a/au“.")
        return ("Den richtigen End-Buchstaben findest du, indem du das Wort "
                "verlängerst oder ein verwandtes Wort suchst.")

    if primary == MORPHEM:
        if compound:
            a, b = compound[0].capitalize(), compound[1].capitalize()
            return (f"Das Wort ist zusammengesetzt: „{a} + {b}“. "
                    "Schreibe beide Bausteine, dann stimmt das Wort.")
        return (f"Das Wort besteht aus Bausteinen ({hy}). Kennst du die "
                f"Bausteine, schreibst du es richtig.")

    if primary == MERKWORT:
        bare = _strip_ipa(f.ipa)
        if "v" in lemma.lower() and "f" in bare and "v" not in bare:
            return "Das „v“ wird wie „f“ gesprochen — diese Schreibung musst du dir merken."
        if lemma.lower().startswith("ch"):
            return "Das „ch“ wird hier wie „k“ gesprochen — eine Schreibung zum Merken."
        return ("Dieses Wort folgt keiner einfachen Regel — seine Schreibung "
                "musst du dir merken (oft aus einer anderen Sprache).")

    if primary == GROSSSCHREIBUNG:
        return "Nomen (Namenwörter) schreibt man groß."

    # klangtreu
    return ("Du schreibst das Wort so, wie du es langsam und deutlich sprichst — "
            "jeder Laut bekommt seinen üblichen Buchstaben.")


# ── core classifier ──────────────────────────────────────────────────────────

def classify(f: WordFeatures, stems: set = None) -> Classification:
    """Classify one word. `stems` is an optional set of known DB headwords
    (lowercased); when supplied, noun compounds are detected and tagged
    `morphem` (with a "X + Y" explanation). Omitting it keeps classify() pure
    and dependency-free (unit tests, ad-hoc use)."""
    lemma = (f.lemma or f.word or "").strip()
    ipa = f.ipa or ""
    cats: set[str] = set()
    is_noun = _is_noun(f)

    if is_noun:
        cats.add(GROSSSCHREIBUNG)
    if _doppelkonsonant(lemma):
        cats.add(DOPPELKONSONANT)
    if _dehnung(lemma, ipa):
        cats.add(DEHNUNG)
    # verwandt fires on Auslautverhärtung (reliable, IPA-decidable). Umlaut-
    # Stammkonstanz is real but mostly manifests in INFLECTED forms (not the
    # base headword) and isn't reliably recoverable from noisy DB inflections
    # ("Glück"→spurious "Gluck"), so it is surfaced in the explanation rather
    # than auto-tagged here. See SPELLING_STRATEGY_SPEC.md §verwandt.
    if _final_devoicing(lemma, ipa):
        cats.add(VERWANDT)
    compound = _split_compound(lemma.lower(), stems) if is_noun else None
    if (compound or _has_prefix(lemma) or _has_suffix(lemma)
            or _separable_particle(f.inflected_forms)):
        cats.add(MORPHEM)
    if _merkwort(lemma, ipa):
        cats.add(MERKWORT)

    # klangtreu is the residual (grossschreibung is orthogonal)
    if not (cats - {GROSSSCHREIBUNG}):
        cats.add(KLANGTREU)

    primary = _pick_primary(cats)
    return Classification(
        detailed=sorted(cats),
        detailed_primary=primary,
        explanation=_explain(cats, primary, f, compound),
    )


def _pick_primary(cats: set[str]) -> str:
    """grossschreibung is primary only when the noun is otherwise regular
    (its only non-gross strategy is klangtreu). Otherwise the most-marked
    orthographic strategy leads."""
    non_gross = cats - {GROSSSCHREIBUNG}
    if non_gross == {KLANGTREU} or not non_gross:
        return GROSSSCHREIBUNG if GROSSSCHREIBUNG in cats else KLANGTREU
    for c in PRIMARY_PRIORITY:
        if c in cats:
            return c
    return KLANGTREU
