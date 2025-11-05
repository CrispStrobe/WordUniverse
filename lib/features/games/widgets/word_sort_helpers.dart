// lib/features/games/widgets/word_sort_helpers.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/services/vocabulary_service.dart';
import '../../../core/theme/space_theme.dart';
import '../models/word_sort_types.dart';

class GenderColors {
  static const masculine = Colors.blue;
  static const feminine = Colors.pink;
  static const neuter = Colors.green;

  static Color fromString(String? gender) {
    if (gender?.toLowerCase() == 'masculine') return masculine;
    if (gender?.toLowerCase() == 'feminine') return feminine;
    if (gender?.toLowerCase() == 'neuter') return neuter;
    return Colors.grey;
  }
}

class ArticleBadge extends StatelessWidget {
  final String article;
  final String? gender;

  const ArticleBadge({
    super.key,
    required this.article,
    this.gender,
  });

  @override
  Widget build(BuildContext context) {
    final color = GenderColors.fromString(gender);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            article,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          if (gender != null) ...[
            const SizedBox(width: 8),
            Text(
              gender!,
              style: TextStyle(
                fontSize: 14,
                color: color.withOpacity(0.8),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class FeedbackCard extends StatelessWidget {
  final FeedbackState state;
  final String? message;
  final List<String>? hints;
  final GermanWord? word;
  final bool showDetailedInfo;
  final Animation<double> animation;

  const FeedbackCard({
    super.key,
    required this.state,
    this.message,
    this.hints,
    this.word,
    required this.showDetailedInfo,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color borderColor;
    IconData icon;

    if (state == FeedbackState.correct) {
      backgroundColor = Colors.green.withOpacity(0.9);
      borderColor = Colors.greenAccent;
      icon = Icons.check_circle;
    } else if (state == FeedbackState.incorrect) {
      backgroundColor = Colors.red.withOpacity(0.9);
      borderColor = Colors.redAccent;
      icon = Icons.cancel;
    } else if (state == FeedbackState.hint) {
      backgroundColor = SpaceTheme.cosmicPink.withOpacity(0.9);
      borderColor = SpaceTheme.starYellow;
      icon = Icons.lightbulb;
    } else {
      return const SizedBox.shrink();
    }

    return FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.8, end: 1.0).animate(animation),
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: 3),
            boxShadow: [
              BoxShadow(
                color: borderColor.withOpacity(0.5),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64, color: Colors.white),
              const SizedBox(height: 16),
              if (message != null)
                Text(
                  message!,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
              if (hints != null && hints!.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(color: Colors.white54),
                const SizedBox(height: 16),
                ...hints!.map((hint) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(fontSize: 18, color: Colors.white)),
                      Expanded(
                        child: Text(
                          hint,
                          style: const TextStyle(fontSize: 16, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                )),
              ],
              if (showDetailedInfo && word != null)
                _buildDetailedInfo(word!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailedInfo(GermanWord word) {
    final inflection = word.inflectionData;
    if (inflection == null) return const SizedBox.shrink();

    final wordTypeStr = word.wordType.toString();
    
    return Column(
      children: [
        const SizedBox(height: 16),
        const Divider(color: Colors.white54),
        const SizedBox(height: 16),
        if (wordTypeStr.contains('substantiv'))
          _buildNounDetails(inflection),
        if (wordTypeStr.contains('verb'))
          _buildVerbDetails(inflection),
        if (wordTypeStr.contains('adjektiv'))
          _buildAdjectiveDetails(inflection),
      ],
    );
  }

  Widget _buildNounDetails(Map<String, dynamic> inflection) {
    final nounData = inflection['analyses']?['noun'];
    if (nounData == null) return const SizedBox.shrink();

    final declension = nounData['declension'] as Map<String, dynamic>?;
    if (declension == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Text('Deklination', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 12),
          _buildDeclensionTable(declension),
        ],
      ),
    );
  }

  Widget _buildDeclensionTable(Map<String, dynamic> declension) {
    final cases = ['Nominativ', 'Akkusativ', 'Dativ', 'Genitiv'];
    
    return Table(
      border: TableBorder.all(color: Colors.white54),
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.1)),
          children: ['Fall', 'Singular', 'Plural'].map((header) => Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(header, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center),
          )).toList(),
        ),
        ...cases.map((caseName) {
          final singularKey = '$caseName Singular';
          final pluralKey = '$caseName Plural';
          final singular = declension[singularKey]?['definite'] ?? '-';
          final plural = declension[pluralKey]?['definite'] ?? '-';
          
          return TableRow(
            children: [
              Padding(padding: const EdgeInsets.all(8.0), child: Text(caseName.substring(0, 3), style: const TextStyle(color: Colors.white))),
              Padding(padding: const EdgeInsets.all(8.0), child: Text(singular, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center)),
              Padding(padding: const EdgeInsets.all(8.0), child: Text(plural, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center)),
            ],
          );
        }).toList(),
      ],
    );
  }

  Widget _buildVerbDetails(Map<String, dynamic> inflection) {
    final verbData = inflection['analyses']?['verb'];
    if (verbData == null) return const SizedBox.shrink();

    final conjugation = verbData['conjugation']?['Präsens'];
    if (conjugation == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          const Text('Konjugation (Präsens)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 12),
          ...conjugation.entries.map((entry) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(entry.key, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                Text(entry.value.toString(), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildAdjectiveDetails(Map<String, dynamic> inflection) {
    final adjData = inflection['analyses']?['adjective'];
    if (adjData == null) return const SizedBox.shrink();

    final predicative = adjData['predicative'] ?? '';
    final comparative = adjData['comparative'] ?? '';
    final superlative = adjData['superlative'] ?? '';

    if (predicative.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          const Text('Steigerung', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildComparisonBox('Positiv', predicative),
              const Icon(Icons.arrow_forward, color: Colors.white70),
              _buildComparisonBox('Komparativ', comparative),
              const Icon(Icons.arrow_forward, color: Colors.white70),
              _buildComparisonBox('Superlativ', superlative),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonBox(String label, String form) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),
        Text(form, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class CategoryConfetti extends StatelessWidget {
  final AnimationController controller;
  final dynamic category; // Changed to dynamic

  const CategoryConfetti({
    super.key,
    required this.controller,
    required this.category,
  });

  String _getEmoji() {
    final categoryStr = category.toString().toLowerCase();
    if (categoryStr.contains('substantiv')) {
      return '🏠';
    } else if (categoryStr.contains('verb')) {
      return '🏃';
    } else if (categoryStr.contains('adjektiv')) {
      return '🎨';
    }
    return '⭐';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Stack(
          children: List.generate(20, (index) {
            final random = math.Random(index);
            final startX = random.nextDouble() * MediaQuery.of(context).size.width;
            final endY = MediaQuery.of(context).size.height;
            final progress = controller.value;

            return Positioned(
              left: startX,
              top: progress * endY - 100,
              child: Opacity(
                opacity: 1.0 - progress,
                child: Transform.rotate(
                  angle: progress * 4 * math.pi,
                  child: Text(_getEmoji(), style: const TextStyle(fontSize: 32)),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}