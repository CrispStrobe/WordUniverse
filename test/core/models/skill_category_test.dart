import 'package:WortUniversum/core/models/skill_category.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('vocabulary band conversion', () {
    test('maps the four learner-facing bands without an offset', () {
      expect(gradeLevelFromBand(1), GradeLevel.grade1);
      expect(gradeLevelFromBand(2), GradeLevel.grade2);
      expect(gradeLevelFromBand(3), GradeLevel.grade3);
      expect(gradeLevelFromBand(4), GradeLevel.grade4);
    });

    test('clamps external values safely', () {
      expect(gradeLevelFromBand(0), GradeLevel.grade1);
      expect(gradeLevelFromBand(99), GradeLevel.grade4);
      expect(gradeLevelFromStoredLevel(0), GradeLevel.grade1);
      expect(gradeLevelFromStoredLevel(99), GradeLevel.grade6);
    });

    test('round-trips every stored enum value', () {
      for (final level in GradeLevel.values) {
        expect(gradeLevelFromStoredLevel(bandFromGradeLevel(level)), level);
      }
    });
  });
}
