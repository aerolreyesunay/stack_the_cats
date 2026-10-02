import 'package:flutter_test/flutter_test.dart';
import 'package:stack_the_cats/game/stack_game.dart';

TowerBalance balanceOf(List<double> xs) =>
    TowerBalance.of(xs, baseX: 100, baseHalf: 70, catHalf: 50);

void main() {
  test('a straight tower is fully stable', () {
    final b = balanceOf([100, 100, 100]);
    expect(b.percent, 100);
    expect(b.side, 0);
  });

  test('leaning right: lower stability, would tumble right', () {
    // The top cat sits 25 to the right of the one below: halfway to falling.
    final b = balanceOf([100, 100, 125]);
    expect(b.percent, 50);
    expect(b.side, 1);
  });

  test('the worst level decides, whichever it is', () {
    // Each cat 20 further left. The three cats on the bottom one have
    // their centre at 60, 40 left of it: 80% of the way to falling, worse
    // than any other level.
    final b = balanceOf([100, 80, 60, 40]);
    expect(b.side, -1);
    expect(b.percent, 20);
  });

  test('at the edge of toppling it reads 0%', () {
    expect(balanceOf([100, 150]).percent, 0);
  });

  test('no cats: balanced', () {
    expect(balanceOf([]).percent, 100);
  });
}
