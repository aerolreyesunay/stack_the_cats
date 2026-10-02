import 'package:flutter_test/flutter_test.dart';
import 'package:stack_the_cats/ads/ad_pacing.dart';

void main() {
  final t0 = DateTime(2026, 10, 1, 12);

  test('an ad is due after every 3 games', () {
    final pacing = AdPacing();
    expect(pacing.gamesBetweenAds, 3);
    for (var i = 0; i < 2; i++) {
      pacing.gameFinished();
      expect(pacing.isDue(t0), isFalse);
    }
    pacing.gameFinished();
    expect(pacing.isDue(t0), isTrue);
  });

  test('showing an ad starts the count again', () {
    final pacing = AdPacing();
    for (var i = 0; i < 3; i++) {
      pacing.gameFinished();
    }
    pacing.adShown(t0);
    expect(pacing.isDue(t0), isFalse);
    expect(pacing.gamesSinceAd, 0);
  });

  test('never two ads within 90 seconds, even after 3 quick games', () {
    final pacing = AdPacing();
    for (var i = 0; i < 3; i++) {
      pacing.gameFinished();
    }
    pacing.adShown(t0);
    for (var i = 0; i < 3; i++) {
      pacing.gameFinished();
    }
    expect(pacing.isDue(t0.add(const Duration(seconds: 60))), isFalse);
    expect(pacing.isDue(t0.add(const Duration(seconds: 90))), isTrue);
  });
}
