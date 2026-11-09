#!/usr/bin/env python3
"""Write the reviewed corrections of tools/pack/llm_correct.py into a pack.

    python3 tools/pack/apply_llm_overlay.py <pack.db> --lang de [--report]

Runs in .github/workflows/pack-build.yml after repair_pack.py and before
index_pack.sh, so the feature index is built from the corrected rows.

Reads pipeline/llm_review/<lang>.jsonl. A correction applies only while the
entry still reads as it did when it was reviewed — the record carries a
digest of what the models saw — so a pack whose data moved on is never
"corrected" back to an older reading; those entries are counted and need
another pass.

Per field:
  definition     put first in enrichment.definitions (the app reads the first;
                 the old senses stay behind it), metadata.gloss_source =
                 "llm-reviewed", and any gloss_above_reader mark dropped
  word_type      the column
  article        the column, and genus to match
  plural         metadata.forms
  plural_only    metadata.nurImPlural
  vocabulary     metadata.quality = {vocabulary: false, reasons: [...]}

For the English pack, pipeline/llm_review/en_phrasal.jsonl rewrites the
phrasal_verbs table: a row the models agreed is not a real phrasal verb (or
not for children) is removed; a kept row gets the reviewed meaning, the
sentences that passed verification — in which only its own particle fits —
and three particles that fit none of them. Its Wiktionary quotations are
dropped: they are adult prose, and the reviewed sentences replace them.

Idempotent: applying twice changes nothing the second time.
"""
import argparse
import json
import pathlib
import re
import sqlite3
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from llm_correct import OUT_DIR, digest, entry_of  # noqa: E402

GENUS = {'der': 'mask.', 'die': 'fem.', 'das': 'neut.'}


def load(lang):
    path = OUT_DIR / f'{lang}.jsonl'
    latest = {}
    for line in open(path, encoding='utf-8'):
        if line.strip():
            record = json.loads(line)
            latest[record['id']] = record  # a later reading supersedes
    return {k: r for k, r in latest.items() if not r.get('ok') and r.get('change')}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('pack')
    parser.add_argument('--lang', choices=['de', 'en'], required=True)
    parser.add_argument('--report', action='store_true')
    args = parser.parse_args()

    corrections = load(args.lang)
    db = sqlite3.connect(args.pack)
    db.row_factory = sqlite3.Row
    counts = {'applied': 0, 'stale': 0, 'missing': 0, 'unchanged': 0}
    fields = {}
    for entry_id, record in corrections.items():
        row = db.execute('SELECT id, original_id, word, word_type, article, genus, '
                         'grade_level, enrichment_json, metadata_json FROM words '
                         'WHERE original_id = ?', (entry_id,)).fetchone()
        if row is None:
            counts['missing'] += 1
            continue
        enrichment = json.loads(row['enrichment_json'] or '{}')
        metadata = json.loads(row['metadata_json'] or '{}')
        already = metadata.get('llm_review') == record['src']
        if not already and digest(entry_of(row, args.lang)) != record['src']:
            counts['stale'] += 1
            continue
        if already:
            counts['unchanged'] += 1
            continue
        change = record['change']
        word_type, article, genus = row['word_type'], row['article'], row['genus']
        if 'definition' in change:
            old = [d for d in enrichment.get('definitions') or []
                   if d != change['definition']]
            enrichment['definitions'] = [change['definition']] + old
            metadata['gloss_source'] = 'llm-reviewed'
            metadata.pop('gloss_above_reader', None)
        if 'word_type' in change:
            word_type = change['word_type']
        if 'article' in change:
            article = change['article']
            genus = GENUS[article]
        if 'plural' in change:
            metadata['forms'] = change['plural']
        if 'plural_only' in change:
            metadata['nurImPlural'] = change['plural_only']
        # A plain word is never "not a word" or a "fragment": the models said
        # so of participles (angekommen) and plurals (problems) in an early
        # run. Those verdicts are only for spellings like "i-i" or "a-".
        if (change.get('vocabulary') is False
                and change.get('not_vocabulary') in ('not_a_word', 'fragment')
                and re.match(r"^[A-Za-zÀ-ÖØ-öø-ÿß]+$", row['word'])):
            change = {k: v for k, v in change.items()
                      if k not in ('vocabulary', 'not_vocabulary')}
        if change.get('vocabulary') is False:
            quality = metadata.get('quality') or {}
            reasons = list(quality.get('reasons') or [])
            reason = f"reviewed: {change.get('not_vocabulary', 'not_a_word')}"
            if reason not in reasons:
                reasons.append(reason)
            metadata['quality'] = {'vocabulary': False, 'reasons': reasons}
        metadata['llm_review'] = record['src']
        for k in change:
            fields[k] = fields.get(k, 0) + 1
        db.execute('UPDATE words SET word_type=?, article=?, genus=?, '
                   'enrichment_json=?, metadata_json=? WHERE id=?',
                   (word_type, article, genus,
                    json.dumps(enrichment, ensure_ascii=False),
                    json.dumps(metadata, ensure_ascii=False), row['id']))
        counts['applied'] += 1
    phrasal = apply_phrasal(db) if args.lang == 'en' else None
    db.commit()
    print(json.dumps({'corrections': len(corrections), **counts, 'fields': fields,
                      **({'phrasal': phrasal} if phrasal else {})}))


def apply_phrasal(db):
    path = OUT_DIR / 'en_phrasal.jsonl'
    if not path.exists():
        return None
    counts = {'rewritten': 0, 'removed': 0, 'left': 0}
    latest = {}
    for line in open(path, encoding='utf-8'):
        if line.strip():
            record = json.loads(line)
            if record.get('keep') is not None or record['id'] not in latest:
                latest[record['id']] = record
    for phrasal_verb, record in latest.items():
        row = db.execute('SELECT id, grade_band FROM phrasal_verbs WHERE phrasal = ?',
                         (phrasal_verb,)).fetchone()
        if row is None:
            continue
        if record.get('keep') is False:
            db.execute('DELETE FROM phrasal_verbs WHERE id = ?', (row['id'],))
            counts['removed'] += 1
        elif record.get('keep') is True:
            db.execute('UPDATE phrasal_verbs SET meaning=?, examples_json=?, '
                       'distractors_json=?, wiktionary_examples_json=? WHERE id=?',
                       (record['meaning'],
                        json.dumps({str(row['grade_band'] or 3): record['sentences']},
                                   ensure_ascii=False),
                        json.dumps(record['wrong_particles']), '[]', row['id']))
            counts['rewritten'] += 1
        else:
            counts['left'] += 1
    return counts


if __name__ == '__main__':
    main()
