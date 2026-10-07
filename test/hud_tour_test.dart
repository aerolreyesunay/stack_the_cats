import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stack_the_cats/ui/hud_button.dart';
import 'package:stack_the_cats/ui/hud_tour.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the tour remembers which buttons were explained', () async {
    expect(await HudTour.seen(), isEmpty);
    await HudTour.markSeen(['home', 'settings']);
    await HudTour.markSeen(['settings', 'store']);
    expect(await HudTour.seen(), {'home', 'settings', 'store'});
  });

  Future<void> pumpTour(
    WidgetTester tester, {
    required void Function() onFinished,
    required void Function() onButton,
  }) {
    final a = GlobalKey();
    final b = GlobalKey();
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                top: 10,
                left: 10,
                child: HudButton(
                  key: a,
                  icon: Icons.home_rounded,
                  tooltip: 'Home',
                  onPressed: onButton,
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: HudButton(
                  key: b,
                  icon: Icons.storefront_rounded,
                  tooltip: 'Store',
                  accent: true,
                  onPressed: onButton,
                ),
              ),
              Positioned.fill(
                child: HudTour(
                  steps: [
                    HudTourStep(
                      id: 'a',
                      target: a,
                      title: 'First',
                      body: 'One',
                    ),
                    HudTourStep(
                      id: 'b',
                      target: b,
                      title: 'Second',
                      body: 'Two',
                    ),
                  ],
                  onFinished: onFinished,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('Next walks through the steps, then finishes', (tester) async {
    var finished = 0;
    var buttonTaps = 0;
    await pumpTour(
      tester,
      onFinished: () => finished++,
      onButton: () => buttonTaps++,
    );
    await tester.pump();
    expect(find.text('First'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);

    // The game's buttons can't be pressed while the tour is up.
    await tester.tap(find.byTooltip('Home'), warnIfMissed: false);
    expect(buttonTaps, 0);

    await tester.tap(find.text('Next'));
    // (The old card fades out first.)
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('Skip'), findsNothing);

    await tester.tap(find.text("Let's stack!"));
    expect(finished, 1);
  });

  testWidgets('Skip ends the tour straight away', (tester) async {
    var finished = 0;
    await pumpTour(tester, onFinished: () => finished++, onButton: () {});
    await tester.pump();
    await tester.tap(find.text('Skip'));
    expect(finished, 1);
  });

  testWidgets('the attention pulse starts and stops', (tester) async {
    Widget pulse(bool active) => MaterialApp(
      home: Center(
        child: AttentionPulse(
          active: active,
          child: const SizedBox(width: 40, height: 40),
        ),
      ),
    );
    double scale() => tester
        .widget<Transform>(find.byType(Transform).first)
        .transform
        .getMaxScaleOnAxis();

    await tester.pumpWidget(pulse(true));
    await tester.pump(const Duration(milliseconds: 375));
    expect(scale(), greaterThan(1.0));

    await tester.pumpWidget(pulse(false));
    await tester.pumpAndSettle();
    expect(scale(), 1.0);
  });
}
