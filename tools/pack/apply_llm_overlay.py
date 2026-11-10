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

Where pipeline/llm_review/<lang>.audit.jsonl exists (llm_correct.py audit),
only the changes it confirmed are applied. Two further guards are rules,
not judgement: a plural must start like its word, and a German word a
state's Grundwortschatz teaches is never marked "not vocabulary".

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
and three particles that fit none of them. A row whose rewrite failed
verification is removed as well. Its Wiktionary quotations are
dropped: they are adult prose, and the reviewed sentences replace them.
Where pipeline/llm_review/en_phrasal_fits.jsonl has judged a row's gaps,
its distractors are instead every particle neither judge said fits any of
its kept sentences.

pipeline/llm_review/<lang>_relations.jsonl adds metadata.llm_classes (the
classes the spelling is used in, for the word-class games) and, for nouns
and verbs, metadata.llm_category (the hypernym game's answer, "" for none).

Idempotent: applying twice changes nothing the second time.
"""
import argparse
import json
import pathlib
import re
import sqlite3
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from llm_correct import (OUT_DIR, PARTICLES, RELATIONS_TEXT,  # noqa: E402
                         digest, entry_of, relation_entry)

GENUS = {'der': 'mask.', 'die': 'fem.', 'das': 'neut.'}


TAUGHT = ('fry', 'dolch', 'cambridge_yle', 'de_curriculum', 'uk_y')
GERMAN_LISTS = {'BAYERN', 'BERLIN', 'BRANDENBURG', 'BW1', 'BW3', 'HESSEN',
                'NIEDERSACHSEN', 'NRW111', 'NRW422', 'RHEINLAND_PFALZ',
                'SCHLESWIG_HOLSTEIN'}


def taught(metadata):
    tags = [str(t).lower() for t in metadata.get('tags') or []]
    sources = {str(s).upper() for s in metadata.get('sources') or []}
    return (bool(metadata.get('cefr_level'))
            or any(k in t for t in tags for k in TAUGHT)
            or bool(sources & GERMAN_LISTS))


def fold(text):
    return (text.lower().replace('ä', 'a').replace('ö', 'o')
            .replace('ü', 'u'))


def load_audit(lang):
    path = OUT_DIR / f'{lang}.audit.jsonl'
    if not path.exists():
        return None
    verdicts = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        if line.strip():
            r = json.loads(line)
            verdicts[r['key']] = r['ok']
    return verdicts


def load(lang):
    path = OUT_DIR / f'{lang}.jsonl'
    latest = {}
    for line in path.read_text(encoding='utf-8').splitlines():
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
    audited = load_audit(args.lang)
    db = sqlite3.connect(args.pack)
    db.row_factory = sqlite3.Row
    counts = {'applied': 0, 'stale': 0, 'missing': 0, 'unchanged': 0}
    fields = {}
    for entry_id, record in corrections.items():
        by_row = entry_id.startswith('row:')
        row = db.execute('SELECT id, original_id, word, word_type, article, genus, '
                         'grade_level, enrichment_json, metadata_json FROM words '
                         + ('WHERE id = ? AND original_id IS NULL' if by_row
                            else 'WHERE original_id = ?'),
                         (int(entry_id[4:]) if by_row else entry_id,)).fetchone()
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
        change = dict(record['change'])
        # Only what the audit confirmed, when there is an audit: a change it
        # flagged, or never got to, is not applied.
        if audited is not None:
            confirmed = {f for f in change
                         if audited.get(f"{entry_id}|{record['src']}|{f}") is True}
            if 'vocabulary' in confirmed:
                confirmed.add('not_vocabulary')
            dropped_fields = set(change) - confirmed
            for f in dropped_fields:
                counts['audit_dropped'] = counts.get('audit_dropped', 0) + 1
            change = {k: v for k, v in change.items() if k in confirmed}
        # A plural starts like its word (Hund/Hunde, Apfel/Äpfel, Haus/Häuser).
        # The first run gave Tröpfchen the plural "Vanillen": an answer that
        # belonged to another entry of the batch.
        if 'plural' in change and isinstance(change['plural'], str) and \
                fold(change['plural'][:2]) != fold(row['word'][:2]):
            change.pop('plural')
        # A German word a state's Grundwortschatz teaches is vocabulary,
        # whatever a model said: "fett" was called a misspelling, "Kindern"
        # not a word.
        if args.lang == 'de' and taught(metadata):
            change.pop('vocabulary', None)
            change.pop('not_vocabulary', None)
        if not change:
            counts['nothing_left'] = counts.get('nothing_left', 0) + 1
            continue
        word_type, article, genus = row['word_type'], row['article'], row['genus']
        if 'definition' in change:
            old = [d for d in enrichment.get('definitions') or []
                   if d != change['definition']]
            enrichment['definitions'] = [change['definition']] + old
            metadata['gloss_source'] = 'llm-reviewed'
            metadata.pop('gloss_above_reader', None)
        # Months, weekdays, Christmas: English capitalises them and the models
        # called them proper nouns, which takes a word out of every game. A
        # word a curriculum list or a CEFR level teaches is vocabulary.
        if change.get('word_type') == 'proper_noun' and taught(metadata):
            change = {k: v for k, v in change.items() if k != 'word_type'}
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
    relations = apply_relations(db, args.lang)
    db.commit()
    print(json.dumps({'corrections': len(corrections), **counts, 'fields': fields,
                      **({'phrasal': phrasal} if phrasal else {}),
                      **({'relations': relations} if relations else {})}))


def find_row(db, entry_id, columns):
    by_row = entry_id.startswith('row:')
    return db.execute(f'SELECT {columns} FROM words '
                      + ('WHERE id = ? AND original_id IS NULL' if by_row
                         else 'WHERE original_id = ?'),
                      (int(entry_id[4:]) if by_row else entry_id,)).fetchone()


def apply_relations(db, lang):
    """metadata.llm_classes and metadata.llm_category from <lang>_relations.jsonl.

    llm_classes: the classes two models of different families named for the
    spelling, united — a word-class game asks only where it is one class, and
    that class is the column's. llm_category: for a noun or verb, the category
    word the verifier confirmed, or "" where none was (the hypernym game then
    leaves the word out rather than fall back on WordNet's every-sense list).
    Applied against the corrected row, after the corrections above, since
    that is what the models were shown.
    """
    path = OUT_DIR / f'{lang}_relations.jsonl'
    if not path.exists():
        return None
    latest = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        if line.strip():
            record = json.loads(line)
            latest[record['id']] = record
    counts = {'applied': 0, 'stale': 0, 'missing': 0}
    too_general = {w.strip().lower()
                   for w in RELATIONS_TEXT[lang]['too_general'].split(',')}
    for entry_id, record in latest.items():
        row = find_row(db, entry_id, 'id, original_id, word, word_type, article, '
                                     'enrichment_json, metadata_json')
        if row is None:
            counts['missing'] += 1
            continue
        if digest(relation_entry(row, lang)) != record['src']:
            counts['stale'] += 1
            continue
        metadata = json.loads(row['metadata_json'] or '{}')
        if record.get('classes'):
            metadata['llm_classes'] = record['classes']
        if record.get('word_type') in ('noun', 'verb'):
            category = (record.get('category') or '').strip()
            # The prompt names the answers too general to ask for, and a model
            # still gave "Nachbarin -> Person"; the list is a rule here.
            if category.lower() in too_general:
                category = ''
            metadata['llm_category'] = category
        db.execute('UPDATE words SET metadata_json=? WHERE id=?',
                   (json.dumps(metadata, ensure_ascii=False), row['id']))
        counts['applied'] += 1
    return counts


def load_fits():
    """Sentence-with-gap -> the particles any judge said fills it."""
    path = OUT_DIR / 'en_phrasal_fits.jsonl'
    if not path.exists():
        return None
    fits = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        if line.strip():
            r = json.loads(line)
            # Every round's judges are united: a particle any of them
            # accepted is never offered as wrong.
            fits.setdefault(r['sentence'], set()).update(r['fits'])
    return fits


def safe_distractors(record, fits, attested=frozenset()):
    """The sentences to keep and the particles that fit none of them.

    A sentence is kept only if at least three particles fit nowhere in it;
    the distractors are the particles that fit none of the kept sentences.
    A particle that makes another phrasal verb in [attested] with the same
    verb is never a distractor, whatever the judges said: four of them let
    "She put ___ the tent." offer "away".
    Returns (sentences, distractors), or None when no sentence leaves three.
    """
    verb, particle = record['id'].split(' ', 1)
    taken = {p for p in PARTICLES if f'{verb} {p}' in attested}
    scored = []
    for sentence in record['sentences']:
        gap = re.sub(r'\b' + re.escape(particle) + r'\b', '___', sentence,
                     count=1, flags=re.I)
        if gap not in fits:
            return None  # not judged yet: keep the verified rewrite as it is
        wrong = [p for p in PARTICLES
                 if p != particle and p not in fits[gap] and p not in taken]
        scored.append((sentence, set(wrong)))
    kept, common = [], None
    for sentence, wrong in sorted(scored, key=lambda x: -len(x[1])):
        joint = wrong if common is None else common & wrong
        if len(joint) >= 3:
            kept.append(sentence)
            common = joint
    if not kept:
        return ([], [])
    return (kept, [p for p in PARTICLES if p in common])


def apply_phrasal(db):
    path = OUT_DIR / 'en_phrasal.jsonl'
    if not path.exists():
        return None
    counts = {'rewritten': 0, 'removed': 0, 'unverified, removed': 0,
              'no safe distractors, removed': 0}
    fits = load_fits()
    attested = {row[0] for row in db.execute('SELECT phrasal FROM phrasal_verbs')}
    listed = OUT_DIR / 'en_attested_phrasals.txt'
    if listed.exists():
        attested |= {line.strip() for line in listed.read_text().splitlines()
                     if line.strip() and not line.startswith('#')}
    latest = {}
    for line in path.read_text(encoding='utf-8').splitlines():
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
            safe = safe_distractors(record, fits, attested) if fits is not None else None
            if safe is not None:
                sentences, wrong = safe
                if not sentences:
                    db.execute('DELETE FROM phrasal_verbs WHERE id = ?', (row['id'],))
                    counts['no safe distractors, removed'] += 1
                    continue
                record = {**record, 'sentences': sentences, 'wrong_particles': wrong}
            db.execute('UPDATE phrasal_verbs SET meaning=?, examples_json=?, '
                       'distractors_json=?, wiktionary_examples_json=? WHERE id=?',
                       (record['meaning'],
                        json.dumps({str(row['grade_band'] or 3): record['sentences']},
                                   ensure_ascii=False),
                        json.dumps(record['wrong_particles']), '[]', row['id']))
            counts['rewritten'] += 1
        else:
            # Read, rewritten, and the rewrite failed verification. The row's
            # own data is what the read found broken ("I join out."), so it
            # goes too: a missing item costs less than a wrong one.
            db.execute('DELETE FROM phrasal_verbs WHERE id = ?', (row['id'],))
            counts['unverified, removed'] += 1
    return counts


if __name__ == '__main__':
    main()
