import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stack_the_cats/store/catalog.dart';
import 'package:stack_the_cats/ui/share_result.dart';

void main() {
  test('gold, silver and bronze for the top three, then the top 20', () {
    expect(shareTierFor(1), ShareTier.gold);
    expect(shareTierFor(2), ShareTier.silver);
    expect(shareTierFor(3), ShareTier.bronze);
    expect(shareTierFor(4), ShareTier.top20);
    expect(shareTierFor(20), ShareTier.top20);
    expect(shareTierFor(21), ShareTier.none);
    expect(shareTierFor(null), ShareTier.none);
  });

  test('the share text mentions the rank only in the top 20', () {
    expect(shareText(score: 142, rank: 2), startsWith("I'm #2 on this week's"));
    expect(shareText(score: 1, rank: 50), startsWith('I stacked 1 cat '));
  });

  testWidgets('every card fits its 1080 × 1350 picture', (tester) async {
    for (final rank in [1, 2, 3, 7, null]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: ShareCard(
              score: 1234,
              name: 'Maximiliano Q.',
              rank: rank,
              pool: Cats.all,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'rank $rank');
      expect(tester.getSize(find.byType(ShareCard)), ShareCard.size);
    }
  });
}
