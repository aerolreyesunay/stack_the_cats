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
        CatTier.special => 300,
        CatTier.exotic => 500,
      });
    }
  });

  test('two cats per paid tier unlock with videos: 3 Special, 5 Exotic', () {
    for (final tier in [CatTier.special, CatTier.exotic]) {
      expect(Cats.all.where((c) => c.tier == tier && c.adUnlockable).length, 2);
    }
    expect(Cats.all.where((c) => c.isBasic && c.adUnlockable), isEmpty);
    expect(CatTier.special.adVideos, 3);
    expect(CatTier.exotic.adVideos, 5);
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

  test('wallpapers: one free, 2 premium at 500, the rest 100', () {
    expect(Wallpapers.all.where((w) => w.isFree), [Wallpapers.classic]);
    expect(
      Wallpapers.all.map((w) => w.id).toSet().length,
      Wallpapers.all.length,
    );
    final premium = Wallpapers.all.where((w) => w.payoutBonus).toList();
    expect(premium.map((w) => w.id), ['crowns', 'blossom']);
    for (final w in Wallpapers.all.where((w) => !w.isFree)) {
      expect(w.price, w.payoutBonus ? 500 : 100);
      expect(w.payoutBonus && w.adUnlockable, isFalse);
    }
    expect(Wallpapers.byId('unknown'), Wallpapers.classic);
  });
}
