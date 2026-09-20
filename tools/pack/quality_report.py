#!/usr/bin/env python3
"""What each content rule keeps out of the games, and what it costs.

    python3 tools/pack/quality_report.py <pack.db> [--samples 8]

The app decides what a learner may be asked from prose: is this gloss a
meaning or a parse, does it name a place, is this entry a misspelling. Those
rules are substring lists, and a substring list is one careless entry away
from removing a tenth of the catalogue — " state of " read "The state of
being free from illness" as a place name, and `often_misspelled` was read as
"this is a misspelling" when it marks the *pair*, which took "add", "all" and
"and" out of the English catalogue without a single test failing.

For each rule this prints how many entries it excludes, how many it is the
*only* rule to exclude, and — the number to read first — how many of those
are attested vocabulary: a CEFR level, or a place on a curriculum word list.
A rule that excludes attested vocabulary is either wrong or worth an argument.

Rules are read from lib/core/models/vocabulary_quality.dart, so this reports
on what ships rather than on a copy of it.
"""
import argparse
import importlib.util
import json
import pathlib
import sqlite3
import sys
from collections import Counter

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('repair', HERE / 'repair_pack.py')
repair = importlib.util.module_from_spec(spec)
spec.loader.exec_module(repair)


def rule_hits(word, definitions, metadata, rules):
    """Every rule that would keep this entry out of a question."""
    hits = []
    tags = [str(tag).lower() for tag in metadata.get('tags') or []]
    sources = [str(source).upper() for source in metadata.get('sources') or []]
    if (any(marker in tag for tag in tags for marker in repair.MISSPELLING_TAGS)
            and not any(repair.VOCABULARY_TAGS.match(tag) for tag in tags)):
        hits.append('misspelling tags')
    if any('COMMON_MISSPELL' in source for source in sources):
        hits.append('misspelling source')

    described = [definition for definition in definitions
                 if isinstance(definition, str) and definition.strip()]
    if not described:
        hits.append('no gloss')
        return hits

    gloss = described[0]
    lower = gloss.lower()
    if any(marker in lower for marker in rules['misspelling_markers']):
        hits.append('gloss: says misspelling')
    if len(gloss.strip()) < 4:
        hits.append('gloss: too short')
    if gloss.strip().endswith(':'):
        hits.append('gloss: bare label')
    if ' ' not in gloss.strip():
        hits.append('gloss: single word')
    if any(marker in lower for marker in rules['form_markers']):
        hits.append('gloss: grammatical parse')
    if any(marker in lower for marker in rules['abbreviation_markers']):
        hits.append('gloss: abbreviation')
    if repair.describes_a_name(gloss, rules):
        hits.append('gloss: names something')
    if repair.ends_mid_sentence(gloss, rules):
        hits.append('gloss: stops mid-sentence')
    return hits


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('pack', type=pathlib.Path)
    parser.add_argument('--samples', type=int, default=8)
    args = parser.parse_args()

    rules = repair.load_rules()
    db = sqlite3.connect(args.pack)
    db.row_factory = sqlite3.Row

    total = 0
    excluded = 0
    hit_counts = Counter()
    only_counts = Counter()
    attested_counts = Counter()
    samples = {}
    attested_samples = {}

    for row in db.execute(
            'SELECT word, grade_level, enrichment_json, metadata_json '
            'FROM words'):
        total += 1
        enrichment = json.loads(row['enrichment_json'] or '{}')
        metadata = json.loads(row['metadata_json'] or '{}')
        hits = rule_hits(row['word'], enrichment.get('definitions') or [],
                         metadata, rules)
        if not hits:
            continue
        excluded += 1
        attested = repair.is_attested_vocabulary(metadata)
        for rule in hits:
            hit_counts[rule] += 1
            samples.setdefault(rule, []).append(row['word'])
            if len(hits) == 1:
                only_counts[rule] += 1
            if attested:
                attested_counts[rule] += 1
                attested_samples.setdefault(rule, []).append(row['word'])
    db.close()

    width = max(len(rule) for rule in hit_counts) if hit_counts else 10
    print(f'{args.pack.name}: {total} entries, {excluded} kept out of '
          f'questions ({100 * excluded / total:.1f}%)\n')
    print(f'{"rule".ljust(width)}   excludes   only it   attested')
    for rule, count in hit_counts.most_common():
        print(f'{rule.ljust(width)}   {count:8d}   {only_counts[rule]:7d}   '
              f'{attested_counts[rule]:8d}')
    print()
    for rule, count in hit_counts.most_common():
        print(f'{rule}: {", ".join(samples[rule][:args.samples])}')
        if attested_counts[rule]:
            print(f'  ATTESTED VOCABULARY ({attested_counts[rule]}): '
                  f'{", ".join(attested_samples[rule][:args.samples])}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
