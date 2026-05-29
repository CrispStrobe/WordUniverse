// lib/features/games/models/false_friend.dart
//
// Model for the EN `false_friends` table (built by
// pipeline/voc-en/add_false_friends_en.py). Curated DE↔EN false friends —
// English words that look like a German word but mean something different
// (gift ≠ Gift). For the EN learning mode (German speakers learning English).

class FalseFriend {
  final String english; // "gift"
  final String german; // "Gift"
  final String englishMeans; // German gloss of the English word ("Geschenk")
  final String germanMeans; // English gloss of the German word ("poison")
  final String? example; // English sentence using the English word correctly

  const FalseFriend({
    required this.english,
    required this.german,
    required this.englishMeans,
    required this.germanMeans,
    this.example,
  });

  factory FalseFriend.fromRow(Map<String, dynamic> row) {
    String s(dynamic v) => (v ?? '').toString();
    final ex = s(row['example']).trim();
    return FalseFriend(
      english: s(row['english']),
      german: s(row['german']),
      englishMeans: s(row['english_means']),
      germanMeans: s(row['german_means']),
      example: ex.isEmpty ? null : ex,
    );
  }
}
