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

# json key -> what to keep of it. Stripping is a blunt instrument: the whole
# of `wordnetSenses` was 12.5 MB and went, and with it the only thing in either
# pack that says which *sense* a synonym or a hypernym belongs to. Everything
# the games did afterwards about senses was a heuristic standing in for data
# that had been thrown away — asking whether a hypernym is repeated in the
# word's own gloss, capping how many an entry may list, requiring the
# catalogue to confirm it.
#
# The sense-linked version answers those directly: chicken is poultry, not
# competition; hand is an extremity, not an ability; boat is a vessel, not a
# dish; charge is an attack, not a point.
#
# Reduced rather than restored. Senses carry hyponyms, holonyms, meronyms and
# a full hypernym chain that no game reads, and a sense with neither synonyms
# nor hypernyms says nothing either. What is left is 5.3 MB of 12.5, about
# 1.2 MB on the compressed artifact.
def reduce_wordnet_senses(senses):
    if not isinstance(senses, list):
        return None
    kept = [
        {
            'pos': sense.get('pos'),
            'definition': sense.get('definition'),
            'synonyms': sense.get('synonyms') or [],
            'hypernyms': sense.get('hypernyms') or [],
        }
        for sense in senses
        if isinstance(sense, dict) and (sense.get('synonyms')
                                        or sense.get('hypernyms'))
    ]
    return kept or None


# The German half of the same story. openThesaurus groups synonyms by sense —
# "Zug" is {Durchzug, Luftzug, Zugluft} in one synset and {Bahn, Eisenbahn} in
# another — and it went for the same reason wordnetSenses did. Without it the
# German pack's flat `synonyms` is every sense pooled, which is how Spielzeug
# came to be answered Werkzeug and Eingang answered Schalter.
#
# Associations and hyponyms are dropped: an association is a related word, not
# a synonym, and offering one as the answer would be the same fault by another
# route. 3.0 MB of 7.9, about 0.7 MB compressed, for 6,225 entries.
def reduce_open_thesaurus(synsets):
    if not isinstance(synsets, list):
        return None
    # No hypernyms: the field exists on every synset and is empty on all
    # 15,517 of them, so carrying it would ship bytes that claim data the
    # thesaurus does not have. German hypernyms stay on the heuristics.
    kept = [
        {
            'categories': synset.get('categories') or [],
            'synonyms': synset.get('synonyms') or [],
        }
        for synset in synsets
        if isinstance(synset, dict) and synset.get('synonyms')
    ]
    return kept or None


REDUCE_ENRICHMENT = {
    'wordnetSenses': reduce_wordnet_senses,
    'openThesaurus': reduce_open_thesaurus,
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
    # Reductions are per row, in Python: the shape is nested deeply enough
    # that doing it in SQL would be less readable than the thing it saves.
    for key, reduce in REDUCE_ENRICHMENT.items():
        updates = []
        for row_id, blob in db.execute(
                'SELECT id, enrichment_json FROM words '
                'WHERE enrichment_json IS NOT NULL '
                f"AND json_extract(enrichment_json, '$.{key}') IS NOT NULL"):
            enrichment = json.loads(blob)
            reduced = reduce(enrichment.get(key))
            if reduced == enrichment.get(key):
                continue          # already reduced; a second run is a no-op
            if reduced is None:
                enrichment.pop(key, None)
            else:
                enrichment[key] = reduced
            updates.append((json.dumps(enrichment, ensure_ascii=False), row_id))
        if updates:
            db.executemany(
                'UPDATE words SET enrichment_json = ? WHERE id = ?', updates)
            print(f'  reduced {key} on {len(updates)} rows')

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
