// lib/features/games/services/translation_flash_service.dart
//
// Translation Flash and Reverse Translation Flash challenge construction,
// extracted from the screens so they can be generated and reviewed without
// running the games. See docs/content-audit.md.
//
// Both directions read `apiEnrichment.translations` (lang_code == 'en') and
// share the cleanliness rule, so they share a file.

import 'dart:math';

import '../../../core/models/vocabulary_models.dart';
import '../../../core/models/vocabulary_quality.dart';

class TranslationChallenge {
  const TranslationChallenge({
    required this.word,
    required this.translation,
    required this.options,
    required this.correctIndex,
  });

  /// The catalogue word being asked about.
  final GermanWord word;

  /// Its English translation — the answer when asking word → English, the
  /// prompt when asking English → word.
  final String translation;
  final List<String> options;
  final int correctIndex;
}

/// Whether an English gloss is usable as a one-word answer.
bool isCleanTranslation(String word) {
  if (word.isEmpty) return false;
  if (word.contains('.')) return false;
  if (word == word.toUpperCase() && word.length > 1) return false;
  if (!RegExp(r"^[a-zA-Z\-' ]+$").hasMatch(word)) return false;
  return word.split(' ').length <= 2;
}

/// The English translation a challenge should use, or null when none is clean.
String? primaryEnglishTranslation(GermanWord word) {
  for (final translation in word.apiEnrichment?.translations ?? const []) {
    if (translation.langCode == 'en' && translation.word != null) {
      final candidate = translation.word!.trim();
      if (isCleanTranslation(candidate)) return candidate;
    }
  }
  return null;
}

/// Every clean English translation of [word], for excluding from distractors.
Set<String> englishTranslations(GermanWord word) => (word.apiEnrichment
            ?.translations ??
        const [])
    .where((t) => t.langCode == 'en' && t.word != null)
    .map((t) => t.word!.toLowerCase())
    .toSet();

/// Builds up to [maxChallenges] asking for the English of a catalogue word.
///
/// [reversed] swaps which side is the prompt; the challenge data is the same
/// either way, so both screens share this.
List<TranslationChallenge> buildTranslationChallenges({
  required List<GermanWord> pool,
  int maxChallenges = 10,
  int optionCount = 4,
  bool reversed = false,
  Random? rng,
}) {
  final random = rng ?? Random();

  // Options come from the other words' translations (or their spellings, when
  // the prompt is the English side).
  final englishPool = <String>[
    for (final word in pool)
      if (primaryEnglishTranslation(word) case final translation?) translation,
  ]..shuffle(random);
  final wordPool = <String>[
    for (final word in pool)
      if (!namesSomething(word)) word.word,
  ]..shuffle(random);

  final challenges = <TranslationChallenge>[];
  for (final word in pool) {
    if (challenges.length >= maxChallenges) break;
    final challenge = buildTranslationChallenge(
      word: word,
      optionTexts: reversed ? wordPool : englishPool,
      reversed: reversed,
      optionCount: optionCount,
      rng: random,
    );
    if (challenge != null) challenges.add(challenge);
  }
  return challenges;
}

/// One challenge, or null when [word] cannot make a full set of options.
TranslationChallenge? buildTranslationChallenge({
  required GermanWord word,
  required List<String> optionTexts,
  bool reversed = false,
  int optionCount = 4,
  Random? rng,
}) {
  final random = rng ?? Random();
  if (namesSomething(word)) return null;

  final translation = primaryEnglishTranslation(word);
  if (translation == null) return null;

  // When the English is the prompt, the answer is the catalogue word itself.
  final correct = reversed ? word.word : translation;
  final excluded = reversed
      ? {word.word.toLowerCase()}
      : englishTranslations(word)..add(correct.toLowerCase());

  // Shuffled per challenge: taking from the front of one shuffled list put
  // the same three distractors in every round.
  final distractors = <String>[];
  for (final text in optionTexts.toList()..shuffle(random)) {
    if (distractors.length >= optionCount - 1) break;
    if (excluded.contains(text.toLowerCase())) continue;
    if (distractors.any((d) => d.toLowerCase() == text.toLowerCase())) continue;
    distractors.add(text);
  }
  if (distractors.length < optionCount - 1) return null;

  final options = [correct, ...distractors.take(optionCount - 1)]
    ..shuffle(random);
  final correctIndex =
      options.indexWhere((o) => o.toLowerCase() == correct.toLowerCase());
  if (correctIndex < 0) return null;

  return TranslationChallenge(
    word: word,
    translation: translation,
    options: options,
    correctIndex: correctIndex,
  );
}
