import 'package:flutter_test/flutter_test.dart';
import 'package:stack_the_cats/services/age_gate.dart';

void main() {
  group('AgeGate.isKidBornIn', () {
    test('under 13 is a kid; turning 13 this year still counts', () {
      expect(AgeGate.isKidBornIn(2020, 2026), isTrue);
      expect(AgeGate.isKidBornIn(2013, 2026), isTrue);
      expect(AgeGate.isKidBornIn(2012, 2026), isFalse);
      expect(AgeGate.isKidBornIn(1990, 2026), isFalse);
    });

    test('a kid until the age is known', () {
      expect(AgeGate.isKidBornIn(null, 2026), isTrue);
    });

    test('years offered: this year back 100, newest first', () {
      final years = AgeGate.yearsToPick(2026);
      expect(years.first, 2026);
      expect(years.last, 1926);
      expect(years.length, 101);
    });
  });

  group('KidName', () {
    test('the same names as the server (functions/test/api.test.mjs)', () {
      expect(KidName.forUid('abc123'), 'Speedy Kitten 98');
      expect(KidName.forUid('Xy9QpL2mN8rT4vW6zK1jH3gF5dS7'), 'Fluffy Muffin 52');
    });

    test('always the same name for the same account', () {
      expect(KidName.forUid('someUid'), KidName.forUid('someUid'));
    });
  });
}
