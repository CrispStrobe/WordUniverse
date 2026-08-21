// lib/features/home/widgets/word_of_the_day_card.dart
//
// Word of the Day home-screen card.
// Picks a deterministic word each calendar day (day-of-year hash into the
// grade-1–2 word pool). Shows the word, its first definition, one grade
// example sentence, and up to 3 synonyms. DE + EN depending on learningLanguage.
//
// The card is additive: if the vocabulary service hasn't been initialized yet
// it silently shows nothing (no flash of content on first launch).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/skill_category.dart';
import '../../../core/models/vocabulary_models.dart';
import '../../../core/services/audio_service.dart';
import '../../../core/services/vocabulary_service.dart';
import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';
import '../../games/providers/game_provider.dart';
import '../../games/screens/definition_quiz_game.dart';
import '../../games/widgets/cefr_chip.dart';
import '../services/word_of_the_day_service.dart';

class WordOfTheDayCard extends StatelessWidget {
  final bool isVerySmall;
  const WordOfTheDayCard({super.key, this.isVerySmall = false});

  @override
  Widget build(BuildContext context) {
    final vocabService = context.watch<VocabularyService>();
    if (!vocabService.isInitialized) return const SizedBox.shrink();

    final gameProvider = context.read<GameProvider>();
    final words = vocabService.getAllWords(gameProvider);
    final word = pickWordOfTheDay(words, DateTime.now(),
        targetBand: gameProvider.grade.clamp(1, 4));
    if (word == null) return const SizedBox.shrink();

    return _WordOfTheDayContent(word: word, isVerySmall: isVerySmall);
  }
}

class _WordOfTheDayContent extends StatelessWidget {
  final GermanWord word;
  final bool isVerySmall;
  const _WordOfTheDayContent({required this.word, required this.isVerySmall});

  String? get _definition {
    final defs = word.apiEnrichment?.definitions;
    if (defs != null && defs.isNotEmpty) return defs.first;
    final ex = word.exampleSentences;
    if (ex.isNotEmpty) return ex.first;
    return null;
  }

  String? get _exampleSentence {
    final grade = word.gradeLevel;
    final gradeExamples = word.apiEnrichment?.gradeExamples?['$grade'] ?? [];
    if (gradeExamples.isNotEmpty) return gradeExamples.first;
    final ex = word.examples;
    if (ex.isNotEmpty) {
      final sent = ex.first.text;
      if (sent != null && sent.isNotEmpty) return sent;
    }
    return null;
  }

  List<String> get _synonyms {
    return (word.apiEnrichment?.synonyms ?? []).take(3).toList();
  }

  void _showDetail(BuildContext context, bool isDE) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WordDetailSheet(word: word, isDE: isDE),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context)!;
    final audioService = context.read<AudioService>();
    final isDE = context.read<VocabularyService>().learningLanguage == 'de';
    final definition = _definition;
    final example = _exampleSentence;
    final synonyms = _synonyms;

    return GestureDetector(
      onTap: () => _showDetail(context, isDE),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: isVerySmall ? 14 : 18,
          vertical: isVerySmall ? 12 : 16,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1A237E).withValues(alpha: 0.7),
              SpaceTheme.deepSpace.withValues(alpha: 0.85),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: SpaceTheme.starYellow.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Icon(Icons.wb_sunny_outlined,
                    color: SpaceTheme.starYellow, size: isVerySmall ? 14 : 16),
                const SizedBox(width: 6),
                Text(
                  s.wordOfTheDay,
                  style: TextStyle(
                    color: SpaceTheme.starYellow,
                    fontSize: isVerySmall ? 11 : 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                if (word.cefrLevel != null)
                  CefrChip(word.cefrLevel!, small: true),
              ],
            ),
            SizedBox(height: isVerySmall ? 6 : 8),

            // Word + speaker
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    word.article != null
                        ? '${word.article} ${word.word}'
                        : word.word,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isVerySmall ? 22 : 26,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () => audioService.speak(
                    word.word,
                    lang: isDE ? 'de-DE' : 'en-US',
                  ),
                  icon: const Icon(Icons.volume_up_rounded,
                      color: Colors.white60, size: 20),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: s.pronounce,
                ),
              ],
            ),

            // Definition
            if (definition != null) ...[
              SizedBox(height: isVerySmall ? 4 : 6),
              Text(
                definition,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: isVerySmall ? 12 : 13,
                  height: 1.35,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            // Example sentence
            if (example != null) ...[
              SizedBox(height: isVerySmall ? 4 : 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('»  ',
                      style: TextStyle(
                          color: SpaceTheme.planetOrange.withValues(alpha: 0.8),
                          fontSize: isVerySmall ? 11 : 12,
                          fontWeight: FontWeight.bold)),
                  Expanded(
                    child: Text(
                      example,
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: isVerySmall ? 11 : 12,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            // Synonyms
            if (synonyms.isNotEmpty) ...[
              SizedBox(height: isVerySmall ? 6 : 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: synonyms
                    .map(
                        (s) => _SynonymChip(label: s, isVerySmall: isVerySmall))
                    .toList(),
              ),
            ],

            // Tap hint
            SizedBox(height: isVerySmall ? 6 : 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  s.tapToPractise,
                  style: TextStyle(
                    color: SpaceTheme.starYellow.withValues(alpha: 0.6),
                    fontSize: isVerySmall ? 10 : 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SynonymChip extends StatelessWidget {
  final String label;
  final bool isVerySmall;
  const _SynonymChip({required this.label, required this.isVerySmall});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isVerySmall ? 7 : 9, vertical: isVerySmall ? 2 : 3),
      decoration: BoxDecoration(
        color: SpaceTheme.nebulaPurple.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: SpaceTheme.nebulaPurple.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white70,
          fontSize: isVerySmall ? 10 : 11,
        ),
      ),
    );
  }
}

// ─── Word Detail Bottom Sheet ─────────────────────────────────────────────────

class _WordDetailSheet extends StatelessWidget {
  final GermanWord word;
  final bool isDE;
  const _WordDetailSheet({required this.word, required this.isDE});

  GradeLevel get _gradeLevel => gradeLevelFromBand(word.gradeLevel);

  @override
  Widget build(BuildContext context) {
    final s = S.of(context)!;
    final audioService = context.read<AudioService>();
    final defs = word.apiEnrichment?.definitions ?? [];
    final synonyms = word.apiEnrichment?.synonyms ?? [];
    final antonyms = word.apiEnrichment?.antonyms ?? [];
    final entryNotes = word.entryNotes;
    final gradeExamples =
        word.apiEnrichment?.gradeExamples?['${word.gradeLevel}'] ?? [];
    final allExamples = [
      ...gradeExamples,
      ...word.exampleSentences,
    ].take(3).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0D1B2A),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border:
              Border.all(color: SpaceTheme.starYellow.withValues(alpha: 0.2)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            // drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Word + TTS + CEFR
            Row(
              children: [
                Expanded(
                  child: Text(
                    word.article != null
                        ? '${word.article} ${word.word}'
                        : word.word,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => audioService.speak(
                    word.word,
                    lang: isDE ? 'de-DE' : 'en-US',
                  ),
                  icon: const Icon(Icons.volume_up_rounded,
                      color: Colors.white60, size: 22),
                  tooltip: s.pronounce,
                ),
                if (word.cefrLevel != null) CefrChip(word.cefrLevel!),
              ],
            ),
            const SizedBox(height: 4),

            // Grade badge
            Text(
              s.gradeLabel(word.gradeLevel),
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 16),

            // Definitions
            if (defs.isNotEmpty) ...[
              _SectionHeader(s.sectionDefinitions),
              const SizedBox(height: 6),
              for (final d in defs.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ',
                          style: TextStyle(
                              color: SpaceTheme.starYellow, fontSize: 13)),
                      Expanded(
                        child: Text(d,
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                height: 1.4)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
            ],

            // Examples
            if (allExamples.isNotEmpty) ...[
              _SectionHeader(s.sectionExamples),
              const SizedBox(height: 6),
              for (final ex in allExamples)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    '» $ex',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      height: 1.35,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
            ],

            // Synonyms
            if (synonyms.isNotEmpty) ...[
              _SectionHeader(s.sectionSynonyms),
              const SizedBox(height: 6),
              Wrap(
                spacing: 7,
                runSpacing: 5,
                children: synonyms
                    .take(8)
                    .map((s) => _SynonymChip(label: s, isVerySmall: false))
                    .toList(),
              ),
              const SizedBox(height: 12),
            ],

            // Antonyms
            if (antonyms.isNotEmpty) ...[
              _SectionHeader(s.sectionAntonyms),
              const SizedBox(height: 6),
              Wrap(
                spacing: 7,
                runSpacing: 5,
                children: antonyms
                    .take(6)
                    .map((s) => _SynonymChip(label: s, isVerySmall: false))
                    .toList(),
              ),
              const SizedBox(height: 12),
            ],

            // Entry notes (etymology for grade 5+)
            if (entryNotes.isNotEmpty && word.gradeLevel >= 5) ...[
              _SectionHeader('💡 ${s.didYouKnow}'),
              const SizedBox(height: 6),
              Text(
                entryNotes.first,
                style: const TextStyle(
                    color: Colors.white60, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
            ],

            const SizedBox(height: 8),

            // Practice button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DefinitionQuizGame(
                        gradeLevel: _gradeLevel,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(s.practiceNow),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SpaceTheme.starYellow,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: SpaceTheme.starYellow,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      );
}
