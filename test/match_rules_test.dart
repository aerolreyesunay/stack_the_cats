import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:stack_the_cats/challenge/match_rules.dart';
import 'package:stack_the_cats/game/cat.dart';

Racer alive(int score) => Racer(score: score, alive: true);
Racer fell(int score) => Racer(score: score, alive: false);

void main() {
  group('outcomeFor', () {
    test('undecided while both are still stacking', () {
      expect(outcomeFor(alive(10), alive(30)), MatchOutcome.undecided);
    });

    test('my tower fell but they have not passed me yet', () {
      expect(outcomeFor(fell(10), alive(8)), MatchOutcome.undecided);
      expect(outcomeFor(fell(10), alive(10)), MatchOutcome.undecided);
    });

    test('they win the moment they pass my fallen score', () {
      expect(outcomeFor(fell(10), alive(11)), MatchOutcome.lose);
    });

    test('I win the moment I pass their fallen score', () {
      expect(outcomeFor(alive(11), fell(10)), MatchOutcome.win);
    });

    test('both fell: higher score wins, equal is a draw', () {
      expect(outcomeFor(fell(12), fell(7)), MatchOutcome.win);
      expect(outcomeFor(fell(7), fell(12)), MatchOutcome.lose);
      expect(outcomeFor(fell(9), fell(9)), MatchOutcome.draw);
    });

    test('a forfeit loses, whatever the scores', () {
      final quit = Racer(score: 50, alive: true, forfeited: true);
      expect(outcomeFor(alive(1), quit), MatchOutcome.win);
      expect(outcomeFor(quit, alive(1)), MatchOutcome.lose);
    });

    test('the result is the same from both sides', () {
      const flips = {
        MatchOutcome.win: MatchOutcome.lose,
        MatchOutcome.lose: MatchOutcome.win,
        MatchOutcome.draw: MatchOutcome.draw,
        MatchOutcome.undecided: MatchOutcome.undecided,
      };
      final cases = [
        (alive(3), alive(5)),
        (fell(3), alive(5)),
        (fell(5), alive(3)),
        (fell(4), fell(4)),
        (fell(9), fell(2)),
      ];
      for (final (a, b) in cases) {
        expect(outcomeFor(b, a), flips[outcomeFor(a, b)]);
      }
    });
  });

  test('the same seed gives both players the same cats in order', () {
    List<String> catsFor(int seed) {
      final rng = Random(seed);
      return [
        for (var i = 0; i < 30; i++)
          '${rng.nextBool()}-${CatLook.random(rng).fur.toARGB32()}',
      ];
    }

    expect(catsFor(42), catsFor(42));
    expect(catsFor(42), isNot(catsFor(43)));
  });
}
