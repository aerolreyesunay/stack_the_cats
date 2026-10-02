import 'package:flutter_test/flutter_test.dart';
import 'package:stack_the_cats/game/stack_game.dart';

void main() {
  test('starts at 200 and steps up by 24 every 20 cats', () {
    expect(StackGame.swingSpeedFor(0), 200);
    expect(StackGame.swingSpeedFor(19), 200);
    expect(StackGame.swingSpeedFor(20), 224);
    expect(StackGame.swingSpeedFor(39), 224);
    expect(StackGame.swingSpeedFor(40), 248);
    expect(StackGame.swingSpeedFor(100), 320);
    expect(StackGame.swingSpeedFor(250), 488);
  });

  test('top speed of 800 is reached at 500 cats', () {
    expect(StackGame.swingSpeedFor(480), 776);
    expect(StackGame.swingSpeedFor(499), 776);
    expect(StackGame.swingSpeedFor(500), 800);
    expect(StackGame.swingSpeedFor(5000), 800);
  });

  test('every step is the same size', () {
    final steps = <double>{};
    for (var cats = 20; cats <= 500; cats += 20) {
      steps.add(
        StackGame.swingSpeedFor(cats) - StackGame.swingSpeedFor(cats - 20),
      );
    }
    expect(steps, {24});
  });

  test('speed never goes past the top speed', () {
    var previous = 0.0;
    for (var score = 0; score <= 2000; score++) {
      final speed = StackGame.swingSpeedFor(score);
      expect(speed, greaterThanOrEqualTo(previous));
      expect(speed, lessThanOrEqualTo(StackGame.maxSwingSpeed));
      previous = speed;
    }
  });
}
