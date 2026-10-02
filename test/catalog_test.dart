import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:stack_the_cats/game/cat.dart';
import 'package:stack_the_cats/store/catalog.dart';
import 'package:stack_the_cats/store/wallpapers.dart';

void main() {
  test('everyone starts with exactly 2 basic cats: Ginger and Grey', () {
    expect(Cats.basic.map((c) => c.id), ['ginger', 'grey']);
  });

  test('cat ids are unique and prices match the tier', () {
    expect(Cats.all.map((c) => c.id).toSet().length, Cats.all.length);
    for (final c in Cats.all) {
      expect(c.price, switch (c.tier) {
        CatTier.basic => 0,
        CatTier.special => 100,
        CatTier.exotic => 300,
      });
    }
  });

  test('the old colours are now Special cats in the Store', () {
    for (final id in ['black', 'white', 'cream', 'brown']) {
      expect(Cats.byId(id)!.tier, CatTier.special);
    }
  });

  test('a player gets their basic cats plus whatever they bought', () {
    final pool = Cats.ownedBy(['siamese', 'nonsense']);
    expect(pool.map((c) => c.id), ['ginger', 'grey', 'siamese']);
  });

  test('new cats only come from the cats a player owns', () {
    final pool = Cats.ownedBy(['bengal']);
    final rng = Random(3);
    for (var i = 0; i < 200; i++) {
      expect(pool, contains(CatLook.random(rng, pool).breed));
    }
  });

  test('wallpapers: one free, the rest 100, unique ids', () {
    expect(Wallpapers.all.where((w) => w.isFree), [Wallpapers.classic]);
    expect(
      Wallpapers.all.map((w) => w.id).toSet().length,
      Wallpapers.all.length,
    );
    for (final w in Wallpapers.all.where((w) => !w.isFree)) {
      expect(w.price, 100);
    }
    expect(Wallpapers.byId('unknown'), Wallpapers.classic);
  });
}
