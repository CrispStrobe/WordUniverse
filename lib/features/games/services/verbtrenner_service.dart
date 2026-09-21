// lib/features/games/services/verbtrenner_service.dart
//
// Separable-verb pair construction, extracted from the screen so it can be
// generated and reviewed without running the game. See docs/content-audit.md.

import 'dart:math';

import '../../../core/models/vocabulary_models.dart';
import '../../../core/models/vocabulary_quality.dart';
import '../models/verb_pair.dart';

String? findRealExample({
  required List<ApiExample> apiExamples,
  required List<String> tataoebaExamples,
  required String formText,
}) {
  final matches = _matcherFor(formText);
  for (final ex in apiExamples) {
    final text = ex.text;
    if (text != null &&
        text.isNotEmpty &&
        matches(text) &&
        sentenceSuitsAChild(text)) {
      return text;
    }
  }
  for (final text in tataoebaExamples) {
    if (text.isNotEmpty && matches(text) && sentenceSuitsAChild(text)) {
      return text;
    }
  }
  // No fallback to an unrelated sentence. The tile shows the context beneath
  // the form, and falling back attached "Komm doch mal vor zu mir!" to
  // "vorzukommen" — a sentence that does not contain the form the learner is
  // being asked to judge.
  return null;
}

/// How a sentence has to contain [formText] to be its context.
///
/// A separated form is *never* contiguous in German: "stehe auf" appears as
/// "Ich stehe früh auf." Requiring the literal string found a sentence for
/// almost no separated form, so the game asked one side of its own contrast —
/// 29 of 33 generated tiles were ZUSAMMEN, and answering "together" every
/// time scored full marks. The parts are matched in order instead, each on a
/// word boundary.
bool Function(String) _matcherFor(String formText) {
  final parts = formText.split(' ').where((p) => p.isNotEmpty).toList();
  if (parts.length != 2) return (text) => text.contains(formText);
  final pattern = RegExp(
    r'\b' +
        RegExp.escape(parts[0]) +
        r'\b.*\b' +
        RegExp.escape(parts[1]) +
        r'\b',
    caseSensitive: false,
  );
  return pattern.hasMatch;
}

/// Whether an inflected form can be asked as a separable-verb tile.
///
/// Wiktionary's inflection list mixes finite forms with participles and
/// zu-infinitives. "eingezogen zu sein" and "vor…zukommen" are not the
/// separated/joined contrast this game teaches, and reading them as one
/// produced tiles no rule explains.
bool isAskableSeparableForm(String formText) {
  final lower = formText.toLowerCase().trim();
  if (lower.isEmpty) return false;
  if (lower.contains(' zu ') || lower.startsWith('zu ')) return false;
  // Infixed zu-infinitives: einzurichten, vorzutragen, aufzustehen.
  if (RegExp(r'^[a-zäöüß]+zu[a-zäöüß]+en$').hasMatch(lower)) return false;
  // Past participles: aufgefordert, angekommen. The game contrasts a finite
  // form split from its prefix with the joined infinitive; a participle is
  // neither, and "auf … gefordert" matches no rule the game explains.
  if (RegExp(r'^[a-zäöüß]+ge[a-zäöüß]+(t|en)$').hasMatch(lower)) return false;
  return true;
}

bool isVerbSeparable(GermanWord word) {
  final inflections = word.apiEnrichment?.inflections ?? [];

  for (final form in inflections) {
    final formText = form['form_text'] as String?;
    if (formText == null) continue;

    // Check for separated forms (e.g., "stehe auf")
    if (formText.contains(' ')) {
      final parts = formText.split(' ');
      if (parts.length == 2 && _isSeparablePrefix(parts[1])) {
        return true;
      }
    }
  }

  return false;
}

List<VerbPair> pairsFromVerb(GermanWord word) {
  final pairs = <VerbPair>[];
  final inflections = word.apiEnrichment?.inflections ?? [];
  final apiExamples = word.apiEnrichment?.examples ?? [];
  final tataoebaExamples = word.exampleSentences;

  final String infinitive = word.word;
  String prefix = '';

  for (final form in inflections) {
    final formText = form['form_text'] as String?;
    if (formText != null && formText.contains(' ')) {
      final parts = formText.split(' ');
      if (parts.length == 2 && _isSeparablePrefix(parts[1])) {
        prefix = parts[1];
        break;
      }
    }
  }

  if (prefix.isEmpty) return pairs;

  for (final form in inflections) {
    final formText = form['form_text'] as String?;
    if (formText == null || !isAskableSeparableForm(formText)) continue;
    final tags = form['tags'] as String?;
    if (tags == null) continue;

    // RULE 1: Present/Past tense (conjugated) → GETRENNT
    if ((tags.contains('present') || tags.contains('past')) &&
        !tags.contains('participle') &&
        !tags.contains('infinitive') &&
        formText.contains(' ')) {
      final parts = formText.split(' ');
      if (parts.length == 2) {
        final context = findRealExample(
          apiExamples: apiExamples,
          tataoebaExamples: tataoebaExamples,
          formText: formText,
        );
        if (context == null) continue;
        pairs.add(VerbPair(
          part1: parts[0],
          part2: parts[1],
          shouldBeSeparated: true,
          context: context,
          explanation: 'Konjugierte Form im Hauptsatz → getrennt',
          difficulty: 2,
          wordId: word.id,
          formText: formText,
        ));
      }
    }

    // RULE 2: Extended infinitive with "zu"
    if (tags.contains('extended') && tags.contains('infinitive')) {
      final context = findRealExample(
        apiExamples: apiExamples,
        tataoebaExamples: tataoebaExamples,
        formText: formText,
      );
      if (context == null) continue;
      final hasSpaces = formText.contains(' ');
      final String part1, part2;
      if (hasSpaces) {
        final lastSpace = formText.lastIndexOf(' ');
        part1 = formText.substring(0, lastSpace);
        part2 = formText.substring(lastSpace + 1);
      } else {
        part1 = prefix;
        part2 = formText.substring(prefix.length);
      }
      pairs.add(VerbPair(
        part1: part1,
        part2: part2,
        shouldBeSeparated: hasSpaces,
        context: context,
        explanation: hasSpaces
            ? 'Infinitiv mit Hilfsverb (zu haben/sein) → getrennt'
            : 'zu-Infinitiv (ein Wort) → zusammen',
        difficulty: 3,
        wordId: word.id,
        formText: formText,
      ));
    }

    // RULE 3: Plain infinitive → ZUSAMMEN
    if (tags.contains('infinitive') &&
        !tags.contains('extended') &&
        formText == infinitive) {
      final context = findRealExample(
        apiExamples: apiExamples,
        tataoebaExamples: tataoebaExamples,
        formText: formText,
      );
      if (context == null) continue;
      pairs.add(VerbPair(
        part1: prefix,
        part2: formText.substring(prefix.length),
        shouldBeSeparated: false,
        context: context,
        explanation: 'Infinitiv nach Modalverb → zusammen',
        difficulty: 1,
        wordId: word.id,
        formText: formText,
      ));
    }

    // RULE 4: Past participle → ZUSAMMEN
    if (tags.contains('participle') && tags.contains('perfect')) {
      final context = findRealExample(
        apiExamples: apiExamples,
        tataoebaExamples: tataoebaExamples,
        formText: formText,
      );
      if (context == null) continue;
      pairs.add(VerbPair(
        part1: prefix,
        part2: formText.substring(prefix.length),
        shouldBeSeparated: false,
        context: context,
        explanation: 'Partizip Perfekt → zusammen',
        difficulty: 2,
        wordId: word.id,
        formText: formText,
      ));
    }
  }

  return pairs;
}

const _separablePrefixes = [
  'ab',
  'an',
  'auf',
  'aus',
  'bei',
  'ein',
  'empor',
  'fest',
  'fort',
  'her',
  'hin',
  'los',
  'mit',
  'nach',
  'nieder',
  'vor',
  'weg',
  'weiter',
  'zu',
  'zurecht',
  'zurück',
  'zusammen'
];

bool _isSeparablePrefix(String prefix) {
  return _separablePrefixes.contains(prefix.toLowerCase());
}

/// Whether an infinitive begins with one of the separable prefixes, which is
/// what makes "wir bleiben auf" rather than "wir aufbleiben". Shared with
/// Großstadt, which frames verbs the same way.
bool hasSeparablePrefix(String infinitive) {
  final lower = infinitive.toLowerCase();
  return _separablePrefixes.any(
      (prefix) => lower.startsWith(prefix) && lower.length > prefix.length + 2);
}

/// Builds up to [maxPairs] from [verbs], which are expected hydrated.
List<VerbPair> buildVerbPairs({
  required List<GermanWord> verbs,
  int maxPairs = 20,
  Random? rng,
}) {
  final random = rng ?? Random();
  final pairs = <VerbPair>[];
  for (final verb in verbs) {
    if (!isVerbSeparable(verb)) continue;
    pairs.addAll(pairsFromVerb(verb));
  }
  pairs.shuffle(random);
  return pairs.length > maxPairs ? pairs.sublist(0, maxPairs) : pairs;
}
