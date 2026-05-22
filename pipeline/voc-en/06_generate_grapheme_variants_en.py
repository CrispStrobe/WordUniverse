"""Generate conservative English spelling variants for spelling distractors.

This is an EN-native analogue of the DE grapheme variant step. It does not try
to exhaustively map phonemes back to spellings; instead it applies common,
teachable English grapheme confusions to the actual word spelling.

The script overwrites grundwortschatz_en.json in place and is idempotent.
"""
import json
from pathlib import Path

HERE = Path(__file__).parent
JSON_PATH = HERE / "grundwortschatz_en.json"
MAX_VARIANTS_PER_WORD = 12

SUBSTITUTIONS = [
    ("ph", ["f"], "ph_f", 70.0),
    ("f", ["ph"], "f_ph", 18.0),
    ("ck", ["k", "c"], "ck_k_c", 65.0),
    ("k", ["ck", "c"], "k_ck_c", 35.0),
    ("c", ["k", "s"], "c_k_s", 28.0),
    ("ch", ["tch"], "ch_tch", 24.0),
    ("tch", ["ch"], "tch_ch", 60.0),
    ("dge", ["ge", "j"], "dge_ge_j", 54.0),
    ("ge", ["dge", "j"], "ge_dge_j", 22.0),
    ("j", ["g", "dge"], "j_g_dge", 20.0),
    ("kn", ["n"], "silent_k", 80.0),
    ("n", ["kn"], "n_kn", 8.0),
    ("wr", ["r"], "silent_w", 80.0),
    ("r", ["wr"], "r_wr", 7.0),
    ("gn", ["n"], "silent_g", 55.0),
    ("mb", ["m"], "silent_b", 50.0),
    ("igh", ["ie", "i", "y"], "igh_ie_i_y", 42.0),
    ("ie", ["ei", "igh", "y"], "ie_ei_igh_y", 32.0),
    ("ei", ["ie", "ey"], "ei_ie_ey", 30.0),
    ("ee", ["ea", "e"], "ee_ea_e", 45.0),
    ("ea", ["ee", "e"], "ea_ee_e", 40.0),
    ("ai", ["ay", "a_e"], "ai_ay_magic_e", 36.0),
    ("ay", ["ai"], "ay_ai", 34.0),
    ("oa", ["ow", "o_e"], "oa_ow_magic_e", 36.0),
    ("ow", ["oa", "ou"], "ow_oa_ou", 26.0),
    ("ou", ["ow"], "ou_ow", 22.0),
    ("oy", ["oi"], "oy_oi", 42.0),
    ("oi", ["oy"], "oi_oy", 42.0),
    ("er", ["ir", "ur"], "er_ir_ur", 28.0),
    ("ir", ["er", "ur"], "ir_er_ur", 28.0),
    ("ur", ["er", "ir"], "ur_er_ir", 28.0),
    ("le", ["el", "al"], "final_le", 25.0),
    ("tion", ["sion", "shun"], "tion_sion", 24.0),
    ("sion", ["tion"], "sion_tion", 24.0),
    ("cious", ["tious"], "cious_tious", 25.0),
    ("tious", ["cious"], "tious_cious", 25.0),
    ("able", ["ible"], "able_ible", 23.0),
    ("ible", ["able"], "ible_able", 23.0),
]


def replace_at(word, start, old, new):
    if new == "a_e":
        stem = word[:start] + "a" + word[start + len(old):]
        return stem + "e" if not stem.endswith("e") else stem
    if new == "o_e":
        stem = word[:start] + "o" + word[start + len(old):]
        return stem + "e" if not stem.endswith("e") else stem
    return word[:start] + new + word[start + len(old):]


def drop_final_silent_e(word):
    if len(word) > 4 and word.endswith("e"):
        return {
            "spelling": word[:-1],
            "probability": 38.0,
            "rule": "drop_final_silent_e",
        }
    return None


def double_final_consonant(word):
    if len(word) < 4:
        return None
    vowels = set("aeiou")
    if (
        word[-1] not in vowels
        and word[-1] not in "wxy"
        and word[-2] in vowels
        and word[-3] not in vowels
    ):
        return {
            "spelling": word + word[-1],
            "probability": 18.0,
            "rule": "double_final_consonant",
        }
    return None


def generate_variants(word):
    variants = {}
    lower = word.lower()

    for old, replacements, rule, probability in SUBSTITUTIONS:
        start = 0
        while True:
            idx = lower.find(old, start)
            if idx == -1:
                break
            for new in replacements:
                variant = replace_at(lower, idx, old, new)
                if variant != lower and variant.isalpha():
                    current = variants.get(variant)
                    if current is None or probability > current["probability"]:
                        variants[variant] = {
                            "spelling": variant,
                            "probability": probability,
                            "rule": rule,
                        }
            start = idx + 1

    for extra in [drop_final_silent_e(lower), double_final_consonant(lower)]:
        if extra and extra["spelling"] != lower and extra["spelling"].isalpha():
            variants.setdefault(extra["spelling"], extra)

    return sorted(
        variants.values(),
        key=lambda item: (-item["probability"], item["spelling"]),
    )[:MAX_VARIANTS_PER_WORD]


def main():
    if not JSON_PATH.exists():
        raise SystemExit("Run 03_conv_csv_to_json_en.py first.")

    data = json.loads(JSON_PATH.read_text(encoding="utf-8"))
    words_with_variants = 0
    total_variants = 0

    for entry in data.get("vocabulary", []):
        variants = generate_variants(entry.get("word") or "")
        entry["graphemeVariants"] = variants
        entry["graphematicVariants"] = variants
        if variants:
            words_with_variants += 1
            total_variants += len(variants)

    data.setdefault("metadata", {})["hasGraphematicVariants"] = True
    data["metadata"]["grapheme_variant_strategy"] = "english_pattern_substitutions"
    data["metadata"]["words_with_grapheme_variants"] = words_with_variants
    data["metadata"]["total_grapheme_variants"] = total_variants

    JSON_PATH.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(
        f"Generated {total_variants} variants for "
        f"{words_with_variants}/{len(data.get('vocabulary', []))} words."
    )


if __name__ == "__main__":
    main()
