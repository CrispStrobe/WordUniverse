"""Lossless readers for the BW teacher (L) and pupil (S) word-list exports.

Only documented list annotations are normalized. Raw labels, forms, page text,
CSV row numbers and list filenames remain available as source provenance.
No lowercasing is used to join declarations: ``Arm`` and ``arm`` are distinct.
"""

from dataclasses import dataclass
import csv
import json
from pathlib import Path
import re
import unicodedata


BW_COLUMNS = ["Word", "Article", "Forms", "BW_RawLabels", "BW_Pages", "BW_Provenance"]
PROVENANCE_COLUMNS = BW_COLUMNS[3:]


def parse_pages(value):
    """Return every reference in a page cell; headings/blank cells return ()."""
    value = value.strip()
    if not re.fullmatch(r"[1-9]\d*(?:\s*,\s*[1-9]\d*)*", value):
        return ()
    return tuple(int(page.strip()) for page in value.split(","))


def normalize_bw_label(raw_label):
    """Normalize explicit BW headword annotations, retaining exact case.

    Optional context belongs in provenance: ``(ein) paar`` has the display
    head ``paar`` and must remain distinct from the noun ``Paar``.
    """
    word = unicodedata.normalize("NFC", raw_label.strip())
    if word.endswith("(-)"):
        word = word[:-3]
    for prefix in ("(ein) ", "(sich) "):
        if word.startswith(prefix):
            word = word[len(prefix):]
            break
    return word


def is_valid_bw_word(word):
    """Allow verified BW heads, including E-Mail; reject unknown annotations."""
    if not isinstance(word, str) or len(word.strip()) < 2:
        return False
    return all(piece.isalpha() for piece in word.strip().split("-"))


@dataclass(frozen=True)
class BWRow:
    raw_label: str
    word: str
    forms: str
    article: str
    pages: tuple
    page_text: str
    source_file: str
    row_number: int
    list_kind: str

    def provenance(self):
        return {"file": self.source_file, "row": self.row_number,
                "list": self.list_kind, "rawLabel": self.raw_label,
                "article": self.article, "forms": self.forms,
                "pageText": self.page_text, "pages": list(self.pages)}


def read_bw_list(filename, kind):
    if kind not in ("L", "S"):
        raise ValueError("BW list kind must be L or S")
    filename = Path(filename)
    rows = []
    with filename.open(encoding="utf-8-sig", newline="") as handle:
        for number, fields in enumerate(csv.reader(handle, delimiter=";"), 1):
            fields = (fields + ["", "", ""])[:3]
            if kind == "L":
                raw_label, forms, page_text = (field.strip() for field in fields)
                pages = parse_pages(page_text)
                article = ""
                if not pages:
                    continue
            else:
                article, raw_label, notes = (field.strip() for field in fields)
                if (not raw_label or notes == "Meine Notizen"
                        or raw_label == "Weitere Wörter"
                        or re.fullmatch(r"[A-ZÄÖÜ] [a-zäöü]", raw_label)):
                    continue
                article = article if article in ("der", "die", "das") else ""
                forms, page_text, pages = "", "", ()
            word = normalize_bw_label(raw_label)
            if not is_valid_bw_word(word):
                raise ValueError(f"{filename.name}:{number}: unrecognized BW head {raw_label!r}")
            rows.append(BWRow(raw_label, word, forms, article, pages, page_text,
                              filename.name, number, kind))
    return rows


def merge_json_lists(values):
    """Union JSON arrays without losing distinct source declarations."""
    result = []
    for value in values:
        if not isinstance(value, str) or not value:
            continue
        for item in json.loads(value):
            if item not in result:
                result.append(item)
    return json.dumps(result, ensure_ascii=False) if result else ""


def merge_bw_rows(*row_lists):
    """Outer union on exact raw labels, preserving short-list-only heads."""
    groups = {}
    for rows in row_lists:
        for row in rows:
            groups.setdefault(row.raw_label, []).append(row)
    records = []
    for label, rows in groups.items():
        articles = {row.article for row in rows if row.article}
        if len(articles) > 1:
            raise ValueError(f"Conflicting BW articles for {label!r}: {sorted(articles)}")
        pages = sorted({page for row in rows for page in row.pages})
        records.append({"Word": rows[0].word, "Article": next(iter(articles), ""),
                        "Forms": next((row.forms for row in rows if row.forms), ""),
                        "BW_RawLabels": json.dumps([label], ensure_ascii=False),
                        "BW_Pages": json.dumps(pages),
                        "BW_Provenance": json.dumps([row.provenance() for row in rows],
                                                    ensure_ascii=False)})
    return records


def protected_bw_case_variants(words):
    """Protect every BW-declared head from differently cased outside sources.

    Even if BW contains only ``essen``, another list's noun ``Essen`` must not
    supply its article or replace the spelling. Same-case senses such as
    ``sein`` and ``sein(-)`` retain separate raw-label provenance records.
    """
    return {word.lower() for word in words}


def consolidation_key(word, protected_lowercase):
    """Use exact case for BW keys; preserve the old policy for other keys."""
    lower = word.lower()
    return (lower + "\x1f" + word) if lower in protected_lowercase else lower
