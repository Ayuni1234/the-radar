import 'package:flutter_test/flutter_test.dart';
import 'package:the_radar/src/state/age_verification.dart';

void main() {
  final now = DateTime(2026, 10, 29);

  group('checkBirthYear', () {
    test('missing, invalid, future and valid entries', () {
      expect(checkBirthYear(null, now: now), AgeCheck.missing);
      expect(checkBirthYear(1899, now: now), AgeCheck.invalid);
      expect(checkBirthYear(2027, now: now), AgeCheck.future);
      expect(checkBirthYear(2012, now: now), AgeCheck.valid);
    });
  });

  group('isMinorFromBirthYear', () {
    test('under 18 is a minor, 18 and over is not', () {
      expect(isMinorFromBirthYear(2012, now: now), isTrue);
      expect(isMinorFromBirthYear(2009, now: now), isTrue); // age 17
      expect(isMinorFromBirthYear(2008, now: now), isFalse); // age 18
      expect(isMinorFromBirthYear(1990, now: now), isFalse);
    });

    test('missing or invalid birth year never marks a user as an adult', () {
      expect(isMinorFromBirthYear(null, now: now), isFalse);
      expect(isMinorFromBirthYear(1800, now: now), isFalse);
    });
  });

  group('generalizeForMinor', () {
    test('rounds a minor coordinate to 0.1 degrees', () {
      final g = generalizeForMinor(4.0512, 9.7679, isMinor: true);
      expect(g.lat, closeTo(4.1, 1e-9));
      expect(g.lon, closeTo(9.8, 1e-9));
    });

    test('adults keep exact coordinates', () {
      final g = generalizeForMinor(4.0512, 9.7679, isMinor: false);
      expect(g.lat, 4.0512);
      expect(g.lon, 9.7679);
    });
  });
}
