#!/usr/bin/env python3
"""Write pipeline/llm_review/<lang>_synonym_senses.jsonl: each word's
synonyms ranked by sense, with what the old pipeline let in taken out.

    python3 tools/pack/build_synonym_senses.py DE_PACK.db \
        --wiktionary DIR_WITH_PARQUET   # cstr/de-wiktionary-extracted
        --openthesaurus openthesaurus_dump.sql \
        [--wn ~/.wn_data/wn.db]         # holds OdeNet 1.4
    python3 tools/pack/build_synonym_senses.py EN_PACK.db --lang en   # NLTK WordNet

The rules are in thesaurus_de.py and thesaurus_en.py. Terms the three-judge review accepted for
the word (de_lexrel.jsonl) go first and are never dropped for being weak,
only for being the word itself or offensive.

The sources are large and not in the repo, so this runs on a laptop and the
JSONL is committed; apply_llm_overlay.py applies it in CI, to rows whose
lists are still the ones read here.
"""
import argparse
import collections
import json
import os
import pathlib
import sqlite3
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import thesaurus_de as T  # noqa: E402
from llm_correct import OUT_DIR, entry_key, _terms  # noqa: E402
from apply_llm_overlay import synonym_lists_digest as lists_digest  # noqa: E402

NEVER_KEEP = {'self', 'offensive', 'offensive elsewhere', 'pattern'}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('pack')
    ap.add_argument('--lang', choices=('de', 'en'), default='de')
    ap.add_argument('--wiktionary')
    ap.add_argument('--openthesaurus')
    ap.add_argument('--wn', default=os.path.expanduser('~/.wn_data/wn.db'))
    ap.add_argument('--out')
    args = ap.parse_args()
    args.out = args.out or str(OUT_DIR / f'{args.lang}_synonym_senses.jsonl')
    if args.lang == 'de' and not (args.wiktionary and args.openthesaurus):
        ap.error('German needs --wiktionary and --openthesaurus')

    db = sqlite3.connect(f'file:{args.pack}?mode=ro', uri=True)
    db.row_factory = sqlite3.Row
    rows = db.execute('SELECT * FROM words').fetchall()
    accepted = {}
    lexrel = OUT_DIR / f'{args.lang}_lexrel.jsonl'
    if lexrel.exists():
        for line in lexrel.read_text(encoding='utf-8').splitlines():
            if line.strip():
                r = json.loads(line)
                accepted[r['id']] = {t.lower() for t in r.get('synonyms') or []}

    if args.lang == 'de':
        print('reading OpenThesaurus, OdeNet, Wiktionary ...', file=sys.stderr)
        ot = T.OpenThesaurus(args.openthesaurus)
        odenet = T.OdeNet(args.wn)
        wikt = T.Wiktionary(args.wiktionary, {r['word'] for r in rows})
        common = T.frequent_words(HERE.parent.parent / 'pipeline' / 'voc-de')
        weak, tiers = T.WEAK_TIERS, T.TIERS

        def review(row, enrichment, syns):
            return T.review(row['word'], row['word_type'],
                            enrichment.get('definitions') or [], syns,
                            odenet, ot, wikt, common)

        def antonyms_of(row, ants):
            return T.clean_antonyms(row['word'], ants, ot)
    else:
        import thesaurus_en as E
        wordnet = E.WordNet()
        weak, tiers = E.WEAK_TIERS, E.TIERS

        def review(row, enrichment, syns):
            return E.review(row['word'], row['word_type'], syns, wordnet)

        def antonyms_of(row, ants):
            return E.clean_antonyms(row['word'], ants, wordnet)

    totals = collections.Counter()
    with open(args.out, 'w', encoding='utf-8') as out:
        for row in rows:
            enrichment = json.loads(row['enrichment_json'] or '{}')
            syns, ants = _terms(enrichment.get('synonyms')), _terms(enrichment.get('antonyms'))
            if not syns and not ants:
                continue
            drop, ranked = review(row, enrichment, syns)
            ok = accepted.get(entry_key(row), set())
            first = [t for t, _ in ranked if t.lower() in ok]
            rest = [t for t, tier in ranked
                    if t.lower() not in ok and tier not in weak]
            for term, reason in list(drop.items()):
                text = T.bare(term)[0] if args.lang == 'de' else term.replace('_', ' ')
                if text.lower() in ok and reason not in NEVER_KEEP \
                        and text.lower() not in {t.lower() for t in first}:
                    first.append(text)
                    del drop[term]
            for t, tier in ranked:
                if tier in weak and t.lower() not in ok:
                    drop[t] = f'weak: {tiers[tier]}'
            ant_drop, antonyms = antonyms_of(row, ants)
            for reason in list(drop.values()) + list(ant_drop.values()):
                totals[reason.split(':')[0]] += 1
            totals['kept'] += len(first) + len(rest)
            dropped = {**drop, **{f'antonym {k}': v for k, v in ant_drop.items()}}
            # Name what was taken out for a reason worth checking; only count
            # the duplicates and the weak tiers, which are most of it.
            counted = collections.Counter(why.split(':')[0] for why in dropped.values()
                                          if why.split(':')[0] in ('weak', 'duplicate'))
            record = {'id': entry_key(row), 'word': row['word'],
                      'src': lists_digest(enrichment),
                      'synonyms': first + rest, 'antonyms': antonyms,
                      'dropped': {k: v for k, v in dropped.items()
                                  if v.split(':')[0] not in counted}}
            if counted:
                record['dropped_count'] = dict(counted)
            out.write(json.dumps(record, ensure_ascii=False) + '\n')
    print(json.dumps(dict(totals), ensure_ascii=False))


if __name__ == '__main__':
    main()
