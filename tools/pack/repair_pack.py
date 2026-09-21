#!/usr/bin/env python3
"""Fix in the pack what the app has been working around at runtime.

    python3 tools/pack/repair_pack.py <pack.db> [--out repaired.db] [--report]

Three reading passes over the generated questions found the same thing each
time: the app filtering prose it cannot really judge. The packs carry entries
that are not vocabulary — a spelling-error corpus contributes "kacken" with no
gloss and no grade, Wiktionary contributes "passerbys" glossed "plural of
passerby", and a bad word-list import tags "jun", "jul", "html" and "linux" as
Fry sight words. Every game then needs a rule to keep them out of a question.

This marks them once, in the artifact, so the app can read a verdict instead
of guessing from the gloss:

  quality.vocabulary=false   the entry is not a word to ask about
  word_type=proper_noun      the gloss says it names something
  curriculum tags dropped    from entries that are neither

and it recovers entries whose *first* gloss is unusable but whose later senses
are fine, by dropping the leading ones — the app only ever reads the first.

The rules come from lib/core/models/vocabulary_quality.dart, parsed out of it
rather than copied, so the two cannot drift.

Idempotent: only rows whose verdict differs from what they already carry are
rewritten, because the published digest is the pin.
"""
import argparse
import json
import pathlib
import re
import shutil
import sqlite3
import sys
from collections import Counter

QUALITY_DART = pathlib.Path('lib/core/models/vocabulary_quality.dart')


def dart_list(source, name):
    """The string literals of a `const name = <String>[...]` / `{...}` list."""
    match = re.search(
        r'const\s+(?:List<String>\s+)?' + re.escape(name) +
        r'\s*=\s*(?:<String>)?\s*[\[{](.*?)[\]}];', source, re.S)
    if not match:
        sys.exit(f'{QUALITY_DART}: cannot find {name}')
    return [literal for literal in re.findall(r"'([^']*)'", match.group(1))]



ACCUSATIVE_ARTICLES = ('den', 'einen', 'jeden', 'diesen', 'keinen', 'unseren',
                       'meinen', 'deinen', 'seinen', 'ihren', 'euren')
DATIVE_ARTICLES = ('dem', 'einem', 'jedem', 'diesem', 'keinem', 'unserem',
                   'meinem', 'deinem', 'seinem', 'ihrem', 'eurem')


def weak_masculine_forms(db):
    """Nouns the pack declines weakly: Held → Helden, Gedanke → Gedanken.

    German marks these in every case but the nominative, and the packs'
    written examples keep forgetting: "Ich habe einen Gedanke", "den Held und
    Erzähler". The pack's own declension table says what the form should be,
    so nothing here is invented.
    """
    forms = {}
    for word, blob in db.execute(
            "SELECT word, enrichment_json FROM words "
            "WHERE word_type = 'substantiv' AND enrichment_json IS NOT NULL"):
        inflections = json.loads(blob).get('inflections') or []
        oblique = {}
        for inflection in inflections:
            tags = str(inflection.get('tags') or '')
            text = str(inflection.get('form_text') or '')
            if 'singular' not in tags or not text:
                continue
            for case in ('accusative', 'dative'):
                if case in tags and case not in oblique:
                    oblique[case] = text.split()[-1]
        accusative = oblique.get('accusative')
        if not accusative:
            continue
        if accusative.lower() in (f'{word.lower()}n', f'{word.lower()}en'):
            forms[word] = accusative
    return forms


def fix_weak_nouns(sentence, forms, patterns):
    """The sentence with weak nouns given the ending their case requires."""
    fixed = sentence
    for word, pattern in patterns.items():
        fixed = pattern.sub(lambda m: f'{m.group(1)} {forms[word]}', fixed)
    return fixed


def weak_noun_patterns(forms):
    articles = '|'.join(ACCUSATIVE_ARTICLES + DATIVE_ARTICLES)
    return {
        word: re.compile(rf'\b({articles})\s+{re.escape(word)}\b')
        for word in forms
    }


def load_rules():
    # Comments first: an apostrophe in one ("The German pack's grade glosses")
    # breaks the quote pairing, and the parser then reads the ", " between two
    # literals as a literal of its own — which matches every gloss there is.
    source = re.sub(r'//[^\n]*', '', QUALITY_DART.read_text())
    return {
        'name_openings': dart_list(source, 'kNameGlossOpenings'),
        'name_phrases': dart_list(source, 'kNameGlossPhrases'),
        'form_markers': dart_list(source, 'kGrammaticalFormMarkers'),
        'abbreviation_markers': dart_list(source, 'kAbbreviationMarkers'),
        'misspelling_markers': dart_list(source, '_invalidSpellingMarkers'),
        'dangling': dart_list(source, '_danglingWords'),
    }


# Mirrors _geographyGloss in vocabulary_quality.dart. Keep the two together.
GEOGRAPHY_GLOSS = re.compile(
    r'^(hauptstadt|stadt|fluss|insel|gebirge|ozean|provinz|bundesland'
    r'|bundesstaat|kontinent|staat|region|gemeinde|dorf)\s*,?\s*'
    r'(in|im|der|des|von|vom|zwischen|an|auf|nahe|bei|südlich|nördlich'
    r'|östlich|westlich|mit)\b')


def describes_a_name(definition, rules):
    lower = definition.lower()
    # Mirrors the one rule in describesAName that is code rather than a list:
    # a capital and a city in one gloss is a place however it is phrased.
    if 'capital' in lower and 'city' in lower:
        return True
    # And the German pack's "kind of place, then where it is": "Stadt im
    # US-Bundesstaat Pennsylvania", "Staat in Ostasien". The locating word is
    # what keeps "Ausland: Land oder Länder außerhalb ..." out of it.
    if GEOGRAPHY_GLOSS.match(lower):
        return True
    return (any(lower.startswith(opening) for opening in rules['name_openings'])
            or any(phrase in lower for phrase in rules['name_phrases']))


def ends_mid_sentence(definition, rules):
    trimmed = definition.strip()
    if ',.' in trimmed or ' .' in trimmed:
        return True
    if trimmed.endswith(',') or trimmed.endswith(';'):
        return True
    if re.search(r'[.!?]$', trimmed):
        return False
    stripped = re.sub(r'[\s.,;:!?]+$', '', trimmed)
    if not stripped:
        return True
    return stripped.split()[-1].lower() in rules['dangling']


def gloss_verdict(definition, rules):
    """Why this gloss cannot carry a question, or None when it can."""
    trimmed = (definition or '').strip()
    lower = trimmed.lower()
    if len(trimmed) < 4:
        return 'gloss too short'
    if trimmed.endswith(':'):
        return 'gloss is a bare label'
    if ' ' not in trimmed:
        return 'gloss is a single word'
    if any(marker in lower for marker in rules['form_markers']):
        return 'gloss is a grammatical parse'
    if any(marker in lower for marker in rules['abbreviation_markers']):
        return 'gloss is an abbreviation'
    if describes_a_name(trimmed, rules):
        return 'gloss names something'
    if ends_mid_sentence(trimmed, rules):
        return 'gloss stops mid-sentence'
    return None


CURRICULUM_TAGS = re.compile(
    r'^source:(dolch|fry|de_curriculum_en|cambridge_yle_.*|uk_y.*)$')

MISSPELLING_TAGS = ('common_misspell', 'often_misspelled')

# The misspelling tags mark the *pair* — "accomodation" carries them and so
# does "add". What separates the mistake from the word is that the word is
# also on a vocabulary list.
# Any independent corroboration that this half of a misspelling pair is the
# word rather than the mistake — a frequency corpus counts here, since a
# corpus that lists "accomodation" also lists "accommodation" far more often
# and only the latter reaches a word list.
VOCABULARY_TAGS = re.compile(
    r'^(source:(fry|dolch|cefr_j|hermit|cambridge_yle_.*|uk_y.*|'
    r'de_curriculum_en)|fry_.*|dolch_.*)$')


def is_attested_vocabulary(metadata):
    """Whether something independent says this entry is a word, not a name.

    A CEFR level, and only that. Levels are assigned to meanings a learner is
    expected to acquire, and no one assigns one to a place: "of", "gay" and
    "mrs" are A1/B1 and lead with a surname or a territory gloss, while
    "london", "texas", "canada" and "ii" have no level at all — though all
    four sit on the Fry list, which is why word lists cannot answer this.
    """
    return bool(metadata.get('cefr_level'))


def names_something(definitions, metadata, rules):
    """Whether the entry is a name rather than a word.

    Either of the first two senses naming something is enough, unless the
    entry carries a CEFR level. See is_attested_vocabulary.
    """
    described = [definition for definition in definitions
                 if isinstance(definition, str) and definition.strip()]
    if not described:
        return False
    if is_attested_vocabulary(metadata):
        return False
    return any(describes_a_name(definition, rules)
               for definition in described[:2])


def row_verdict(word, definitions, metadata, rules):
    """(reasons, names_something) for one row."""
    reasons = []
    tags = [str(tag).lower() for tag in metadata.get('tags') or []]
    sources = [str(source).upper() for source in metadata.get('sources') or []]
    if (any(marker in tag for tag in tags for marker in MISSPELLING_TAGS)
            and not any(VOCABULARY_TAGS.match(tag) for tag in tags)):
        reasons.append('tagged a misspelling')
    if any('COMMON_MISSPELL' in source for source in sources):
        reasons.append('sourced as a misspelling')

    described = [
        definition for definition in definitions
        if isinstance(definition, str) and definition.strip()
    ]
    if not described:
        # Not a reason to call it non-vocabulary: a word with no gloss is
        # still a word to spell. It cannot carry a *question*, and the app
        # already knows that from WordFeature.usableDefinition.
        return reasons, False

    names = names_something(described, metadata, rules)
    return reasons, names


def leading_unusable(definitions, rules):
    """How many leading glosses to drop so a usable one leads."""
    dropped = 0
    for definition in definitions:
        if not isinstance(definition, str) or gloss_verdict(definition, rules):
            dropped += 1
        else:
            return dropped
    return 0  # nothing usable anywhere; leave the row alone


# Rows a model read and found plainly wrong, which nothing in the pack can be
# used to detect: the linkage is right, the examples are right, only the gloss
# is somebody else's. Each entry names the text it expects to replace, so this
# fails loudly rather than silently if the upstream data is ever corrected.
#
#   "know about" was glossed "like something because you have good feelings
#   about it" — the meaning of "be keen on" — while its own examples read
#   "I know about toys" and "You never know about that family."
PHRASAL_CORRECTIONS = {
    'know about': (
        'like something because you have good feelings about it',
        'be informed about something',
        'To be informed about (someone or something); to have knowledge of.',
    ),
}


def fix_phrasal_glosses(db, report):
    """Applies PHRASAL_CORRECTIONS. Returns the phrasals it changed."""
    try:
        rows = db.execute(
            'SELECT id, phrasal, meaning FROM phrasal_verbs').fetchall()
    except sqlite3.OperationalError:
        return []                      # the German pack has no phrasal verbs
    fixed = []
    for row in rows:
        correction = PHRASAL_CORRECTIONS.get(row['phrasal'])
        if correction is None:
            continue
        wrong, meaning, sense = correction
        if row['meaning'] != wrong:
            print(f'  phrasal "{row["phrasal"]}" no longer reads '
                  f'"{wrong}" — leaving it alone')
            continue
        fixed.append(row['phrasal'])
        if not report:
            db.execute(
                'UPDATE phrasal_verbs SET meaning = ?, senses_json = ? '
                'WHERE id = ?',
                (meaning, json.dumps([sense], ensure_ascii=False), row['id']))
    if fixed and not report:
        db.commit()
    return fixed


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('pack', type=pathlib.Path)
    parser.add_argument('--out', type=pathlib.Path)
    parser.add_argument('--report', action='store_true',
                        help='count and sample without writing anything')
    args = parser.parse_args()

    rules = load_rules()
    if args.report:
        out = args.pack
    else:
        out = args.out or args.pack.with_suffix('.repaired.db')
        shutil.copyfile(args.pack, out)

    db = sqlite3.connect(out)
    db.row_factory = sqlite3.Row
    phrasals_fixed = fix_phrasal_glosses(db, args.report)
    weak = weak_masculine_forms(db)
    weak_patterns = weak_noun_patterns(weak)
    reasons = Counter()
    samples = {}
    named = 0
    detagged = 0
    resenses = 0
    declined = 0
    rewritten = 0

    updates = []
    for row in db.execute(
            'SELECT id, word, word_type, enrichment_json, metadata_json '
            'FROM words'):
        enrichment = json.loads(row['enrichment_json'] or '{}')
        metadata = json.loads(row['metadata_json'] or '{}')
        definitions = enrichment.get('definitions') or []

        verdict, names = row_verdict(row['word'], definitions, metadata, rules)
        # Never for a name: its leading gloss is *why* it is a name, and
        # dropping it left "london" reading "A former administrative county of
        # England" and looking like ordinary vocabulary again.
        drop = 0 if (verdict or names) else leading_unusable(definitions, rules)
        # Nor when dropping would *reveal* one: "erin" is glossed "Ireland."
        # first — a single word, and unusable — and a town in Ontario next.
        if drop and names_something(definitions[drop:], metadata, rules):
            names, drop = True, 0
        # Only for what is demonstrably not the word: "my" and "they" really
        # are Dolch words, however parse-like their glosses are, and a true
        # fact is not worth removing to make a filter easier.
        untaught = bool(verdict) or names

        quality = {'vocabulary': False, 'reasons': verdict} if verdict else None
        tags = [tag for tag in metadata.get('tags') or []]
        kept_tags = tags
        if untaught:
            kept_tags = [tag for tag in tags
                         if not CURRICULUM_TAGS.match(str(tag))]
        word_type = 'proper_noun' if names else row['word_type']

        # The pack writes its own example sentences, and they decline weak
        # masculine nouns as if they were strong: "den Held", "einen
        # Gedanke". The table in the same row says what the form is.
        sentences_fixed = 0
        for example in enrichment.get('examples') or []:
            if not isinstance(example, dict):
                continue
            text = example.get('text')
            if not isinstance(text, str):
                continue
            fixed = fix_weak_nouns(text, weak, weak_patterns)
            if fixed != text:
                example['text'] = fixed
                sentences_fixed += 1
        grade_examples = metadata.get('grade_examples')
        if isinstance(grade_examples, dict):
            for grade, sentences in grade_examples.items():
                if not isinstance(sentences, list):
                    continue
                for index, text in enumerate(sentences):
                    if not isinstance(text, str):
                        continue
                    fixed = fix_weak_nouns(text, weak, weak_patterns)
                    if fixed != text:
                        sentences[index] = fixed
                        sentences_fixed += 1

        changed = (quality != metadata.get('quality')
                   or kept_tags != tags
                   or word_type != row['word_type']
                   or drop
                   or sentences_fixed)
        if not changed:
            continue

        for reason in verdict:
            reasons[reason] += 1
            samples.setdefault(reason, []).append(row['word'])
        if names and row['word_type'] != 'proper_noun':
            named += 1
            samples.setdefault('named', []).append(row['word'])
        if kept_tags != tags:
            detagged += 1
            samples.setdefault('detagged', []).append(row['word'])
        if drop:
            resenses += 1
            samples.setdefault('resensed', []).append(row['word'])
        if sentences_fixed:
            declined += sentences_fixed
            samples.setdefault('declined', []).append(row['word'])
        rewritten += 1

        if args.report:
            continue

        if quality is None:
            metadata.pop('quality', None)
        else:
            metadata['quality'] = quality
        if kept_tags != tags:
            metadata['tags'] = kept_tags
        if drop:
            enrichment['definitions'] = definitions[drop:]
        updates.append((
            json.dumps(enrichment, ensure_ascii=False)
            if (drop or sentences_fixed) else row['enrichment_json'],
            json.dumps(metadata, ensure_ascii=False),
            word_type,
            row['id'],
        ))

    if updates:
        db.executemany(
            'UPDATE words SET enrichment_json = ?, metadata_json = ?, '
            'word_type = ? WHERE id = ?', updates)
        db.commit()
        db.execute('VACUUM')

    total = db.execute('SELECT COUNT(*) FROM words').fetchone()[0]
    db.close()

    print(f'{args.pack.name}: {total} words, {rewritten} rows '
          f'{"would be " if args.report else ""}rewritten')
    for reason, count in reasons.most_common():
        shown = ', '.join(samples[reason][:6])
        print(f'  {count:6d}  {reason:28s} {shown}')
    for label, count in (('word_type -> proper_noun', named),
                         ('curriculum tags dropped', detagged),
                         ('leading glosses dropped', resenses),
                         ('weak nouns declined', declined)):
        if count:
            key = {'word_type -> proper_noun': 'named',
                   'curriculum tags dropped': 'detagged',
                   'leading glosses dropped': 'resensed',
                   'weak nouns declined': 'declined'}[label]
            print(f'  {count:6d}  {label:28s} {", ".join(samples[key][:6])}')
    if phrasals_fixed:
        print(f'  {len(phrasals_fixed):6d}  {"phrasal glosses corrected":28s} '
              f'{", ".join(phrasals_fixed)}')
    if not args.report:
        print(f'  wrote   {out}')


if __name__ == '__main__':
    main()
