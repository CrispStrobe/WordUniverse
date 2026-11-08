import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/features/games/services/sentence_completion_service.dart';
import 'package:WortUniversum/features/games/services/adaptive_word_selection.dart';

import 'word_fixture.dart';

const _meanings = {
  'Tisch': 'Ein Möbelstück mit einer Platte und Beinen.',
  'Stuhl': 'Ein Sitzmöbel für eine Person.',
  'Lampe': 'Ein Gerät, das Licht erzeugt.',
  'Teppich': 'Ein weicher Belag für den Fußboden.',
  'sonnig': 'Von der Sonne beschienen.',
  'wichtig': 'Von großer Bedeutung.',
  'still': 'Ohne Lärm oder Bewegung.',
  'dreckig': 'Mit Schmutz bedeckt.',
  'Haus': 'Ein Gebäude zum Wohnen.',
  'Buch': 'Zusammengebundene Seiten zum Lesen.',
  'Baum': 'Eine große Pflanze mit einem Stamm.',
  'Hund': 'Ein Haustier, das bellt.',
  'laufen': 'Sich auf den Beinen fortbewegen.',
  'fahren': 'Sich mit einem Fahrzeug fortbewegen.',
  'springen': 'Sich vom Boden in die Luft abstoßen.',
};

GermanWord _word(
  String word, {
  Map<String, List<String>>? examples,
  int grade = 4,
  GermanWordType type = GermanWordType.substantiv,
  List<String>? definitions,
  List<String> synonyms = const [],
  List<Map<String, dynamic>> inflections = const [],
  String? article,
}) =>
    testWord(
      word,
      type: type,
      grade: grade,
      article: article,
      enrichment: testEnrichment(
          gradeExamples: examples,
          definitions: definitions ?? [_meanings[word] ?? 'Ein anderes Ding.'],
          synonyms: synonyms,
          inflections: inflections),
    );

List<GermanWord> _pool() => [
      _word('Tisch'),
      _word('Stuhl'),
      _word('Lampe'),
      _word('Teppich'),
    ];

Map<String, dynamic> _form(String text, String tags) =>
    {'form_text': text, 'tags': tags};

SentenceChallenge? _build(GermanWord word,
        {List<GermanWord>? pool, bool isGerman = true}) =>
    buildSentenceChallenge(
        word: word,
        gradeIndex: 4,
        pool: pool ?? _pool(),
        isGerman: isGerman,
        rng: Random(1));

void main() {
  group('blankWord', () {
    test('cuts an exact token and preserves Unicode boundaries', () {
      expect(blankWord('Der Hund bellt.', 'Hund'), ('Der ', ' bellt.'));
      expect(blankWord('Öl schwimmt oben.', 'Öl'), ('', ' schwimmt oben.'));
      expect(blankWord('Ich höre Übungen.', 'Übungen'), ('Ich höre ', '.'));
      expect(blankWord('Hund bellt.', 'hund'), ('', ' bellt.'));
      expect(blankWord('Ölflaschen sind leer.', 'Öl'), isNull);
      expect(blankWord('Die Haustür ist zu.', 'Tür'), isNull);
    });

    test('an inflected form needs explicit evidence', () {
      expect(blankWord('Die Hunde bellen.', 'Hund'), isNull);
      expect(blankWord('Die Hunde bellen.', 'Hund', forms: ['Hunde']),
          ('Die ', ' bellen.'));
    });

    test('does not infer an inflection from a short shared prefix', () {
      expect(blankWord('Hundert Menschen kamen.', 'Hund'), isNull);
      expect(blankWord('Hunderte kamen.', 'Hund'), isNull);
      expect(blankWord('Die Armee zieht weiter.', 'arm'), isNull);
      expect(blankWord('Das ist eine Haus-Tür.', 'Haus'), isNull);
    });

    test('returns nothing for an empty or absent word', () {
      expect(blankWord('Die Katze schläft.', 'Hund'), isNull);
      expect(blankWord('Die Katze schläft.', ''), isNull);
    });
  });

  group('hasGradeExamples', () {
    test('uses the requested grade, or an existing example band', () {
      final word = _word('Tisch', examples: {
        '4': ['Der Tisch ist rund.']
      });
      expect(hasGradeExamples(word, 4), isTrue);
      expect(hasGradeExamples(word, 6), isTrue);
      expect(hasGradeExamples(_word('Tisch'), 4), isFalse);
    });
  });

  group('buildSentenceChallenge', () {
    test('the accepted answer restores the source and carries a meaning clue',
        () {
      const source = 'Der Tisch steht im Zimmer.';
      final word = _word('Tisch', examples: {
        '4': [source]
      });
      final challenge = _build(word)!;
      expect(challenge.before, 'Der ');
      expect(challenge.after, ' steht im Zimmer.');
      expect(challenge.correctOption, 'Tisch');
      expect(challenge.options[challenge.correctIndex], 'Tisch');
      expect('${challenge.before}${challenge.correctOption}${challenge.after}',
          source);
      expect(challenge.source, source);
      expect(challenge.meaningCue, _meanings['Tisch']);
      expect(challenge.skillType, LanguageSkillType.vocabulary);
    });

    test('the source article remains outside the accepted noun', () {
      final word = _word('Tisch', article: 'der', examples: {
        '4': ['Ich sehe den Tisch.']
      });
      final challenge = _build(word)!;
      expect(challenge.before, 'Ich sehe den ');
      expect(challenge.correctOption, 'Tisch');
      expect(challenge.options, isNot(contains('der Tisch')));
    });

    test('rejects the pack\'s malformed attributive adjective, without repair',
        () {
      final word = _word('sonnig', type: GermanWordType.adjektiv, examples: {
        '4': ['Ein sonnig Tag am Meer ist immer schön.']
      }, inflections: [
        _form('sonniger', 'masculine, nominative, singular, positive, strong')
      ]);
      expect(
          _build(word, pool: [
            word,
            _word('wichtig', type: GermanWordType.adjektiv),
          ]),
          isNull);
    });

    test('accepts the exact inflected adjective and uses only attested options',
        () {
      const tags = 'masculine, nominative, singular, positive, strong';
      const source = 'Ein sonniger Tag am Meer ist immer schön.';
      final word = _word('sonnig', type: GermanWordType.adjektiv, examples: {
        '4': [source]
      }, inflections: [
        _form('sonniger', tags)
      ]);
      final challenge = _build(word, pool: [
        word,
        _word('wichtig',
            type: GermanWordType.adjektiv,
            inflections: [_form('wichtiger', tags)]),
        _word('still',
            type: GermanWordType.adjektiv,
            inflections: [_form('stiller', tags)]),
        _word('dreckig',
            type: GermanWordType.adjektiv,
            inflections: [_form('dreckiger', tags)]),
      ])!;
      expect(challenge.correctOption, 'sonniger');
      expect(challenge.options,
          unorderedEquals(['sonniger', 'wichtiger', 'stiller', 'dreckiger']));
      expect('${challenge.before}${challenge.correctOption}${challenge.after}',
          source);
    });

    test('keeps a valid predicative adjective instead of the malformed example',
        () {
      final word = _word('sonnig', type: GermanWordType.adjektiv, examples: {
        '4': ['Ein sonnig Tag ist schön.', 'Das Wetter ist sonnig.']
      });
      final challenge = _build(word, pool: [
        word,
        _word('still', type: GermanWordType.adjektiv),
      ])!;
      expect(challenge.source, 'Das Wetter ist sonnig.');
      expect(challenge.correctOption, 'sonnig');
    });

    test('preserves an attested umlaut plural and the existing article', () {
      const source = 'Die Häuser sind alt.';
      final word = _word('Haus', examples: {
        '4': [source]
      }, inflections: [
        _form('die Häuser', 'nominative, plural')
      ]);
      final challenge = _build(word, pool: [
        word,
        _word('Buch', inflections: [_form('die Bücher', 'nominative, plural')]),
        _word('Baum', inflections: [_form('die Bäume', 'nominative, plural')]),
      ])!;
      expect(challenge.before, 'Die ');
      expect(challenge.correctOption, 'Häuser');
      expect(challenge.options, unorderedEquals(['Häuser', 'Bücher', 'Bäume']));
      expect('${challenge.before}${challenge.correctOption}${challenge.after}',
          source);
    });

    test('can use an explicitly attested irregular verb', () {
      const tags = 'present, third-person, singular, indicative, active';
      final word = _word('laufen', type: GermanWordType.verb, examples: {
        '4': ['Sie läuft zur Schule.']
      }, inflections: [
        _form('läuft', tags)
      ]);
      final challenge = _build(word, pool: [
        word,
        _word('fahren',
            type: GermanWordType.verb, inflections: [_form('fährt', tags)]),
      ])!;
      expect(challenge.correctOption, 'läuft');
      expect(challenge.options, unorderedEquals(['läuft', 'fährt']));
    });

    test('does not guess person agreement from vague present-tense tags', () {
      final word = _word('laufen', type: GermanWordType.verb, examples: {
        '4': ['Sie läuft zur Schule.']
      }, inflections: [
        _form('läuft', 'present')
      ]);
      expect(
          _build(word, pool: [
            word,
            _word('fahren', type: GermanWordType.verb, inflections: [
              _form('fahre', 'present'),
              _form('fährst', 'present'),
              _form('fährt', 'present'),
            ]),
          ]),
          isNull);
    });

    test('does not treat an auxiliary as a form of the target verb', () {
      final word = _word('laufen', type: GermanWordType.verb, examples: {
        '4': ['Wir haben Zeit.']
      }, inflections: [
        _form('haben', 'perfect, auxiliary')
      ]);
      expect(
          _build(word, pool: [
            word,
            _word('fahren', type: GermanWordType.verb),
          ]),
          isNull);
    });

    test('preserves initial capitalization in the accepted source span', () {
      final word = _word('tradition', definitions: [
        'A custom passed between generations.'
      ], examples: {
        '4': ['Tradition connects people.']
      });
      final challenge = _build(word, isGerman: false, pool: [
        word,
        _word('destination', definitions: ['The final place of a journey.']),
        _word('cheek', definitions: ['The side of a face.']),
      ])!;
      expect(challenge.correctOption, 'Tradition');
      expect(challenge.options, containsAll(['Destination', 'Cheek']));
    });

    test('a meaning cue resolves a sentence with several plausible fillers',
        () {
      final word = _word('tradition', definitions: [
        'A custom passed between generations.'
      ], examples: {
        '4': ['The town has a special tradition.']
      });
      final challenge = _build(word, isGerman: false, pool: [
        word,
        _word('destination', definitions: ['The final place of a journey.']),
        _word('cheek', definitions: ['The side of a face.']),
      ])!;
      expect(challenge.options, contains('destination'));
      expect(challenge.meaningCue, 'A custom passed between generations.');
      expect(challenge.skillType, isNot(LanguageSkillType.sentenceStructure));
    });

    test('skips a prompt without a legitimate readable meaning cue', () {
      final word = _word('Tisch', definitions: [], examples: {
        '4': ['Der Tisch steht im Zimmer.']
      });
      expect(_build(word), isNull);
    });

    test('does not reveal the target or switch senses to obtain a clue', () {
      final word = _word('Tisch', definitions: [
        'Ein Tisch ist ein Möbelstück.',
        'Eine Gruppe von Personen beim Essen.',
      ], examples: {
        '4': ['Der Tisch steht im Zimmer.']
      });
      expect(_build(word), isNull);
    });

    test('excludes synonyms in either direction and identical meanings', () {
      final word = _word('Tisch', synonyms: [
        'Schreibtisch'
      ], examples: {
        '4': ['Der Tisch steht im Zimmer.']
      });
      final challenge = _build(word, pool: [
        word,
        _word('Schreibtisch', definitions: ['Ein Möbel zum Schreiben.']),
        _word('Pult',
            synonyms: ['Tisch'], definitions: ['Ein erhöhtes Möbel.']),
        _word('Möbel', definitions: [_meanings['Tisch']!]),
        _word('Stuhl'),
      ])!;
      expect(challenge.options, unorderedEquals(['Tisch', 'Stuhl']));
    });

    test('rejects a noun entry whose own analysis says determiner', () {
      final word = testWord('sufficient',
          type: GermanWordType.substantiv,
          enrichment: testEnrichment(primaryPos: 'determiner', definitions: [
            'An adequate quantity of; enough.'
          ], gradeExamples: {
            '4': ['The teacher thinks we have sufficient time.']
          }));
      expect(_build(word, isGerman: false), isNull);
    });

    test('does not credit an adjective entry for a finite-verb use', () {
      final word =
          _word('accomplished', type: GermanWordType.adjektiv, definitions: [
        'Completed; effected; established.'
      ], examples: {
        '4': ['They accomplished their goal by working together.']
      });
      expect(
          _build(word, isGerman: false, pool: [
            word,
            _word('wichtig', type: GermanWordType.adjektiv),
          ]),
          isNull);
    });

    test('keeps a valid adjective question with a pronoun before the gap', () {
      final word = _word('happy', type: GermanWordType.adjektiv, definitions: [
        'Feeling pleasure or joy.'
      ], examples: {
        '4': ['Is she happy?']
      });
      final challenge = _build(word, isGerman: false, pool: [
        word,
        _word('sad',
            type: GermanWordType.adjektiv,
            definitions: ['Feeling sorrow or unhappiness.']),
      ])!;
      expect(challenge.correctOption, 'happy');
    });

    test('skips repeated target forms beside the gap', () {
      final word = _word('Hund', examples: {
        '4': ['Der Hund sieht viele Hunde.']
      }, inflections: [
        _form('die Hunde', 'nominative, plural')
      ]);
      expect(_build(word), isNull);
    });

    test('uses another source when one repeats the answer', () {
      final word = _word('Tisch', examples: {
        '4': ['Der Tisch ist ein Tisch.', 'Der Tisch steht im Zimmer.']
      });
      final challenge = _build(word)!;
      expect('${challenge.before}${challenge.after}', isNot(contains('Tisch')));
    });

    test('requires both a matching source and a usable distractor', () {
      final absent = _word('Tisch', examples: {
        '4': ['Die Lampe leuchtet hell.']
      });
      expect(_build(absent), isNull);
      final isolated = _word('Tisch', examples: {
        '4': ['Der Tisch steht im Zimmer.']
      });
      expect(_build(isolated, pool: [isolated]), isNull);
    });

    test('keeps fewer valid options instead of adding unrelated word classes',
        () {
      final word = _word('Tisch', examples: {
        '4': ['Der Tisch steht im Zimmer.']
      });
      final challenge = _build(word, pool: [
        word,
        _word('Stuhl'),
        _word('laufen', type: GermanWordType.verb),
        _word('springen', type: GermanWordType.verb),
      ])!;
      expect(challenge.options, unorderedEquals(['Tisch', 'Stuhl']));
    });
  });

  test(
      'buildSentenceChallenges skips names, missing meanings, and limits rounds',
      () {
    final pool = [
      _word('Tisch', examples: {
        '4': ['Der Tisch steht im Zimmer.']
      }),
      _word('columbia', definitions: [
        'A city in South Carolina, United States.'
      ], examples: {
        '4': ['Wir fahren nach columbia.']
      }),
      _word('iot', definitions: [], examples: {
        '4': ['Das iot hat viele Anwendungen.']
      }),
      _word('Stuhl', examples: {
        '4': ['Der Stuhl ist bequem und alt.']
      }),
      ..._pool(),
    ];
    final one = buildSentenceChallenges(
        pool: pool, gradeIndex: 4, maxChallenges: 1, rng: Random(1));
    expect(one.single.word.word, 'Tisch');
    final all = buildSentenceChallenges(
        pool: pool, gradeIndex: 4, maxChallenges: 10, rng: Random(1));
    expect(all.map((c) => c.word.word), ['Tisch', 'Stuhl']);
  });

  test('baseWordFromSriId preserves the shared legacy-id parsing contract', () {
    expect(baseWordFromSriId('SPELL_Tisch'), 'Tisch');
    expect(baseWordFromSriId('TYPE_laufen'), 'laufen');
    expect(baseWordFromSriId('Tisch'), 'Tisch');
    expect(baseWordFromSriId(''), isNull);
  });
}
