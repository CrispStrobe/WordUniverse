// lib/core/models/vocabulary_item.dart
class VocabularyItem {
  final String id;
  final String german;
  final String english; // or other target language
  final String? article; // der/die/das
  final WordType type; // noun, verb, adjective
  final String? plural;
  final String? audioUrl;
  final List<String> exampleSentences;
  final int difficulty; // A1-C2 or grade level
  final List<String> topics; // categories
}