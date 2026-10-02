import 'package:flutter_test/flutter_test.dart';
import 'package:stack_the_cats/economy/treats.dart';
import 'package:stack_the_cats/store/catalog.dart';

void main() {
  group('Treats.forLanding', () {
    test('pays nothing for the first three perfects in a row', () {
      for (final combo in [0, 1, 2, 3]) {
        expect(Treats.forLanding(combo: combo, score: 7), 0);
      }
    });

    test('pays 10 for every perfect after three in a row', () {
      expect(Treats.forLanding(combo: 4, score: 7), 10);
      expect(Treats.forLanding(combo: 12, score: 7), 10);
    });

    test('pays 50 at every 50 cats, except where a fish is given', () {
      expect(Treats.forLanding(combo: 0, score: 50), 50);
      expect(Treats.forLanding(combo: 0, score: 150), 50);
      expect(Treats.forLanding(combo: 0, score: 49), 0);
      // 100, 200, 300 ... pay a Tuna or Salmon instead.
      expect(Treats.forLanding(combo: 0, score: 100), 0);
      expect(Treats.forLanding(combo: 0, score: 200), 0);
    });

    test('streak and milestone add up on the same landing', () {
      expect(Treats.forLanding(combo: 5, score: 50), 60);
    });
  });

  group('Store cat bonuses', () {
    test('a Purrfect outside a streak: basic 0, Special +1, Exotic +5', () {
      for (final combo in [1, 2, 3]) {
        expect(Treats.forLanding(combo: combo, score: 7), 0);
        expect(
          Treats.forLanding(combo: combo, score: 7, tier: CatTier.special),
          1,
        );
        expect(
          Treats.forLanding(combo: combo, score: 7, tier: CatTier.exotic),
          5,
        );
      }
    });

    test('in a streak: basic 10, Special 13, Exotic 20', () {
      expect(Treats.forLanding(combo: 4, score: 7), 10);
      expect(Treats.forLanding(combo: 4, score: 7, tier: CatTier.special), 13);
      expect(Treats.forLanding(combo: 9, score: 7, tier: CatTier.exotic), 20);
    });

    test('a landing that is not Purrfect pays no cat bonus', () {
      for (final tier in CatTier.values) {
        expect(Treats.forLanding(combo: 0, score: 7, tier: tier), 0);
      }
    });

    test('the 50-cat bonus still adds on top', () {
      expect(Treats.forLanding(combo: 2, score: 50, tier: CatTier.exotic), 55);
    });
  });

  group('Treats.reviveCostFor', () {
    test('250 for towers up to 50 cats', () {
      expect(Treats.reviveCostFor(0), 250);
      expect(Treats.reviveCostFor(30), 250);
      expect(Treats.reviveCostFor(50), 250);
    });

    test('3 more for every cat above 50', () {
      expect(Treats.reviveCostFor(51), 253);
      expect(Treats.reviveCostFor(60), 280);
      expect(Treats.reviveCostFor(100), 400);
      expect(Treats.reviveCostFor(200), 700);
    });
  });

  test('realign costs 250', () {
    expect(Treats.realignCost, 250);
  });

  group('DailyStatus.compute', () {
    final now = DateTime(2026, 10, 1, 9);

    test('first ever claim is day 1', () {
      final s = DailyStatus.compute(lastClaim: null, lastDay: 0, now: now);
      expect((s.day, s.claimable, s.reward), (1, true, 10));
    });

    test('claiming on consecutive days moves the streak on', () {
      final s = DailyStatus.compute(
        lastClaim: '2026-09-30',
        lastDay: 3,
        now: now,
      );
      expect((s.day, s.claimable, s.reward), (4, true, 50));
    });

    test('already claimed today is not claimable', () {
      final s = DailyStatus.compute(
        lastClaim: '2026-10-01',
        lastDay: 4,
        now: now,
      );
      expect((s.day, s.claimable), (4, false));
    });

    test('missing a day resets to day 1', () {
      final s = DailyStatus.compute(
        lastClaim: '2026-09-29',
        lastDay: 5,
        now: now,
      );
      expect((s.day, s.claimable), (1, true));
    });

    test('after day 7 the streak starts over', () {
      final s = DailyStatus.compute(
        lastClaim: '2026-09-30',
        lastDay: 7,
        now: now,
      );
      expect((s.day, s.reward), (1, 10));
    });

    test('day 7 pays 200', () {
      final s = DailyStatus.compute(
        lastClaim: '2026-09-30',
        lastDay: 6,
        now: now,
      );
      expect((s.day, s.reward), (7, 200));
    });

    test('yesterday works across a month boundary', () {
      final s = DailyStatus.compute(
        lastClaim: '2026-09-30',
        lastDay: 1,
        now: DateTime(2026, 10, 1),
      );
      expect(s.day, 2);
    });
  });
}
