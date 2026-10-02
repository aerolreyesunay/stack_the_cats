import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:stack_the_cats/ui/treat_confetti.dart';

void main() {
  testWidgets('treat confetti shows fish, lets taps through, then cleans up', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  taps++;
                  showTreatConfetti(context);
                },
                child: const Text('Go'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Go'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(FaIcon), findsWidgets);

    // The confetti doesn't block taps underneath it.
    await tester.tap(find.text('Go'), warnIfMissed: false);
    expect(taps, 2);

    // The second burst starts on the next frame; both are gone once
    // they've finished.
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.byType(FaIcon), findsNothing);
  });
}
