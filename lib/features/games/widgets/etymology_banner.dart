// lib/features/games/widgets/etymology_banner.dart
//
// "Did you know?" banner shown after correct answers for grade 5-6 words.
// Reads from word.entryNotes (Wiktionary linguistic notes). Hidden when
// entryNotes is empty or word grade < 5.

import 'package:flutter/material.dart';

import '../../../core/models/vocabulary_models.dart';
import '../../../core/theme/space_theme.dart';
import '../../../generated/l10n.dart';

/// Returns the first entry note for [word] when the word is grade 5 or 6
/// and notes are available. Returns null otherwise.
/// This pure function is the testable kernel of [EtymologyBanner].
String? etymologyNoteFor(GermanWord word) {
  if (word.gradeLevel < 5) return null;
  if (word.entryNotes.isEmpty) return null;
  return word.entryNotes.first;
}

class EtymologyBanner extends StatelessWidget {
  final GermanWord word;

  const EtymologyBanner({
    super.key,
    required this.word,
  });

  @override
  Widget build(BuildContext context) {
    final note = etymologyNoteFor(word);
    if (note == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: SpaceTheme.starYellow.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: SpaceTheme.starYellow.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('💡 ', style: TextStyle(fontSize: 16)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.of(context)!.didYouKnow,
                  style: TextStyle(
                    color: SpaceTheme.starYellow.withValues(alpha: 0.9),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  note,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
