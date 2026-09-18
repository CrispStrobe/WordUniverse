#!/usr/bin/env python3
"""Strip enrichment the app never reads from a language pack.

    python3 tools/pack/slim_pack.py <pack.db> [--out slim.db]

The packs carry fields no code path reads — a WordNet sense dump, ConceptNet
relations, thesaurus and derived-term lists, and two duplicate copies of the
inflection list that the model takes from `enrichment_json.inflections`. They
cost download, decompression, the IndexedDB write, the cold open and the
storage quota, and nothing renders them.

Every key below was checked against the Dart accessor that reads it, not
against the JSON key name: `wiktionary_translations` looks unused by that test
and is in fact the source of `.translations`, which two games depend on.
"""
import argparse
import json
import pathlib
import shutil
import sqlite3
import subprocess
import sys

# json key -> why it goes. Keyed on enrichment_json unless noted.
DEAD_ENRICHMENT = {
    'wordnetSenses': 'not in the Dart model at all',
    'openThesaurus': 'not in the Dart model at all',
    'conceptnet': 'parsed into the model, rendered nowhere',
    'alternative_analyses': 'parsed into the model, rendered nowhere',
    'semantic_relations': 'parsed into the model, rendered nowhere',
    'wiktionary_derived_terms': '.derivedTerms is read nowhere',
    'wiktionary_related_terms': '.relatedTerms is read nowhere',
    'holonyms': '.holonyms is read nowhere',
    'meronyms': '.meronyms is read nowhere',
    'coordinate_terms': '.coordinateTerms is read nowhere',
    'hyponyms': '.hyponyms is read only by its own feature bit; no game uses it',
    'graphemeVariants': 'not the field games use — that is graphematicVariants',
}

DEAD_METADATA = {
    'inflectionData': 'duplicate; the model reads enrichment_json.inflections',
    'wiktionaryInflections': 'duplicate; same source',
    'graphemeVariants': 'not the field games use — that is graphematicVariants',
}

# Never strip these: each is read by a game. Listed so the intent is reviewable.
KEEP = [
    'definitions', 'synonyms', 'antonyms', 'hyphenation', 'examples',
    'hypernyms', 'expressions', 'proverbs', 'pronunciation', 'inflections',
    'wiktionary_translations', 'enrichment_status', 'primary_pos',
    'primary_lemma', 'entryNotes', 'inflections_pattern', 'graphematicVariants',
    'grade_examples', 'gutenberg_examples', 'commonLearnerErrors',
    'commonMistakes', 'sources', 'tags', 'cefr_level',
]


def megabytes(value):
    return f'{value / 1048576:.1f} MB'


def gzip_size(path):
    return len(subprocess.run(['gzip', '-9', '-c', str(path)],
                              capture_output=True, check=True).stdout)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('pack', type=pathlib.Path)
    parser.add_argument('--out', type=pathlib.Path)
    parser.add_argument('--gzip', action='store_true',
                        help='also report compressed sizes (slow)')
    args = parser.parse_args()

    out = args.out or args.pack.with_suffix('.slim.db')
    shutil.copyfile(args.pack, out)
    before = out.stat().st_size

    db = sqlite3.connect(out)
    before_changes = 0
    for column, dead in (('enrichment_json', DEAD_ENRICHMENT),
                         ('metadata_json', DEAD_METADATA)):
        paths = ', '.join(f"'$.{key}'" for key in dead)
        keys = ', '.join(f"'{key}'" for key in dead)
        # Only rows that actually carry a dead key are rewritten, so a second
        # run is a true no-op. The published digest is the pin, so the tool has
        # to be able to reproduce its own artifact rather than shrink it a
        # little more each time it is run.
        db.execute(
            f'UPDATE words SET {column} = json_remove({column}, {paths}) '
            f'WHERE {column} IS NOT NULL AND EXISTS ('
            f'  SELECT 1 FROM json_each(words.{column}) WHERE key IN ({keys}))')
    # total_changes, not cursor.rowcount: SQLite reports -1 for these.
    changed = db.total_changes - before_changes
    db.commit()
    if changed:
        db.execute('VACUUM')
    else:
        print('  already slim; nothing rewritten')
    rows = db.execute('SELECT COUNT(*) FROM words').fetchone()[0]

    # Nothing that games read may have gone missing.
    kept = set()
    for (blob,) in db.execute(
            'SELECT enrichment_json FROM words WHERE enrichment_json IS NOT NULL '
            'LIMIT 2000'):
        kept.update(json.loads(blob).keys())
    removed = kept & set(DEAD_ENRICHMENT)
    if removed:
        sys.exit(f'FAILED: {sorted(removed)} survived the strip')
    db.close()

    after = out.stat().st_size
    print(f'{args.pack.name}: {rows} words, {changed} rewritten')
    print(f'  before  {megabytes(before)}')
    print(f'  after   {megabytes(after)}   '
          f'({100 * (before - after) / before:.0f}% smaller)')
    if args.gzip:
        before_gz, after_gz = gzip_size(args.pack), gzip_size(out)
        print(f'  gzipped {megabytes(before_gz)} -> {megabytes(after_gz)}   '
              f'({100 * (before_gz - after_gz) / before_gz:.0f}% smaller)')
    print(f'  wrote   {out}')


if __name__ == '__main__':
    main()
