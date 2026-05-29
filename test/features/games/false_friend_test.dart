// test/features/games/false_friend_test.dart
//
// Unit tests for FalseFriend.fromRow (the false_friends table row parser).

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/features/games/models/false_friend.dart';

void main() {
  group('FalseFriend.fromRow', () {
    test('parses a full row', () {
      final ff = FalseFriend.fromRow({
        'english': 'gift',
        'german': 'Gift',
        'english_means': 'Geschenk',
        'german_means': 'poison',
        'example': 'She gave me a birthday gift.',
      });
      expect(ff.english, 'gift');
      expect(ff.german, 'Gift');
      expect(ff.englishMeans, 'Geschenk');
      expect(ff.germanMeans, 'poison');
      expect(ff.example, 'She gave me a birthday gift.');
    });

    test('null/empty example becomes null', () {
      final a = FalseFriend.fromRow({
        'english': 'rat',
        'german': 'Rat',
        'english_means': 'Ratte',
        'german_means': 'advice',
        'example': '',
      });
      final b = FalseFriend.fromRow({
        'english': 'rat',
        'german': 'Rat',
        'english_means': 'Ratte',
        'german_means': 'advice',
      });
      expect(a.example, isNull);
      expect(b.example, isNull);
    });

    test('tolerates missing fields', () {
      final ff = FalseFriend.fromRow({'english': 'fast'});
      expect(ff.english, 'fast');
      expect(ff.german, '');
      expect(ff.example, isNull);
    });
  });
}
