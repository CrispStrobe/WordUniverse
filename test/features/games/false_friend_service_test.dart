// test/features/games/false_friend_service_test.dart

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:WortUniversum/features/games/models/false_friend.dart';
import 'package:WortUniversum/features/games/services/false_friend_service.dart';

FalseFriend _ff(String en, String de, String enMeans, String deMeans) =>
    FalseFriend(
      english: en,
      german: de,
      englishMeans: enMeans,
      germanMeans: deMeans,
      example: null,
    );

void main() {
  final sample = [
    _ff('gift', 'Gift', 'Geschenk', 'poison'),
    _ff('become', 'bekommen', 'werden', 'to receive'),
    _ff('boot', 'Boot', 'Stiefel', 'boat'),
    _ff('brand', 'Brand', 'Marke', 'fire'),
    _ff('rat', 'Rat', 'Ratte', 'advice'),
  ];

  group('buildFalseFriendChallenges', () {
    test('correct meaning indexed correctly; trap look-alike is an option', () {
      final cs = buildFalseFriendChallenges(friends: sample, rng: Random(1));
      expect(cs, isNotEmpty);
      for (final c in cs) {
        expect(c.options[c.correctIndex], c.correctMeaning);
        // the German look-alike word appears as a trap distractor
        expect(c.options.map((o) => o.toLowerCase()), contains(c.german.toLowerCase()));
        expect(c.options.length, lessThanOrEqualTo(4));
      }
    });

    test('options have no duplicates', () {
      final c = buildFalseFriendChallenges(friends: sample, rng: Random(2)).first;
      final lc = c.options.map((o) => o.toLowerCase()).toList();
      expect(lc.toSet().length, lc.length);
    });

    test('skips entries without english or meaning', () {
      final cs = buildFalseFriendChallenges(
        friends: [_ff('', 'X', 'Y', 'Z'), _ff('gift', 'Gift', '', 'poison'), ...sample],
        rng: Random(3),
      );
      expect(cs.every((c) => c.english.isNotEmpty && c.correctMeaning.isNotEmpty), isTrue);
    });

    test('returns empty with fewer than two usable friends', () {
      expect(buildFalseFriendChallenges(friends: [_ff('gift', 'Gift', 'Geschenk', 'poison')], rng: Random(4)), isEmpty);
    });

    test('respects maxChallenges', () {
      final many = List.generate(20, (i) => _ff('w$i', 'W$i', 'M$i', 'X$i'));
      expect(buildFalseFriendChallenges(friends: many, maxChallenges: 5, rng: Random(5)).length, 5);
    });
  });
}
