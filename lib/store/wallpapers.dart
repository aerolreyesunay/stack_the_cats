import 'dart:math';

import 'package:flutter/material.dart';

/// The pattern drawn behind the game.
enum WallPattern {
  stripes,
  dots,
  plaid,
  leaves,
  fish,
  stars,
  paws,
  hearts,
  checks,
  crowns,
  blossoms,
}

/// A wallpaper for the game background. All are light, so the brown score
/// and cats always stand out.
class Wallpaper {
  const Wallpaper({
    required this.id,
    required this.name,
    required this.price,
    required this.background,
    required this.ink,
    required this.pattern,
    this.adUnlockable = false,
    this.payoutBonus = false,
  });

  /// Can also be unlocked by watching one video ad instead of paying.
  final bool adUnlockable;

  /// Premium: in a normal game started with this wallpaper, every 50 cats
  /// stacked pays double treats for [PayoutBonus.seconds] seconds.
  final bool payoutBonus;

  final String id;
  final String name;

  /// 0 for the free one.
  final int price;
  final Color background;

  /// The colour of the pattern (usually see-through).
  final Color ink;
  final WallPattern pattern;

  bool get isFree => price == 0;
}

class Wallpapers {
  Wallpapers._();

  static const price = 100;
  static const premiumPrice = 500;

  static const classic = Wallpaper(
    id: 'classic',
    name: 'Cozy Stripes',
    price: 0,
    background: Color(0xFFFDEBD3),
    ink: Color(0x0D8A5A3C),
    pattern: WallPattern.stripes,
  );

  static const all = <Wallpaper>[
    classic,
    Wallpaper(
      id: 'polka',
      name: 'Pink Polka',
      price: price,
      background: Color(0xFFFCE4EC),
      ink: Color(0x55FFFFFF),
      pattern: WallPattern.dots,
      adUnlockable: true,
    ),
    Wallpaper(
      id: 'plaid',
      name: 'Sky Plaid',
      price: price,
      background: Color(0xFFE3F0FA),
      ink: Color(0x1A3A6EA5),
      pattern: WallPattern.plaid,
    ),
    Wallpaper(
      id: 'garden',
      name: 'Mint Garden',
      price: price,
      background: Color(0xFFE6F4E4),
      ink: Color(0x2E4E8A4A),
      pattern: WallPattern.leaves,
      adUnlockable: true,
    ),
    Wallpaper(
      id: 'fishy',
      name: 'Fish Market',
      price: price,
      background: Color(0xFFE0F5F3),
      ink: Color(0x262E8B8B),
      pattern: WallPattern.fish,
    ),
    Wallpaper(
      id: 'dusk',
      name: 'Lavender Dusk',
      price: price,
      background: Color(0xFFEDE7F6),
      ink: Color(0x4D7E57C2),
      pattern: WallPattern.stars,
    ),
    Wallpaper(
      id: 'paws',
      name: 'Paw Prints',
      price: price,
      background: Color(0xFFF5EDE3),
      ink: Color(0x268A5A3C),
      pattern: WallPattern.paws,
      adUnlockable: true,
    ),
    Wallpaper(
      id: 'hearts',
      name: 'Sweet Hearts',
      price: price,
      background: Color(0xFFFFEBEE),
      ink: Color(0x33E57373),
      pattern: WallPattern.hearts,
    ),
    Wallpaper(
      id: 'checks',
      name: 'Butter Checks',
      price: price,
      background: Color(0xFFFFF8E1),
      ink: Color(0x1FE0A030),
      pattern: WallPattern.checks,
    ),
    Wallpaper(
      id: 'crowns',
      name: 'Golden Crowns',
      price: premiumPrice,
      background: Color(0xFFFBF1D3),
      ink: Color(0x40C08A1E),
      pattern: WallPattern.crowns,
      payoutBonus: true,
    ),
    Wallpaper(
      id: 'blossom',
      name: 'Cherry Blossom',
      price: premiumPrice,
      background: Color(0xFFFCE8EF),
      ink: Color(0x4DE68AA8),
      pattern: WallPattern.blossoms,
      payoutBonus: true,
    ),
  ];

  static Wallpaper byId(String? id) {
    for (final w in all) {
      if (w.id == id) return w;
    }
    return classic;
  }
}

/// Paints [wallpaper] over [size]. [scroll] moves the pattern with the
/// tower so it feels attached to the wall.
void paintWallpaper(
  Canvas canvas,
  Size size,
  Wallpaper wallpaper, {
  double scroll = 0,
}) {
  canvas.drawRect(Offset.zero & size, Paint()..color = wallpaper.background);
  final ink = Paint()..color = wallpaper.ink;
  // How far the pattern repeats vertically (so scrolling wraps smoothly).
  const tile = 96.0;
  final shift = scroll % tile;

  switch (wallpaper.pattern) {
    case WallPattern.stripes:
      for (double x = 0; x < size.width; x += 48) {
        canvas.drawRect(Rect.fromLTWH(x, 0, 22, size.height), ink);
      }
    case WallPattern.dots:
      for (double y = -tile + shift; y < size.height + tile; y += 48) {
        final row = ((y - shift) / 48).round();
        for (double x = (row.isEven ? 12 : 36); x < size.width; x += 48) {
          canvas.drawCircle(Offset(x, y), 9, ink);
        }
      }
    case WallPattern.plaid:
      for (double x = 0; x < size.width; x += 64) {
        canvas.drawRect(Rect.fromLTWH(x, 0, 16, size.height), ink);
      }
      for (double y = -tile + shift; y < size.height + tile; y += 64) {
        canvas.drawRect(Rect.fromLTWH(0, y, size.width, 16), ink);
      }
    case WallPattern.leaves:
      for (double y = -tile + shift; y < size.height + tile; y += 72) {
        final row = ((y - shift) / 72).round();
        for (double x = (row.isEven ? 24 : 60); x < size.width; x += 72) {
          _leaf(canvas, Offset(x, y), row.isEven ? 0.5 : -0.5, ink);
        }
      }
    case WallPattern.fish:
      for (double y = -tile + shift; y < size.height + tile; y += 64) {
        final row = ((y - shift) / 64).round();
        for (double x = (row.isEven ? 20 : 52); x < size.width; x += 64) {
          _fish(canvas, Offset(x, y), facingRight: row.isEven, paint: ink);
        }
      }
    case WallPattern.stars:
      final rng = Random(7);
      for (double y = -tile + shift; y < size.height + tile; y += tile) {
        for (var i = 0; i < 6; i++) {
          final x = rng.nextDouble() * size.width;
          final dy = rng.nextDouble() * tile;
          _star(canvas, Offset(x, y + dy), 4 + rng.nextDouble() * 5, ink);
        }
      }
    case WallPattern.paws:
      for (double y = -tile + shift; y < size.height + tile; y += 80) {
        final row = ((y - shift) / 80).round();
        for (double x = (row.isEven ? 26 : 66); x < size.width; x += 80) {
          _paw(canvas, Offset(x, y), row.isEven ? 0.3 : -0.3, ink);
        }
      }
    case WallPattern.hearts:
      for (double y = -tile + shift; y < size.height + tile; y += 48) {
        final row = ((y - shift) / 48).round();
        for (double x = (row.isEven ? 16 : 40); x < size.width; x += 48) {
          _heart(canvas, Offset(x, y), 8, ink);
        }
      }
    case WallPattern.checks:
      for (double y = -tile + shift; y < size.height + tile; y += 32) {
        final row = ((y - shift) / 32).round();
        for (double x = row.isEven ? 0 : 32; x < size.width; x += 64) {
          canvas.drawRect(Rect.fromLTWH(x, y, 32, 32), ink);
        }
      }
    case WallPattern.crowns:
      for (double y = -tile + shift; y < size.height + tile; y += 64) {
        final row = ((y - shift) / 64).round();
        for (double x = (row.isEven ? 28 : 64); x < size.width; x += 72) {
          _crown(canvas, Offset(x, y), ink);
        }
      }
    case WallPattern.blossoms:
      for (double y = -tile + shift; y < size.height + tile; y += 64) {
        final row = ((y - shift) / 64).round();
        for (double x = (row.isEven ? 24 : 58); x < size.width; x += 68) {
          _blossom(canvas, Offset(x, y), row.isEven ? 9 : 6.5, ink);
        }
      }
  }
}

void _leaf(Canvas canvas, Offset at, double angle, Paint paint) {
  canvas.save();
  canvas.translate(at.dx, at.dy);
  canvas.rotate(angle);
  final path = Path()
    ..moveTo(0, -14)
    ..quadraticBezierTo(11, 0, 0, 14)
    ..quadraticBezierTo(-11, 0, 0, -14);
  canvas.drawPath(path, paint);
  canvas.restore();
}

void _fish(
  Canvas canvas,
  Offset at, {
  required bool facingRight,
  required Paint paint,
}) {
  canvas.save();
  canvas.translate(at.dx, at.dy);
  if (!facingRight) canvas.scale(-1, 1);
  canvas.drawOval(
    Rect.fromCenter(center: Offset.zero, width: 22, height: 12),
    paint,
  );
  final tail = Path()
    ..moveTo(-9, 0)
    ..lineTo(-17, -7)
    ..lineTo(-17, 7)
    ..close();
  canvas.drawPath(tail, paint);
  canvas.restore();
}

void _star(Canvas canvas, Offset at, double r, Paint paint) {
  final path = Path();
  for (var i = 0; i < 8; i++) {
    final radius = i.isEven ? r : r * 0.4;
    final a = -pi / 2 + i * pi / 4;
    final p = at + Offset(cos(a) * radius, sin(a) * radius);
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  canvas.drawPath(path..close(), paint);
}

void _paw(Canvas canvas, Offset at, double angle, Paint paint) {
  canvas.save();
  canvas.translate(at.dx, at.dy);
  canvas.rotate(angle);
  canvas.drawOval(
    Rect.fromCenter(center: const Offset(0, 5), width: 16, height: 13),
    paint,
  );
  for (final (dx, dy) in [
    (-9.0, -5.0),
    (-3.0, -10.0),
    (3.0, -10.0),
    (9.0, -5.0),
  ]) {
    canvas.drawCircle(Offset(dx, dy), 3.4, paint);
  }
  canvas.restore();
}

void _heart(Canvas canvas, Offset at, double r, Paint paint) {
  final path = Path()
    ..moveTo(at.dx, at.dy + r)
    ..cubicTo(
      at.dx - r * 1.6,
      at.dy - r * 0.2,
      at.dx - r * 0.6,
      at.dy - r * 1.4,
      at.dx,
      at.dy - r * 0.45,
    )
    ..cubicTo(
      at.dx + r * 0.6,
      at.dy - r * 1.4,
      at.dx + r * 1.6,
      at.dy - r * 0.2,
      at.dx,
      at.dy + r,
    )
    ..close();
  canvas.drawPath(path, paint);
}

void _crown(Canvas canvas, Offset at, Paint paint) {
  canvas.save();
  canvas.translate(at.dx, at.dy);
  final path = Path()
    ..moveTo(-13, 8)
    ..lineTo(-15, -6)
    ..lineTo(-7, 0)
    ..lineTo(0, -10)
    ..lineTo(7, 0)
    ..lineTo(15, -6)
    ..lineTo(13, 8)
    ..close()
    ..addRect(const Rect.fromLTWH(-13, 10, 26, 3.5));
  for (final x in [-15.0, 0.0, 15.0]) {
    path.addOval(
      Rect.fromCircle(center: Offset(x, x == 0 ? -12 : -8), radius: 2.6),
    );
  }
  // One path, so the see-through ink doesn't darken where shapes meet.
  canvas.drawPath(path, paint);
  canvas.restore();
}

void _blossom(Canvas canvas, Offset at, double r, Paint paint) {
  // Five petals as one path, so the see-through ink doesn't darken where
  // they overlap.
  final path = Path();
  for (var i = 0; i < 5; i++) {
    final a = -pi / 2 + i * 2 * pi / 5;
    path.addOval(
      Rect.fromCircle(
        center: at + Offset(cos(a) * r * 0.62, sin(a) * r * 0.62),
        radius: r * 0.5,
      ),
    );
  }
  canvas.drawPath(path, paint);
}
