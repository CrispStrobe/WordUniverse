#!/usr/bin/env python3
"""Where a pack disagrees with itself.

    python3 tools/pack/consistency_report.py <pack.db> [--samples 8]

The app inherits the packs' grammar: an article, a gender, a plural, an
inflection table. None of it is checked against anything — and where two
fields say the same thing in different words, a disagreement between them is
a data error we would otherwise show to a child as fact.

This compares the fields that overlap:

  article vs genus     "der" and "fem." cannot both be right
  article missing      a noun the games show bare where they mean to teach
                       its gender
  plural vs forms      the plural column against the declension table
  lemma vs primary     the lemma column against the enrichment's own lemma
  type vs inflection   a verb the pack lists no present form for

Nothing here is fixed automatically, and that is deliberate. Filling the 1,057
missing German articles from the gender field looks obvious until you read a
sample of what it would write: "die Chicago", "das Allah", "der Hunden", "das
Landes". The rows missing an article are largely the ones that should not be
taught at all — inflected forms, names, old spellings — and their gender field
is no more trustworthy than the rest of them. A count is worth having; a
repair needs a source the pack does not contain.
"""
import argparse
import json
import pathlib
import re
import sqlite3
from collections import Counter

GENDER_ARTICLE = {'mask.': 'der', 'fem.': 'die', 'neut.': 'das'}
ARTICLE = re.compile(r'^(der|die|das)\s+(.+)$', re.I)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('pack', type=pathlib.Path)
    parser.add_argument('--samples', type=int, default=8)
    args = parser.parse_args()

    db = sqlite3.connect(args.pack)
    db.row_factory = sqlite3.Row
    findings = Counter()
    samples = {}

    def note(kind, detail):
        findings[kind] += 1
        samples.setdefault(kind, []).append(detail)

    total = 0
    for row in db.execute(
            'SELECT word, lemma, article, genus, word_type, '
            'enrichment_json, metadata_json FROM words'):
        total += 1
        enrichment = json.loads(row['enrichment_json'] or '{}')
        metadata = json.loads(row['metadata_json'] or '{}')
        inflections = enrichment.get('inflections') or []
        forms = set()
        for inflection in inflections:
            form = str(inflection.get('form_text') or '').strip()
            if not form:
                continue
            forms.add(form)
            # The declension table writes the article in: "die Abbildungen".
            without_article = ARTICLE.match(form)
            if without_article:
                forms.add(without_article.group(2).strip())

        article = (row['article'] or '').strip().lower()
        genus = (row['genus'] or '').strip().lower()
        if article and genus:
            expected = GENDER_ARTICLE.get(genus)
            if expected and expected != article:
                note('article disagrees with genus',
                     f"{row['word']}: {article} / {genus}")
        if row['word_type'] == 'substantiv' and not article and genus:
            note('gender known, article missing',
                 f"{row['word']}: {genus}")

        plural = (metadata.get('plural') or '').strip()
        if plural and forms and plural not in forms:
            note('plural not in the inflection table',
                 f"{row['word']}: {plural}")

        # The lemma column echoes the spelling for most rows by design, so a
        # disagreement only means something where the enrichment says this
        # row *is* the lemma: then the column is simply wrong ("Abbieg").
        primary = enrichment.get('primary_lemma')
        if isinstance(primary, str) and primary and row['lemma'] and \
                primary.lower() == row['word'].lower() and \
                primary.lower() != row['lemma'].lower():
            note('lemma column is neither the word nor its lemma',
                 f"{row['word']}: {row['lemma']}")

        if row['word_type'] == 'verb' and inflections and not any(
                'present' in str(inflection.get('tags') or '')
                for inflection in inflections):
            note('verb with no present form',
                 f"{row['word']}")

    db.close()
    print(f'{args.pack.name}: {total} entries\n')
    if not findings:
        print('  nothing disagrees')
        return
    width = max(len(kind) for kind in findings)
    for kind, count in findings.most_common():
        print(f'{kind.ljust(width)}  {count:6d}   '
              f'{", ".join(samples[kind][:args.samples])}')


if __name__ == '__main__':
    main()
