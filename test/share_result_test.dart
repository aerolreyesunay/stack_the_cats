import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stack_the_cats/services/leaderboard_service.dart';
import 'package:stack_the_cats/services/public_name.dart';
import 'package:stack_the_cats/store/catalog.dart';
import 'package:stack_the_cats/ui/share_result.dart';

void main() {
  test('a game is shared without a rank', () {
    expect(shareText(score: 142), startsWith('I stacked 142 cats '));
    expect(shareText(score: 1), startsWith('I stacked 1 cat '));
  });

  test('leaderboard posters say which board', () {
    expect(
      rankShareText(board: Board.weekly, rank: 3, best: 120),
      startsWith(
        "I'm #3 on this week's Stack the Cats leaderboard with 120 cats!",
      ),
    );
    expect(
      rankShareText(board: Board.allTime, rank: 57, best: 1),
      startsWith("I'm #57 of all time in Stack the Cats with 1 cat!"),
    );
  });

  test('pictures show the first name only', () {
    expect(firstName('Aerol Reyes Unay'), 'Aerol');
    expect(firstName('  Madonna '), 'Madonna');
    expect(firstName(''), 'Cat stacker');
    expect(firstName(null), 'Cat stacker');
  });

  test('the weekly poster shows Monday to Sunday', () {
    expect(weekRangeLabel(DateTime.utc(2026, 10, 14)), 'Oct 12 – Oct 18');
    expect(weekRangeLabel(DateTime.utc(2026, 12, 31)), 'Dec 28 – Jan 3');
  });

  testWidgets('the game card fits its 1080 × 1350 picture', (tester) async {
    for (final score in [1, 142, 12345]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: ShareCard(score: score, name: 'Maximiliano', pool: Cats.all),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'score $score');
      expect(tester.getSize(find.byType(ShareCard)), ShareCard.size);
    }
  });

  testWidgets('every poster fits its picture', (tester) async {
    for (final board in Board.values) {
      for (final rank in [1, 2, 3, 12, 1234]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: RankPoster(
                board: board,
                rank: rank,
                best: 4321,
                name: 'Maximiliano',
                pool: Cats.all,
                now: DateTime.utc(2026, 10, 14),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: '$board #$rank');
      }
    }
  });
}
