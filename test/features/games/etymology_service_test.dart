// test/features/games/etymology_service_test.dart
//
// Unit tests for the etymologyNoteFor() helper in etymology_banner.dart.
// Verifies: grade gate (< 5 → hidden), empty-notes gate, first-note selection,
// and realistic German Wiktionary note examples.

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/features/games/widgets/etymology_banner.dart';
import 'package:WortUniversum/core/models/vocabulary_models.dart';
import 'package:WortUniversum/core/models/skill_category.dart';

// ─── Helper ──────────────────────────────────────────────────────────────────

GermanWord _word(
  String word, {
  int grade = 1,
  List<String> entryNotes = const [],
}) =>
    GermanWord(
      id: 'test_$word',
      word: word,
      wordType: GermanWordType.substantiv,
      gradeLevel: grade,
      lemma: word,
      sources: const [],
      isGrundwortschatzBW: false,
      nurImPlural: false,
      graphematicVariants: const [],
      categories: const [],
      exampleSentences: const [],
      spellingDifficulty: SpellingDifficulty.easy,
      isProperNoun: false,
      entryNotes: entryNotes,
      examples: const [],
      hyphenation: const [],
      wiktionaryInflections: const [],
      translations: const [],
      derivedTerms: const [],
      relatedTerms: const [],
      expressions: const [],
      proverbs: const [],
      hypernyms: const [],
      hyponyms: const [],
      holonyms: const [],
      meronyms: const [],
      coordinateTerms: const [],
    );

void main() {
  // ─── Grade gate ────────────────────────────────────────────────────────────

  group('etymologyNoteFor grade gate', () {
    const note = 'Aus dem Lateinischen stammend.';

    test('grade 1 with notes → null (hidden)', () {
      expect(etymologyNoteFor(_word('Haus', grade: 1, entryNotes: [note])), isNull);
    });

    test('grade 2 with notes → null (hidden)', () {
      expect(etymologyNoteFor(_word('Baum', grade: 2, entryNotes: [note])), isNull);
    });

    test('grade 3 with notes → null (hidden)', () {
      expect(etymologyNoteFor(_word('Sturm', grade: 3, entryNotes: [note])), isNull);
    });

    test('grade 4 with notes → null (boundary: not yet grade 5)', () {
      expect(etymologyNoteFor(_word('Eifer', grade: 4, entryNotes: [note])), isNull);
    });

    test('grade 5 with notes → returns note', () {
      expect(etymologyNoteFor(_word('Axiom', grade: 5, entryNotes: [note])), note);
    });

    test('grade 6 with notes → returns note', () {
      expect(etymologyNoteFor(_word('Palindrom', grade: 6, entryNotes: [note])), note);
    });
  });

  // ─── Empty-notes gate ──────────────────────────────────────────────────────

  group('etymologyNoteFor empty-notes gate', () {
    test('grade 5, empty entryNotes → null', () {
      expect(etymologyNoteFor(_word('Algebra', grade: 5, entryNotes: [])), isNull);
    });

    test('grade 6, empty entryNotes → null', () {
      expect(etymologyNoteFor(_word('Chronik', grade: 6, entryNotes: [])), isNull);
    });
  });

  // ─── First-note selection ─────────────────────────────────────────────────

  group('etymologyNoteFor first-note selection', () {
    test('single note → returns it verbatim', () {
      const n = 'Kommt vom griechischen "axios" (würdig).';
      expect(etymologyNoteFor(_word('Axiom', grade: 5, entryNotes: [n])), n);
    });

    test('multiple notes → returns only the first', () {
      const n1 = 'Erste Notiz.';
      const n2 = 'Zweite Notiz.';
      const n3 = 'Dritte Notiz.';
      expect(
        etymologyNoteFor(_word('Chronik', grade: 6, entryNotes: [n1, n2, n3])),
        n1,
      );
    });

    test('note with German etymology phrase is returned as-is', () {
      const note = 'Das Wort stammt aus dem Altgriechischen χρόνος (chronos = Zeit).';
      expect(etymologyNoteFor(_word('Chronologie', grade: 5, entryNotes: [note])), note);
    });

    test('note with usage caveat is returned as-is', () {
      const note = 'In der Umgangssprache oft falsch als Synonym für "Allegorie" verwendet.';
      expect(etymologyNoteFor(_word('Metapher', grade: 6, entryNotes: [note])), note);
    });
  });

  // ─── Realistic examples ───────────────────────────────────────────────────

  group('etymologyNoteFor realistic Wiktionary examples', () {
    test('common grade-5 math term with Latin root', () {
      const note = 'Abgeleitet von lateinisch "radius" (Speiche, Strahl).';
      final word = _word('Radius', grade: 5, entryNotes: [note]);
      expect(etymologyNoteFor(word), note);
    });

    test('grade-6 philosophical term with Greek origin', () {
      const note = 'Von griechisch "philosophia" (Liebe zur Weisheit).';
      final word = _word('Philosophie', grade: 6, entryNotes: [note]);
      expect(etymologyNoteFor(word), note);
    });

    test('grade 4 → always null even with rich note', () {
      const note = 'Sehr interessante Etymologie aus dem Sanskrit.';
      final word = _word('Karma', grade: 4, entryNotes: [note]);
      expect(etymologyNoteFor(word), isNull);
    });
  });
}
