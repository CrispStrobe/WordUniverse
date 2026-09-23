// lib/features/games/services/grossschreib_service.dart
//
// Capitalisation challenge construction for Großschreib-Rakete, extracted from
// the screen so it can be generated and reviewed without running the game.
// See docs/content-audit.md.

import '../../../core/models/vocabulary_models.dart';

enum WordCase { allCaps, capitalized, lowercase }

enum CapitalizationRule { noun, verbOrAdjective, sentenceStart }

class SentenceChallenge {
  final String beforeWord; // Text before the target word
  final String targetWord; // The word to test (original correct form)
  final String afterWord; // Text after the target word
  final WordCase correctCase; // What the player should select
  final CapitalizationRule rule;
  final String explanation;
  final String wordId;
  final bool isAtSentenceStart;

  SentenceChallenge({
    required this.beforeWord,
    required this.targetWord,
    required this.afterWord,
    required this.correctCase,
    required this.rule,
    required this.explanation,
    required this.wordId,
    required this.isAtSentenceStart,
  });

  String get fullSentence => '$beforeWord$targetWord$afterWord';
}

SentenceChallenge? challengeFromWord(
  GermanWord word, {
  required WordCase correctCase,
  required CapitalizationRule rule,
  required String explanation,
  bool forceMiddlePosition = false,
  bool forceSentenceStart = false,
}) {
  if (word.examples.isEmpty) {
    return null;
  }

  // Try each example
  for (int i = 0; i < word.examples.length; i++) {
    final example = word.examples[i];

    if (example.text == null || example.text!.isEmpty) {
      continue;
    }

    final sentence = example.text!;

    // Check sentence length
    if (sentence.length > 120) {
      continue;
    }

    // Find the word in the sentence at a word boundary, and extend the
    // match through any inflectional ending (so a lemma like
    // "amerikanisch" picks up "amerikanische" / "amerikanischen" as a
    // single token, and "Peter" doesn't get sliced into "Pete"+"r").
    final candidates = <String>{
      word.word,
      if (word.lemma.isNotEmpty) word.lemma,
    }..removeWhere((c) => c.isEmpty);

    int wordIndex = -1;
    int wordEnd = -1;
    for (final candidate in candidates) {
      final escaped = RegExp.escape(candidate);
      // \b on the front; on the tail, eat any German letters that
      // follow without a boundary (the inflection).
      final pattern = RegExp(
        r'\b' + escaped + r'[A-Za-zÄÖÜäöüß]*',
        caseSensitive: false,
      );
      final m = pattern.firstMatch(sentence);
      if (m != null) {
        wordIndex = m.start;
        wordEnd = m.end;
        break;
      }
    }

    if (wordIndex == -1) {
      continue;
    }

    // Determine if word is at sentence start: the trimmed text before the
    // target must be empty or end with a sentence terminator (. ! ?),
    // ignoring trailing quotes and spaces.
    final beforeTarget = sentence.substring(0, wordIndex);
    // „ is how German opens a quotation, so leaving it out of this set made
    // the first word of a quoted sentence look like a word in the middle.
    final trimmedBefore =
        beforeTarget.replaceAll(RegExp('[\\s"„“”«»‹›‚‘’\']+\$'), '');
    final isAtStart =
        trimmedBefore.isEmpty || RegExp(r'[.!?]$').hasMatch(trimmedBefore);

    // Check position requirements
    if (forceMiddlePosition && isAtStart) {
      continue;
    }

    if (forceSentenceStart && !isAtStart) {
      continue;
    }

    // Extract the full inflected form actually present in the sentence.
    final actualWordInSentence = sentence.substring(wordIndex, wordEnd);

    // Extract surrounding parts.
    final before = sentence.substring(0, wordIndex);
    final after = wordEnd < sentence.length ? sentence.substring(wordEnd) : '';

    // The sentence is real German from the pack, and it is in front of the
    // learner. If it spells the word the other way from what the rule is
    // about to key, the rule does not govern this occurrence and teaching it
    // here teaches that the sentence is wrong: "Der Europäische Gerichtshof
    // spricht Recht für ganz Europa" was asked as an adjective and keyed
    // klein, because Europäische is an adjective everywhere except in the
    // name of a court. At the start of a sentence every word is capitalised
    // whatever its class, which the game asks about separately.
    if (!isAtStart) {
      final writtenCapitalised = actualWordInSentence.isNotEmpty &&
          actualWordInSentence[0].toUpperCase() == actualWordInSentence[0] &&
          actualWordInSentence[0].toLowerCase() != actualWordInSentence[0];
      final expectedCapitalised = correctCase == WordCase.capitalized;
      if (writtenCapitalised != expectedCapitalised) continue;
    }

    final challenge = SentenceChallenge(
      beforeWord: before,
      targetWord: actualWordInSentence,
      afterWord: after,
      correctCase: correctCase,
      rule: rule,
      explanation: explanation,
      wordId: word.id,
      isAtSentenceStart: isAtStart,
    );

    return challenge;
  }

  return null;
}
