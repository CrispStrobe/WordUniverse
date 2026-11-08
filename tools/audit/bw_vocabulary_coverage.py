#!/usr/bin/env python3
"""Read-only audit of the pinned DE pack against the repository's BW lists.

The database is opened with SQLite mode=ro and query_only. No input is
modified and no downloads are performed. Output goes to stdout. The
membership format exports only official list membership, never invented
definitions, calibrated difficulty, or a claim of complete test coverage.

Examples (from the repository root):
  python3 tools/audit/bw_vocabulary_coverage.py /path/grundwortschatz-app.db
  python3 tools/audit/bw_vocabulary_coverage.py /path/grundwortschatz-app.db \
      --official-dir /path/to/four-docx-files --as-of 2026-11-08
  python3 tools/audit/bw_vocabulary_coverage.py --format membership \
      --official-dir /path/to/four-docx-files --as-of 2026-11-08
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from datetime import date
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import sys
import unicodedata
import csv
import xml.etree.ElementTree as ET
import zipfile


REPO = Path(__file__).resolve().parents[2]
OFFICIAL_PAGE = (
    "https://zsl-bw.de/,Lde/Startseite/allgemein-bildende-schulen/"
    "grundwortschatz-deutsch-gs"
)
DOCUMENT_ROOT = (
    "https://zsl-bw.de/site/pbs-bw-rebrush2024/get/{document}/KULTUS.Dachmandant/"
    "KULTUS/Dienststellen/zsl/Allgemeine%20Bildung/Grundschulen/"
    "Grundwortschatz-Deutsch-GS/{filename}"
)
# Retrieved from the four Word links on OFFICIAL_PAGE on 2026-11-08.
OFFICIAL_DOCUMENTS = {
    "1L": ("documents_E463558729", "Lehrkraefte-1-2", "eca925f77cb07ee8d2460eeef7045d7db14adec22b6b59f92638c77f74f724fb"),
    "1S": ("documents_E972787316", "Schueler-1-2", "79d080acb670402b0ea48ad7cd8b1a73e77791221886d7957c73ca9ec1db957a"),
    "3L": ("documents_E-838648795", "Lehrkraefte-3-4", "f52f32a954b6382cd7dde1ada9edcd6d6dba786f2d8f6e4336128f1556573b3b"),
    "3S": ("documents_E251272688", "Schueler-3-4", "145ab75bb6560d46a878e5f6ceb0bed59b455888d42fb9529257e15ca3139108"),
}
WORD_NS = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
PAGE_LIST = re.compile(r"\d+(?:\s*,\s*\d+)*")


def text(value: str) -> str:
    """NFC and whitespace only; do not casefold German ß to ss."""
    return " ".join(unicodedata.normalize("NFC", value).split())


def lookup_key(value: str) -> str:
    """Diagnostic legacy comparison only; membership remains case sensitive."""
    return text(value).lower()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def fingerprint(path: Path, display_path: str | None = None) -> dict:
    return {
        "path": display_path or path.name,
        "bytes": path.stat().st_size,
        "sha256": sha256(path),
    }


def normalized_label(label: str) -> tuple[str, str]:
    """Remove only the explicit notations used by these official lists.

    Preserve the original label separately. In particular, '(ein) paar' is
    lower-case 'paar', not the noun 'Paar'; 'sein(-)' retains its source
    inflection-pattern context rather than becoming proof about the verb.
    """
    label = text(label)
    if label.endswith("(-)"):
        return label[:-3], "inflectionPattern"
    for prefix in ("(ein) ", "(sich) "):
        if label.startswith(prefix):
            return label[len(prefix):], "contextPhrase"
    return label, "headword"


def source_record(cells: list[str], code: str, location: dict) -> dict | None:
    cells = [text(cell) for cell in cells] + [""] * max(0, 3 - len(cells))
    if code.endswith("L"):
        if not cells[0] or not PAGE_LIST.fullmatch(cells[2]):
            return None
        return dict(location, label=cells[0], forms=cells[1], pages=cells[2])
    if not cells[1] or cells[2] == "Meine Notizen":
        return None
    record = dict(location, label=cells[1])
    if cells[0] in {"der", "die", "das"}:
        record["article"] = cells[0]
    return record


def read_csv_source(path: Path, code: str) -> dict:
    records = []
    with path.open(encoding="utf-8-sig", newline="") as stream:
        rows = list(csv.reader(stream, delimiter=";"))
    for line, cells in enumerate(rows, 1):
        record = source_record(cells, code, {"line": line})
        if record:
            records.append(record)
    return dict(fingerprint(path, f"pipeline/voc-de/{path.name}"),
                physicalRows=len(rows), records=records)


def read_official_sources(directory: Path) -> dict[str, dict]:
    result = {}
    for code, (document, stem, expected_hash) in OFFICIAL_DOCUMENTS.items():
        filename = f"{stem}-Alphabetische-Woerterlisten.docx"
        path = directory / filename
        metadata = fingerprint(path)
        if metadata["sha256"] != expected_hash:
            raise ValueError(
                f"Official document changed: {filename}. Expected {expected_hash}, "
                f"got {metadata['sha256']}. Review its provenance before updating the receipt."
            )
        with zipfile.ZipFile(path) as archive:
            document_xml = ET.fromstring(archive.read("word/document.xml"))
        records = []
        for table_number, table in enumerate(document_xml.findall(".//w:tbl", WORD_NS), 1):
            for row_number, row in enumerate(table.findall("./w:tr", WORD_NS), 1):
                cells = []
                for cell in row.findall("./w:tc", WORD_NS):
                    # Formatting splits a word over runs. Concatenate runs,
                    # then separate paragraphs, never insert spaces per run.
                    cells.append(" ".join(
                        "".join(run.text or "" for run in paragraph.findall(".//w:t", WORD_NS))
                        for paragraph in cell.findall(".//w:p", WORD_NS)
                    ))
                record = source_record(cells, code, {"table": table_number, "row": row_number})
                if record:
                    records.append(record)
        result[code] = dict(
            metadata,
            id=f"zsl-bw-{code.lower()}-2020",
            band=f"BW{code[0]}",
            audience="teacher" if code.endswith("L") else "pupil",
            url=DOCUMENT_ROOT.format(document=document, filename=filename),
            records=records,
        )
    return result


def build_membership(official: dict[str, dict], as_of: str) -> dict:
    entries = {}
    for code in ("1S", "3S"):
        source = official[code]
        for record in source["records"]:
            word, notation = normalized_label(record["label"])
            entry = entries.setdefault(word, {
                "id": "bw-" + hashlib.sha256(word.encode("utf-8")).hexdigest()[:16],
                "word": word, "sourceBands": [], "sourceLabels": [],
            })
            if source["band"] not in entry["sourceBands"]:
                entry["sourceBands"].append(source["band"])
            entry["sourceLabels"].append(dict(
                record, band=source["band"], documentId=source["id"], notation=notation,
            ))
    return {
        "schemaVersion": 1,
        "id": "bw-grundwortschatz-membership-v1",
        "version": 1,
        "language": "de",
        "locale": "de-DE",
        "provenance": {
            "checkedAt": as_of,
            "officialPage": OFFICIAL_PAGE,
            "publicationYear": 2020,
            "documents": [{key: value for key, value in source.items() if key != "records"}
                          for source in official.values()],
            "basis": "Headword labels and articles in the two official pupil lists; teacher lists checked separately.",
        },
        "normalization": {
            "unicode": "NFC", "trim": True, "collapseWhitespace": True,
            "caseSensitive": True, "stripOptionalEnding": "(-)",
            "stripContextPrefixes": ["(ein) ", "(sich) "],
            "senseRule": "Retain sourceLabels. Equal spelling does not establish equal grammatical sense; sein(-) in BW3 is not evidence about the BW1 verb sein.",
        },
        "limitations": [
            "Membership is not a definition, a difficulty calibration, or a KOMPASS test prediction.",
            "Optional endings are recorded as source patterns; the export does not enumerate all inflections.",
            "Source-case distinctions such as arm/Arm and paar/Paar must remain distinct at runtime.",
            "The official description of approximately 870 words uses a different counting basis from this normalized headword export.",
        ],
        "memberships": sorted(entries.values(), key=lambda entry: (entry["word"].lower(), entry["word"])),
    }


def pack_pins(repo: Path) -> dict:
    source = (repo / "lib/core/models/language_pack.dart").read_text(encoding="utf-8")
    block = re.search(r"'de': LanguagePack\((.*?)\n  \),", source, re.S)
    if not block:
        raise ValueError("Cannot locate German LanguagePack pins")
    fields = {}
    for name in ("remoteUrl", "expectedCompressedSha256", "expectedDecompressedSha256"):
        match = re.search(rf"\b{name}:\s*'([^']+)'", block.group(1))
        if not match:
            raise ValueError(f"Missing pack pin: {name}")
        fields[name] = match.group(1)
    for name in ("expectedCompressedBytes", "expectedDecompressedBytes"):
        match = re.search(rf"\b{name}:\s*(\d+)", block.group(1))
        if not match:
            raise ValueError(f"Missing pack pin: {name}")
        fields[name] = int(match.group(1))
    return fields


def load_pack(path: Path) -> list[dict]:
    rows = []
    with sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True) as db:
        db.execute("PRAGMA query_only = ON")
        db.row_factory = sqlite3.Row
        query = (
            "SELECT w.id,w.original_id,w.word,w.lemma,w.article,w.genus,w.word_type,"
            "w.grade_level,w.metadata_json,w.enrichment_json,i.flags,i.sources AS index_sources "
            "FROM words AS w LEFT JOIN word_feature_index AS i ON i.row_id=w.id"
        )
        for raw in db.execute(query):
            row = dict(raw)
            row["metadata"] = json.loads(row.pop("metadata_json") or "{}")
            row["enrichment"] = json.loads(row.pop("enrichment_json") or "{}")
            if not isinstance(row["metadata"], dict) or not isinstance(row["enrichment"], dict):
                raise ValueError(f"Non-object metadata/enrichment on row {row['id']}")
            rows.append(row)
    return rows


def public_row(row: dict) -> dict:
    return {
        "rowId": row["id"], "id": row["original_id"], "word": row["word"],
        "wordType": row["word_type"], "article": row["article"],
        "sources": row["metadata"].get("sources", []),
        "primaryLemma": row["enrichment"].get("primary_lemma"),
    }


def counts(values) -> dict:
    return dict(sorted(Counter(str(value) if value is not None else "missing"
                               for value in values).items()))


def audit(args) -> dict:
    pins = pack_pins(args.repo_root)
    actual = fingerprint(args.pack)
    verified = (actual["bytes"] == pins["expectedDecompressedBytes"] and
                actual["sha256"] == pins["expectedDecompressedSha256"])
    if not verified and not args.allow_unpinned:
        raise ValueError("Database does not match current DE pack pins. Use --allow-unpinned only for an intentional comparison.")
    source_dir = args.source_dir or args.repo_root / "pipeline/voc-de"
    sources = {code: read_csv_source(source_dir / f"Grundwortschatz{code}.csv", code)
               for code in OFFICIAL_DOCUMENTS}
    official = read_official_sources(args.official_dir) if args.official_dir else None
    rows = load_pack(args.pack)
    exact = defaultdict(list)
    lower = defaultdict(list)
    for row in rows:
        exact[text(row["word"])].append(row)
        lower[lookup_key(row["word"])].append(row)
    tagged = [row for row in rows if {"BW1", "BW3"}.intersection(row["metadata"].get("sources", []))]
    result = {
        "auditVersion": 1, "asOf": args.as_of,
        "pack": dict(actual, pins=pins, matchesPins=verified, rowCount=len(rows)),
        "method": {
            "strictComparison": "NFC, trim, collapse whitespace, preserve case; no lemmatization, ss/ß folding, or synonym matching.",
            "legacyComparison": "Lowercase comparison is reported separately as a diagnostic; it is not equivalent orthographic or semantic coverage.",
            "sourceParsing": "Semicolon/BOM CSV. L includes numeric page lists with commas; S excludes empty rows and Meine Notizen headers. Optional annotations remain visible.",
            "sources": "Runtime source membership is read from metadata_json.sources. Definitions/primary lemma/strategies are read from enrichment_json. Difficulty is read from metadata_json.",
        },
        "inputs": {code: {key: value for key, value in source.items() if key != "records"}
                   for code, source in sources.items()},
        "sourceLists": {}, "bands": {},
    }
    for code, source in sources.items():
        records = source["records"]
        labels = [record["label"] for record in records]
        info = {
            "headwordRows": len(labels), "distinctLabels": len(set(labels)),
            "duplicates": {label: count for label, count in Counter(labels).items() if count > 1},
            "multiplePageReferences": [record for record in records if "," in record.get("pages", "")],
        }
        if code.endswith("L"):
            # Reproduce the OLD numeric-page + isalpha + lowercase policy.
            accepted = {lookup_key(record["label"]) for record in records
                        if record["pages"].isdigit() and len(record["label"]) >= 2 and record["label"].isalpha()}
            info["legacyPolicyAcceptedDistinctLowercaseKeys"] = len(accepted)
        if official:
            official_labels = {record["label"] for record in official[code]["records"]}
            info["official"] = {
                "distinctLabels": len(official_labels),
                "missingFromRepository": sorted(official_labels - set(labels)),
                "repositoryOnly": sorted(set(labels) - official_labels),
            }
        result["sourceLists"][code] = info
    for band in ("BW1", "BW3"):
        digit = band[-1]
        labels = {record["label"] for code in (digit + "L", digit + "S") for record in sources[code]["records"]}
        plain = sorted(label for label in labels if len(label) >= 2 and label.isalpha())
        normalized = {normalized_label(label)[0] for label in labels}
        case_only = [{"sourceWord": word, "rows": [public_row(row) for row in lower[lookup_key(word)]]}
                     for word in sorted(normalized) if not exact[word] and lower[lookup_key(word)]]
        band_rows = [row for row in tagged if band in row["metadata"].get("sources", [])]
        result["bands"][band] = {
            "sourceLabels": len(labels), "plainAlphabeticLabels": len(plain),
            "plainLowercaseKeys": len(set(map(lookup_key, plain))),
            "normalizedExactSpellings": len(normalized),
            "taggedRows": len(band_rows),
            "normalizedPresentExactSpelling": sum(bool(exact[word]) for word in normalized),
            "normalizedPresentWithoutBandTagExact": sorted(
                word for word in normalized if exact[word] and
                not any(band in row["metadata"].get("sources", []) for row in exact[word])
            ),
            "taggedSpellingsAbsentFromSourceExact": [
                public_row(row) for row in band_rows if text(row["word"]) not in normalized
            ],
            "plainMissingFromDatabaseEvenIgnoringCase": [word for word in plain if not lower[lookup_key(word)]],
            "plainPresentWithoutBandTagIgnoringCase": [word for word in plain if lower[lookup_key(word)] and
                                                       not any(band in row["metadata"].get("sources", []) for row in lower[lookup_key(word)])],
            "normalizedMissingExactSpelling": sorted(word for word in normalized if not exact[word]),
            "normalizedMissingEvenIgnoringCase": sorted(word for word in normalized if not lower[lookup_key(word)]),
            "caseOnlyMatches": case_only,
            "annotatedOrHyphenatedLabels": [
                {"label": label, "candidateWord": normalized_label(label)[0],
                 "notation": normalized_label(label)[1],
                 "exactRows": [public_row(row) for row in exact[normalized_label(label)[0]]]}
                for label in sorted(labels) if not label.isalpha()
            ],
        }
    feature_text = (args.repo_root / "lib/core/models/word_features.dart").read_text(encoding="utf-8")
    bits = {name: int(bit) for name, bit in re.findall(r"^\s+(\w+)\((\d+)\)[,;]", feature_text, re.M)}
    def no_feature(row, feature):
        return row["flags"] is None or not (row["flags"] & (1 << bits[feature]))
    result["runtimeTaggedPool"] = {
        "distinctRows": len(tagged), "distinctExactSpellings": len({row["word"] for row in tagged}),
        "bothBands": [row["word"] for row in tagged if {"BW1", "BW3"}.issubset(row["metadata"].get("sources", []))],
        "allSourceTokens": sorted({source for row in tagged for source in row["metadata"].get("sources", [])}),
        "gradeLevel": counts(row["grade_level"] for row in tagged),
        "gradeLevelEstimate": counts(row["metadata"].get("gradeLevelEstimate") for row in tagged),
        "gradeLevelEstimateSource": counts(row["metadata"].get("gradeLevelEstimateSource") for row in tagged),
        "spellingDifficulty": counts(row["metadata"].get("spellingDifficulty") for row in tagged),
        "difficultyZeroWithoutLitkeyRate": sum(row["metadata"].get("spellingDifficulty") == 0 and
                                               row["metadata"].get("litkey_error_rate") is None for row in tagged),
        "withLitkeyRate": sum(row["metadata"].get("litkey_error_rate") is not None for row in tagged),
        "withLitkeySampleSize": sum(row["metadata"].get("litkey_total_tokens") is not None for row in tagged),
        "primarySpellingStrategy": counts(row["enrichment"].get("spellingStrategyPrimary") for row in tagged),
        "wordTypes": counts(row["word_type"] for row in tagged),
        "properNounRows": [dict(public_row(row), firstDefinition=(row["enrichment"].get("definitions") or [None])[0])
                           for row in tagged if row["word_type"] == "proper_noun"],
        "nonHeadwordRows": [public_row(row) for row in tagged if no_feature(row, "headword")],
        "unusableLeadingDefinitionRows": [dict(public_row(row), firstDefinition=(row["enrichment"].get("definitions") or [None])[0])
                                          for row in tagged if no_feature(row, "usableDefinition")],
        "glossAboveReaderRows": [row["word"] for row in tagged if row["metadata"].get("gloss_above_reader") is True],
        "missingFeatureIndexRows": [row["word"] for row in tagged if row["flags"] is None],
    }
    if official:
        membership = build_membership(official, args.as_of)
        result["officialDocuments"] = membership["provenance"]["documents"]
        result["officialMembership"] = {
            "distinctNormalizedExactSpellings": len(membership["memberships"]),
            "sourceLabelCount": sum(len(entry["sourceLabels"]) for entry in membership["memberships"]),
            "bands": counts(band for entry in membership["memberships"] for band in entry["sourceBands"]),
            "missingExactSpellings": [entry["word"] for entry in membership["memberships"] if not exact[entry["word"]]],
        }
    return result


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("pack", type=Path, nargs="?")
    parser.add_argument("--repo-root", type=Path, default=REPO)
    parser.add_argument("--source-dir", type=Path,
                        help="optional CSV snapshot directory, e.g. files extracted from a historical commit")
    parser.add_argument("--official-dir", type=Path)
    parser.add_argument("--as-of", default=date.today().isoformat())
    parser.add_argument("--allow-unpinned", action="store_true")
    parser.add_argument("--format", choices=("json", "membership"), default="json")
    args = parser.parse_args(argv)
    try:
        if args.format == "membership":
            if not args.official_dir:
                parser.error("--format membership requires --official-dir")
            result = build_membership(read_official_sources(args.official_dir), args.as_of)
        else:
            if not args.pack:
                parser.error("the pinned database path is required for an audit")
            result = audit(args)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (ValueError, OSError, sqlite3.Error, ET.ParseError, zipfile.BadZipFile) as error:
        print(f"BW audit failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
