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
                         digest, entry_of, lexrel_candidates,
                         pack_vocabulary, relation_entry)
from llm_correct import _terms as terms  # noqa: E402

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
    # lexrel first: it names the candidates the judges turned down, which
    # are read from the lists as they were reviewed.
    lexrel = apply_lexrel(db, args.lang)
    senses = apply_synonym_senses(db, args.lang)
    # Last: they change the leading gloss the steps above were read against;
    # the sense check was read against the children's glosses.
    kidgloss = apply_kidgloss(db, args.lang)
    sense = apply_sense(db, args.lang)
    finished = finish_glosses(db)
    db.commit()
    print(json.dumps({'corrections': len(corrections), **counts, 'fields': fields,
                      **({'phrasal': phrasal} if phrasal else {}),
                      **({'relations': relations} if relations else {}),
                      **({'synonym_senses': senses} if senses else {}),
                      **({'lexrel': lexrel} if lexrel else {}),
                      **({'kidgloss': kidgloss} if kidgloss else {}),
                      **({'sense': sense} if sense else {}),
                      'glosses_finished': finished}))


# The app's isUsableDefinition (lib/core/models/vocabulary_quality.dart)
# reads a gloss with no closing punctuation that ends on one of these words
# as cut off: the source packs have "eine Hupe am Kraftfahrzeug betätigen,
# um". A gloss a model wrote whole can end on one too ("damit isst man
# Suppe oder rührt um", "nicht immer, aber ab und zu"), and lost
# "Löffel" and "manchmal" the word of the day. Keep in step with
# _danglingWords there.
DANGLING = {
    'um', 'und', 'oder', 'dass', 'zu', 'mit', 'von', 'für', 'der', 'die', 'das',
    'ein', 'eine', 'einen', 'einem', 'einer', 'im', 'am', 'beim', 'zum', 'zur',
    'wenn', 'weil', 'sich', 'als', 'aus', 'auf', 'in',
    'to', 'of', 'the', 'a', 'an', 'and', 'or', 'that', 'with', 'for', 'by',
    'from', 'as', 'at', 'on',
}
WRITTEN_WHOLE = {'llm-reviewed', 'llm-sense'}


def finish_glosses(db):
    """A full stop after a model-written leading gloss that ends on a word
    the app takes for a cut. Runs after every step that reads the leading
    gloss, so no record's digest sees it."""
    n = 0
    for row_id, enr, meta in db.execute(
            'SELECT id, enrichment_json, metadata_json FROM words').fetchall():
        metadata = json.loads(meta or '{}')
        if metadata.get('gloss_source') not in WRITTEN_WHOLE:
            continue
        enrichment = json.loads(enr or '{}')
        defs = enrichment.get('definitions') or []
        if not defs or not isinstance(defs[0], str):
            continue
        gloss = defs[0].rstrip()
        if not gloss or gloss[-1] in '.!?,;:' or \
                gloss.split()[-1].lower() not in DANGLING:
            continue
        enrichment['definitions'] = [gloss + '.'] + defs[1:]
        db.execute('UPDATE words SET enrichment_json=? WHERE id=?',
                   (json.dumps(enrichment, ensure_ascii=False), row_id))
        n += 1
    return n


def synonym_lists_digest(enrichment):
    import hashlib
    body = json.dumps([enrichment.get('synonyms') or [],
                       enrichment.get('antonyms') or []],
                      sort_keys=True, ensure_ascii=False)
    return hashlib.sha256(body.encode()).hexdigest()[:16]


def apply_synonym_senses(db, lang):
    """Synonyms ranked by sense, from <lang>_synonym_senses.jsonl.

    Written by build_synonym_senses.py from Wiktionary, OpenThesaurus and
    OdeNet: the word itself, offensive terms, hidden synsets and terms of
    no sense the word shows are gone, and the terms of the meaning shown
    first come first. Applied only where the lists are still the ones it
    read.
    """
    path = OUT_DIR / f'{lang}_synonym_senses.jsonl'
    if not path.exists():
        return None
    counts = {'applied': 0, 'stale': 0, 'missing': 0}
    for line in path.read_text(encoding='utf-8').splitlines():
        if not line.strip():
            continue
        record = json.loads(line)
        row = find_row(db, record['id'], 'id, enrichment_json, metadata_json')
        if row is None:
            counts['missing'] += 1
            continue
        enrichment = json.loads(row['enrichment_json'] or '{}')
        if synonym_lists_digest(enrichment) != record['src']:
            counts['stale'] += 1
            continue
        enrichment['synonyms'] = record['synonyms']
        enrichment['antonyms'] = record['antonyms']
        metadata = json.loads(row['metadata_json'] or '{}')
        for key in ('synonyms', 'antonyms'):
            listed = {t.lower() for t in record[key]}
            for field in (f'llm_{key}', f'llm_rejected_{key}'):
                if field in metadata:
                    metadata[field] = [t for t in metadata[field] if t.lower() in listed]
        db.execute('UPDATE words SET enrichment_json=?, metadata_json=? WHERE id=?',
                   (json.dumps(enrichment, ensure_ascii=False),
                    json.dumps(metadata, ensure_ascii=False), row['id']))
        counts['applied'] += 1
    return counts


def apply_lexrel(db, lang):
    """metadata.llm_synonyms and metadata.llm_antonyms from <lang>_lexrel.jsonl.

    The listed synonyms and antonyms that three judges of different families
    all accepted for the word's usual meaning. Written even when empty: an
    empty list means the review found no answer to ask, which is different
    from not having been reviewed. Kept only where the term is still listed,
    so a later change to the lists cannot smuggle a term in.

    Also metadata.llm_rejected_*: the candidates put to the judges that they
    did not accept, so a list shown to a child can leave them out.
    """
    path = OUT_DIR / f'{lang}_lexrel.jsonl'
    if not path.exists():
        return None
    latest = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        if line.strip():
            record = json.loads(line)
            latest[record['id']] = record
    counts = {'applied': 0, 'stale': 0, 'missing': 0}
    vocabulary = pack_vocabulary(db)
    for entry_id, record in latest.items():
        row = find_row(db, entry_id, 'id, original_id, word, word_type, article, '
                                     'grade_level, enrichment_json, metadata_json')
        if row is None:
            counts['missing'] += 1
            continue
        if digest(relation_entry(row, lang)) != record['src']:
            counts['stale'] += 1
            continue
        enrichment = json.loads(row['enrichment_json'] or '{}')
        metadata = json.loads(row['metadata_json'] or '{}')
        asked = dict(zip(('synonyms', 'antonyms'), lexrel_candidates(row, vocabulary)))
        for key in ('synonyms', 'antonyms'):
            listed = {t.lower() for t in terms(enrichment.get(key))}
            metadata[f'llm_{key}'] = [t for t in record.get(key) or []
                                      if t.lower() in listed]
            accepted = {t.lower() for t in record.get(key) or []}
            metadata[f'llm_rejected_{key}'] = [t for t in asked[key]
                                               if t.lower() not in accepted]
        db.execute('UPDATE words SET metadata_json=? WHERE id=?',
                   (json.dumps(metadata, ensure_ascii=False), row['id']))
        counts['applied'] += 1
    return counts


def apply_kidgloss(db, lang):
    """The children's gloss of <lang>_kidgloss.jsonl, where the check passed.

    It goes first and the old glosses stay behind it, as with a corrected
    gloss above; gloss_source says it was written for the word.
    """
    path = OUT_DIR / f'{lang}_kidgloss.jsonl'
    if not path.exists():
        return None
    latest = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        if line.strip():
            record = json.loads(line)
            latest[record['id']] = record
    counts = {'applied': 0, 'unchanged': 0, 'rejected': 0, 'stale': 0, 'missing': 0}
    for entry_id, record in latest.items():
        if not record.get('ok'):
            counts['rejected'] += 1
            continue
        row = find_row(db, entry_id, 'id, original_id, word, word_type, article, '
                                     'enrichment_json, metadata_json')
        if row is None:
            counts['missing'] += 1
            continue
        if digest(relation_entry(row, lang)) != record['src']:
            counts['stale'] += 1
            continue
        gloss = record['gloss'].strip()
        if gloss == record.get('old'):
            counts['unchanged'] += 1
            continue
        enrichment = json.loads(row['enrichment_json'] or '{}')
        metadata = json.loads(row['metadata_json'] or '{}')
        enrichment['definitions'] = [gloss] + [
            d for d in enrichment.get('definitions') or [] if d != gloss]
        metadata['gloss_source'] = 'llm-reviewed'
        metadata.pop('gloss_above_reader', None)
        db.execute('UPDATE words SET enrichment_json=?, metadata_json=? WHERE id=?',
                   (json.dumps(enrichment, ensure_ascii=False),
                    json.dumps(metadata, ensure_ascii=False), row['id']))
        counts['applied'] += 1
    return counts


def apply_sense(db, lang):
    """The meaning a child means, from <lang>_sense.jsonl, where it was not
    the one shown first and a judge of another family confirmed the change.

    "Kater" led with a hangover (grade 1); it now leads with a male cat. The
    old gloss stays behind it: it is a meaning of the word, just not the one
    a child is asked about.
    """
    path = OUT_DIR / f'{lang}_sense.jsonl'
    if not path.exists():
        return None
    latest = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        if line.strip():
            record = json.loads(line)
            latest[record['id']] = record
    counts = {'applied': 0, 'kept': 0, 'unconfirmed': 0, 'stale': 0, 'missing': 0}
    for entry_id, record in latest.items():
        if record.get('ok'):
            counts['kept'] += 1
            continue
        if not record.get('confirmed') or not record.get('gloss'):
            counts['unconfirmed'] += 1
            continue
        row = find_row(db, entry_id, 'id, original_id, word, word_type, article, '
                                     'enrichment_json, metadata_json')
        if row is None:
            counts['missing'] += 1
            continue
        if digest(relation_entry(row, lang)) != record['src']:
            counts['stale'] += 1
            continue
        gloss = record['gloss'].strip()
        enrichment = json.loads(row['enrichment_json'] or '{}')
        metadata = json.loads(row['metadata_json'] or '{}')
        enrichment['definitions'] = [gloss] + [
            d for d in enrichment.get('definitions') or [] if d != gloss]
        metadata['gloss_source'] = 'llm-sense'
        metadata.pop('gloss_above_reader', None)
        db.execute('UPDATE words SET enrichment_json=?, metadata_json=? WHERE id=?',
                   (json.dumps(enrichment, ensure_ascii=False),
                    json.dumps(metadata, ensure_ascii=False), row['id']))
        counts['applied'] += 1
    return counts


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
