"""Attach English pronunciation data from CMUdict to grundwortschatz_en.json.

CMUdict is already fetched by 00_fetch_sources.py. This step is deliberately
local and deterministic: no espeak/phonemizer dependency is needed for EN.

The script overwrites grundwortschatz_en.json in place and is idempotent.
"""
import json
import re
from pathlib import Path

HERE = Path(__file__).parent
JSON_PATH = HERE / "grundwortschatz_en.json"
CMUDICT_PATH = HERE / "sources" / "cmudict.txt"

ARPABET_TO_IPA = {
    "AA": "ɑ",
    "AE": "æ",
    "AH": "ʌ",
    "AO": "ɔ",
    "AW": "aʊ",
    "AY": "aɪ",
    "B": "b",
    "CH": "tʃ",
    "D": "d",
    "DH": "ð",
    "EH": "ɛ",
    "ER": "ɜr",
    "EY": "eɪ",
    "F": "f",
    "G": "ɡ",
    "HH": "h",
    "IH": "ɪ",
    "IY": "i",
    "JH": "dʒ",
    "K": "k",
    "L": "l",
    "M": "m",
    "N": "n",
    "NG": "ŋ",
    "OW": "oʊ",
    "OY": "ɔɪ",
    "P": "p",
    "R": "r",
    "S": "s",
    "SH": "ʃ",
    "T": "t",
    "TH": "θ",
    "UH": "ʊ",
    "UW": "u",
    "V": "v",
    "W": "w",
    "Y": "j",
    "Z": "z",
    "ZH": "ʒ",
}

IPA_TO_XSAMPA = {
    "ɑ": "A",
    "æ": "{",
    "ʌ": "V",
    "ɔ": "O",
    "aʊ": "aU",
    "aɪ": "aI",
    "tʃ": "tS",
    "ð": "D",
    "ɛ": "E",
    "ɜ": "3",
    "eɪ": "eI",
    "ɡ": "g",
    "ɪ": "I",
    "i": "i",
    "dʒ": "dZ",
    "ŋ": "N",
    "oʊ": "oU",
    "ɔɪ": "OI",
    "ʃ": "S",
    "θ": "T",
    "ʊ": "U",
    "u": "u",
    "ʒ": "Z",
}


def normalize_headword(raw):
    return re.sub(r"\(\d+\)$", "", raw).lower()


def strip_stress(phone):
    return re.sub(r"\d", "", phone)


def arpabet_to_ipa(phones):
    parts = []
    for phone in phones:
        base = strip_stress(phone)
        ipa = ARPABET_TO_IPA.get(base)
        if ipa:
            if phone.endswith("1"):
                ipa = "ˈ" + ipa
            elif phone.endswith("2"):
                ipa = "ˌ" + ipa
            parts.append(ipa)
    return "".join(parts)


def ipa_to_xsampa(ipa):
    out = ipa
    for src, dst in sorted(IPA_TO_XSAMPA.items(), key=lambda item: len(item[0]), reverse=True):
        out = out.replace(src, dst)
    out = out.replace("ˈ", '"').replace("ˌ", "%").replace("r", "r")
    return out


def load_cmudict(path):
    pronunciations = {}
    with path.open(encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith(";;;"):
                continue
            parts = line.split()
            if len(parts) < 2:
                continue
            word = normalize_headword(parts[0])
            if not re.match(r"^[a-z][a-z'\-]*$", word):
                continue
            pronunciations.setdefault(word, parts[1:])
    return pronunciations


def main():
    if not JSON_PATH.exists():
        raise SystemExit("Run 03_conv_csv_to_json_en.py first.")
    if not CMUDICT_PATH.exists():
        raise SystemExit("Run 00_fetch_sources.py first.")

    data = json.loads(JSON_PATH.read_text(encoding="utf-8"))
    pronunciations = load_cmudict(CMUDICT_PATH)

    matched = 0
    for entry in data.get("vocabulary", []):
        word = (entry.get("word") or "").lower()
        phones = pronunciations.get(word)
        if not phones:
            entry.setdefault("pronunciation", None)
            entry.setdefault("ipaPhoneme", None)
            entry.setdefault("sampaPhoneme", None)
            continue

        ipa = arpabet_to_ipa(phones)
        sampa = ipa_to_xsampa(ipa)
        entry["pronunciation"] = {
            "source": "cmudict",
            "arpabet": phones,
            "ipa": ipa,
            "xsampa": sampa,
        }
        entry["ipaPhoneme"] = ipa
        entry["sampaPhoneme"] = sampa
        matched += 1

    data.setdefault("metadata", {})["phonemized"] = True
    data["metadata"]["phonemization_source"] = "CMU Pronouncing Dictionary"
    data["metadata"]["phonemized_count"] = matched

    JSON_PATH.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    total = len(data.get("vocabulary", []))
    pct = 100.0 * matched / max(total, 1)
    print(f"Attached CMUdict pronunciation to {matched}/{total} words ({pct:.1f}%).")


if __name__ == "__main__":
    main()
