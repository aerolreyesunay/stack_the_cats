import 'package:flutter_test/flutter_test.dart';
import 'package:stack_the_cats/challenge/match_rules.dart';
import 'package:stack_the_cats/economy/treats.dart';

void main() {
  group('Fish.forMilestone', () {
    test('a Tuna every 100 cats, a Salmon instead every 200', () {
      expect(Fish.forMilestone(0), isNull);
      expect(Fish.forMilestone(50), isNull);
      expect(Fish.forMilestone(99), isNull);
      expect(Fish.forMilestone(100), Fish.tuna);
      expect(Fish.forMilestone(200), Fish.salmon);
      expect(Fish.forMilestone(300), Fish.tuna);
      expect(Fish.forMilestone(400), Fish.salmon);
    });
  });

  group('UseCounter', () {
    test('2 with treats, 3 with fish, 3 with ads', () {
      final uses = UseCounter();
      for (var i = 0; i < 2; i++) {
        expect(uses.canUse(PayWith.treats), isTrue);
        uses.use(PayWith.treats);
      }
      expect(uses.canUse(PayWith.treats), isFalse);
      expect(uses.left(PayWith.fish), 3);
      expect(uses.left(PayWith.ad), 3);
      for (var i = 0; i < 3; i++) {
        uses
          ..use(PayWith.fish)
          ..use(PayWith.ad);
      }
      expect(uses.anyLeft, isFalse);
      uses.reset();
      expect(uses.left(PayWith.treats), 2);
      expect(uses.anyLeft, isTrue);
    });
  });

  group('SelfChallenge', () {
    test('speeds step up every 20 cats: 340 to 580', () {
      expect(SelfChallenge.swingSpeedFor(0), 340);
      expect(SelfChallenge.swingSpeedFor(19), 340);
      expect(SelfChallenge.swingSpeedFor(20), 400);
      expect(SelfChallenge.swingSpeedFor(40), 460);
      expect(SelfChallenge.swingSpeedFor(60), 520);
      expect(SelfChallenge.swingSpeedFor(80), 580);
      expect(SelfChallenge.swingSpeedFor(100), 580);
    });

    test('rewards by cats reached', () {
      expect(SelfChallenge.rewardFor(49), (tuna: 0, salmon: 0));
      expect(SelfChallenge.rewardFor(50), (tuna: 1, salmon: 0));
      expect(SelfChallenge.rewardFor(74), (tuna: 1, salmon: 0));
      expect(SelfChallenge.rewardFor(75), (tuna: 0, salmon: 1));
      expect(SelfChallenge.rewardFor(99), (tuna: 0, salmon: 1));
      expect(SelfChallenge.rewardFor(100), (tuna: 1, salmon: 1));
    });
  });

  group('CushionSway', () {
    test('still before 20 cats, even if shaky', () {
      expect(CushionSway.at(19, 0.2).amplitude, 0);
    });

    test('a balanced tower sways subtly from 20 cats', () {
      final calm = CushionSway.at(20, 1);
      expect(calm.amplitude, greaterThan(0));
      expect(calm.amplitude, lessThanOrEqualTo(10));
      expect(CushionSway.at(150, 1), calm);
    });

    test('the less stable, the wider and quicker; never fast', () {
      final calm = CushionSway.at(40, 1);
      final wobbly = CushionSway.at(40, 0.6);
      final shaky = CushionSway.at(40, 0);
      expect(wobbly.amplitude, greaterThan(calm.amplitude));
      expect(shaky.amplitude, greaterThan(wobbly.amplitude));
      expect(wobbly.period, lessThan(calm.period));
      expect(shaky.period, lessThan(wobbly.period));
      expect(shaky.period, greaterThanOrEqualTo(3));
    });

    test('offline games sway twice as fast, just as wide', () {
      final online = CushionSway.at(40, 0.6);
      final offline = CushionSway.at(40, 0.6, speed: CushionSway.offlineSpeed);
      expect(offline.amplitude, online.amplitude);
      expect(offline.period, online.period / 2);
    });
  });

  group('MatchStakes', () {
    test('Friendly: winner 30, loser 10, draw 20', () {
      const s = MatchStakes.friendly();
      expect(s.queueKey, 'friendly');
      expect(s.prizeFor(MatchOutcome.win), 30);
      expect(s.prizeFor(MatchOutcome.lose), 10);
      expect(s.prizeFor(MatchOutcome.draw), 20);
    });

    test('wager: the winner takes both stakes, a draw refunds', () {
      const s = MatchStakes.wager(300);
      expect(s.queueKey, 'wager300');
      expect(s.prizeFor(MatchOutcome.win), 600);
      expect(s.prizeFor(MatchOutcome.lose), 0);
      expect(s.prizeFor(MatchOutcome.draw), 300);
    });

    test('read back from a saved stake', () {
      expect(MatchStakes.fromStake(null), const MatchStakes.friendly());
      expect(MatchStakes.fromStake(0), const MatchStakes.friendly());
      expect(MatchStakes.fromStake(500), const MatchStakes.wager(500));
    });
  });
}
