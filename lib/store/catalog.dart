import 'package:flutter/material.dart';

/// How rare (and how rewarding) a cat is.
enum CatTier {
  /// Free for everyone.
  basic,

  /// 100 treats: +1 treat on a Purrfect landing, +3 during a streak.
  special,

  /// 300 treats: +5 treats on a Purrfect landing, double during a streak.
  exotic;

  int get price => switch (this) {
    CatTier.basic => 0,
    CatTier.special => 100,
    CatTier.exotic => 300,
  };

  String get label => switch (this) {
    CatTier.basic => 'Basic',
    CatTier.special => 'Special',
    CatTier.exotic => 'Exotic',
  };

  /// What the cat's tier adds, for the Store.
  String get perk => switch (this) {
    CatTier.basic => '',
    CatTier.special => '+1 treat on every Purrfect, +3 in a streak',
    CatTier.exotic => '+5 treats on every Purrfect, 2× in a streak',
  };
}

/// The markings drawn on a cat's body.
enum CatPattern {
  /// One colour (may still get tabby stripes, see [CatBreed.stripes]).
  plain,

  /// Siamese: dark ears, face mask, paws and tail.
  points,

  /// Orange and black patches on white.
  calico,

  /// Black with a white chest, muzzle and paws.
  tuxedo,

  /// Bengal rosettes.
  spots,

  /// Sphynx: no fur, a few wrinkles.
  hairless,
}

enum CatEars { pointed, folded, tufted }

/// When a breed has tabby stripes.
enum Stripes { never, sometimes, always }

/// One cat design that can drop in a game.
class CatBreed {
  const CatBreed({
    required this.id,
    required this.name,
    required this.tier,
    required this.fur,
    required this.marking,
    required this.eye,
    this.pattern = CatPattern.plain,
    this.ears = CatEars.pointed,
    this.stripes = Stripes.never,
    this.fluffy = false,
  });

  final String id;
  final String name;
  final CatTier tier;

  /// Main fur colour.
  final Color fur;

  /// Stripes, points, patches or spots.
  final Color marking;
  final Color eye;
  final CatPattern pattern;
  final CatEars ears;
  final Stripes stripes;

  /// Big fluffy tail (Maine Coon).
  final bool fluffy;

  int get price => tier.price;
  bool get isBasic => tier == CatTier.basic;
}

/// Every cat in the game, in Store order.
class Cats {
  Cats._();

  // ---------- Basic (everyone has these) ----------
  static const ginger = CatBreed(
    id: 'ginger',
    name: 'Ginger Tabby',
    tier: CatTier.basic,
    fur: Color(0xFFF4A259),
    marking: Color(0xFFD9782D),
    eye: Color(0xFF3B2A1A),
    stripes: Stripes.sometimes,
  );
  static const grey = CatBreed(
    id: 'grey',
    name: 'Grey',
    tier: CatTier.basic,
    fur: Color(0xFF9AA5B1),
    marking: Color(0xFF6E7A87),
    eye: Color(0xFF2B2B2B),
    stripes: Stripes.sometimes,
  );

  // ---------- Special (100 treats) ----------
  static const black = CatBreed(
    id: 'black',
    name: 'Black Cat',
    tier: CatTier.special,
    fur: Color(0xFF3D3D3D),
    marking: Color(0xFF2A2A2A),
    eye: Color(0xFFF2D14B),
  );
  static const white = CatBreed(
    id: 'white',
    name: 'Snow White',
    tier: CatTier.special,
    fur: Color(0xFFF7F4EF),
    marking: Color(0xFFE2DBD0),
    eye: Color(0xFF4A7FB5),
  );
  static const cream = CatBreed(
    id: 'cream',
    name: 'Cream Tabby',
    tier: CatTier.special,
    fur: Color(0xFFEBD8B7),
    marking: Color(0xFFCDB38A),
    eye: Color(0xFF3B2A1A),
    stripes: Stripes.sometimes,
  );
  static const brown = CatBreed(
    id: 'brown',
    name: 'Chocolate',
    tier: CatTier.special,
    fur: Color(0xFF8D6346),
    marking: Color(0xFF6B4630),
    eye: Color(0xFF7CB342),
    stripes: Stripes.sometimes,
  );
  static const tuxedo = CatBreed(
    id: 'tuxedo',
    name: 'Tuxedo',
    tier: CatTier.special,
    fur: Color(0xFF2F2F33),
    marking: Color(0xFFF7F4EF),
    eye: Color(0xFF8BC34A),
    pattern: CatPattern.tuxedo,
  );
  static const russianBlue = CatBreed(
    id: 'russianBlue',
    name: 'Russian Blue',
    tier: CatTier.special,
    fur: Color(0xFF7D8DA6),
    marking: Color(0xFF66768F),
    eye: Color(0xFF6FCF6F),
  );
  static const calico = CatBreed(
    id: 'calico',
    name: 'Calico',
    tier: CatTier.special,
    fur: Color(0xFFF7F1E6),
    marking: Color(0xFFE58A3A),
    eye: Color(0xFF3B2A1A),
    pattern: CatPattern.calico,
  );

  // ---------- Exotic (300 treats) ----------
  static const siamese = CatBreed(
    id: 'siamese',
    name: 'Siamese',
    tier: CatTier.exotic,
    fur: Color(0xFFF1E3CC),
    marking: Color(0xFF5A4032),
    eye: Color(0xFF3F8EE0),
    pattern: CatPattern.points,
  );
  static const bengal = CatBreed(
    id: 'bengal',
    name: 'Bengal',
    tier: CatTier.exotic,
    fur: Color(0xFFE2A25A),
    marking: Color(0xFF6B3F1E),
    eye: Color(0xFF7CB342),
    pattern: CatPattern.spots,
  );
  static const scottishFold = CatBreed(
    id: 'scottishFold',
    name: 'Scottish Fold',
    tier: CatTier.exotic,
    fur: Color(0xFFB9BEC6),
    marking: Color(0xFF8E949E),
    eye: Color(0xFFE7A33E),
    ears: CatEars.folded,
    stripes: Stripes.always,
  );
  static const maineCoon = CatBreed(
    id: 'maineCoon',
    name: 'Maine Coon',
    tier: CatTier.exotic,
    fur: Color(0xFF9C6B45),
    marking: Color(0xFF5E3D25),
    eye: Color(0xFFD9B23A),
    ears: CatEars.tufted,
    stripes: Stripes.always,
    fluffy: true,
  );
  static const sphynx = CatBreed(
    id: 'sphynx',
    name: 'Sphynx',
    tier: CatTier.exotic,
    fur: Color(0xFFF2C9B8),
    marking: Color(0xFFD9A592),
    eye: Color(0xFF5AB3A8),
    pattern: CatPattern.hairless,
  );

  static const all = <CatBreed>[
    ginger,
    grey,
    black,
    white,
    cream,
    brown,
    tuxedo,
    russianBlue,
    calico,
    siamese,
    bengal,
    scottishFold,
    maineCoon,
    sphynx,
  ];

  static final basic = [
    for (final c in all)
      if (c.isBasic) c,
  ];

  static CatBreed? byId(String id) {
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// The cats a player can get in a game: the basic ones plus any bought.
  static List<CatBreed> ownedBy(Iterable<String> boughtIds) {
    final bought = boughtIds.toSet();
    return [
      for (final c in all)
        if (c.isBasic || bought.contains(c.id)) c,
    ];
  }
}
