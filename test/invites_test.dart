import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:stack_the_cats/economy/invites.dart';
import 'package:stack_the_cats/economy/treats.dart';

void main() {
  const limit = Treats.maxPaidSharesPerDay;

  group('Invites.randomCode', () {
    test('is 6 characters with no look-alike letters or digits', () {
      final rng = Random(1);
      for (var i = 0; i < 500; i++) {
        final code = Invites.randomCode(rng);
        expect(code.length, 6);
        expect(code, isNot(matches(RegExp('[01OIL]'))));
        expect(Invites.normalize(code), code);
      }
    });
  });

  group('Invites.normalize', () {
    test('accepts lower case, spaces and dashes', () {
      expect(Invites.normalize('cat7qk'), 'CAT7QK');
      expect(Invites.normalize(' CAT-7QK '), 'CAT7QK');
      expect(Invites.normalize('cat 7qk'), 'CAT7QK');
    });

    test('rejects wrong lengths and characters that are never used', () {
      expect(Invites.normalize('CAT7Q'), isNull);
      expect(Invites.normalize('CAT7QKX'), isNull);
      expect(Invites.normalize('CAT0QK'), isNull); // zero is never used
      expect(Invites.normalize('CATOQK'), isNull); // nor is the letter O
      expect(Invites.normalize(''), isNull);
    });
  });

  group('ShareAllowance', () {
    test('the limit is 50 shares a day, 1 treat each', () {
      expect(limit, 50);
      expect(Treats.shareReward, 1);
    });

    test('a new day starts with the full allowance', () {
      final a = ShareAllowance.compute(
        day: '2026-09-30',
        count: limit,
        today: '2026-10-01',
      );
      expect((a.left, a.canEarn), (limit, true));
    });

    test('counts shares already paid today', () {
      final a = ShareAllowance.compute(
        day: '2026-10-01',
        count: 3,
        today: '2026-10-01',
      );
      expect(a.left, limit - 3);
    });

    test('stops paying at the daily limit', () {
      final a = ShareAllowance.compute(
        day: '2026-10-01',
        count: limit,
        today: '2026-10-01',
      );
      expect((a.left, a.canEarn), (0, false));
    });

    test('never shared before', () {
      final a = ShareAllowance.compute(
        day: null,
        count: 0,
        today: '2026-10-01',
      );
      expect(a.left, limit);
    });
  });

  test('the share message includes the code', () {
    expect(Invites.shareMessage('CAT7QK'), contains('CAT7QK'));
  });
}
