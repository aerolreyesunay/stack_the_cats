import 'dart:math';

import 'package:flutter/material.dart';

import '../store/catalog.dart';

/// How one cat looks: its breed plus a few random touches.
class CatLook {
  const CatLook({
    required this.breed,
    required this.striped,
    required this.tailRight,
    required this.sleepy,
  });

  final CatBreed breed;
  final bool striped;
  final bool tailRight;
  final bool sleepy;

  Color get fur => breed.fur;
  Color get stripe => breed.marking;
  Color get eye => breed.eye;

  bool get isDark => fur.computeLuminance() < 0.15;

  /// A random cat from [pool] (the basic cats if not given). Always uses the
  /// random generator the same number of times, so two players with the
  /// same seed and pool get exactly the same cats.
  static CatLook random(Random rng, [List<CatBreed>? pool]) {
    final cats = (pool == null || pool.isEmpty) ? Cats.basic : pool;
    final breed = cats[rng.nextInt(cats.length)];
    final stripeRoll = rng.nextDouble();
    return CatLook(
      breed: breed,
      striped: switch (breed.stripes) {
        Stripes.never => false,
        Stripes.sometimes => stripeRoll < 0.45,
        Stripes.always => true,
      },
      tailRight: rng.nextBool(),
      sleepy: rng.nextDouble() < 0.25,
    );
  }
}

/// One cat in the game. Position is the center of its body.
class Cat {
  Cat({required this.x, required this.y, required this.look});

  double x;
  double y;
  double vx = 0;
  double vy = 0;
  double angle = 0;
  double spin = 0;
  double squash = 0; // 1 right after landing, fades to 0
  final CatLook look;
}

const _white = Color(0xFFF7F4EF);
const _calicoBlack = Color(0xFF3A3A3A);
const _innerEar = Color(0xFFF4A6A6);

/// Draws a loaf-shaped cat centered at [center]. No image files needed.
void paintCat(
  Canvas canvas,
  CatLook look,
  Offset center,
  double w,
  double h, {
  double angle = 0,
  double squash = 0,
}) {
  final breed = look.breed;
  final pattern = breed.pattern;

  canvas.save();
  canvas.translate(center.dx, center.dy);
  if (angle != 0) canvas.rotate(angle);
  if (squash > 0) {
    // Squish down from the bottom when landing
    final s = squash * 0.14;
    canvas.translate(0, h / 2);
    canvas.scale(1 + s, 1 - s);
    canvas.translate(0, -h / 2);
  }

  final fur = Paint()..color = look.fur;
  final marking = Paint()..color = look.stripe;
  final detail = look.isDark
      ? const Color(0x99FFFFFF)
      : const Color(0x88000000);

  // Tail (behind the body). Siamese and calico tails are darker; the Maine
  // Coon's is big and fluffy.
  final side = look.tailRight ? 1.0 : -1.0;
  final tailColor = switch (pattern) {
    CatPattern.points => look.stripe,
    CatPattern.calico => _calicoBlack,
    _ => look.fur,
  };
  final tail = Path()
    ..moveTo(side * (w / 2 - h * 0.15), h * 0.25)
    ..quadraticBezierTo(
      side * (w / 2 + h * 0.45),
      h * 0.2,
      side * (w / 2 + h * 0.3),
      -h * 0.35,
    );
  canvas.drawPath(
    tail,
    Paint()
      ..color = tailColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * (breed.fluffy ? 0.3 : 0.16)
      ..strokeCap = StrokeCap.round,
  );
  if (breed.fluffy) {
    // A darker ring near the tip.
    canvas.drawCircle(
      Offset(side * (w / 2 + h * 0.31), -h * 0.3),
      h * 0.13,
      marking,
    );
  }

  // Ears
  final earScale = pattern == CatPattern.hairless ? 1.15 : 1.0;
  final earXs = [-w * 0.27, w * 0.27];
  for (var i = 0; i < earXs.length; i++) {
    final ex = earXs[i];
    final earPaint = switch (pattern) {
      CatPattern.points => marking,
      // One orange ear, one black ear.
      CatPattern.calico => Paint()..color = i == 0 ? look.stripe : _calicoBlack,
      _ => fur,
    };
    switch (breed.ears) {
      case CatEars.folded:
        // Little flaps folded forward.
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(ex, -h * 0.4),
            width: h * 0.42,
            height: h * 0.26,
          ),
          earPaint,
        );
      case CatEars.pointed:
      case CatEars.tufted:
        final tip = breed.ears == CatEars.tufted ? 0.95 : 0.82 * earScale;
        final half = 0.24 * earScale;
        final ear = Path()
          ..moveTo(ex - h * half, -h * 0.3)
          ..lineTo(ex, -h * tip)
          ..lineTo(ex + h * half, -h * 0.3)
          ..close();
        canvas.drawPath(ear, earPaint);
        final inner = Path()
          ..moveTo(ex - h * 0.12, -h * 0.38)
          ..lineTo(ex, -h * (tip - 0.14))
          ..lineTo(ex + h * 0.12, -h * 0.38)
          ..close();
        canvas.drawPath(inner, Paint()..color = _innerEar);
        if (breed.ears == CatEars.tufted) {
          // Lynx tufts.
          canvas.drawLine(
            Offset(ex, -h * tip),
            Offset(ex + h * 0.04, -h * (tip + 0.16)),
            Paint()
              ..color = look.stripe
              ..strokeWidth = h * 0.05
              ..strokeCap = StrokeCap.round,
          );
        }
    }
  }

  // Body
  final body = RRect.fromRectAndRadius(
    Rect.fromCenter(center: Offset.zero, width: w, height: h),
    Radius.circular(h * 0.42),
  );
  canvas.drawRRect(body, fur);

  // Markings, kept inside the body outline.
  canvas.save();
  canvas.clipRRect(body);
  switch (pattern) {
    case CatPattern.calico:
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(-w * 0.3, -h * 0.18),
          width: w * 0.38,
          height: h * 0.62,
        ),
        marking,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(w * 0.3, h * 0.12),
          width: w * 0.34,
          height: h * 0.55,
        ),
        Paint()..color = _calicoBlack,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(w * 0.08, -h * 0.44),
          width: w * 0.2,
          height: h * 0.24,
        ),
        marking,
      );
    case CatPattern.tuxedo:
      // White chest and muzzle.
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(0, h * 0.45),
          width: w * 0.46,
          height: h * 0.62,
        ),
        marking,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(0, h * 0.11),
          width: w * 0.3,
          height: h * 0.26,
        ),
        marking,
      );
    case CatPattern.points:
      // Dark face mask.
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(0, h * 0.04),
          width: w * 0.44,
          height: h * 0.5,
        ),
        Paint()..color = look.stripe.withAlpha(215),
      );
    case CatPattern.spots:
      final spot = Paint()
        ..color = look.stripe
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.045;
      for (final (sx, sy, r) in [
        (-0.38, -0.2, 0.07),
        (-0.3, 0.2, 0.06),
        (-0.22, -0.38, 0.05),
        (0.3, -0.22, 0.07),
        (0.38, 0.18, 0.06),
        (0.22, 0.36, 0.05),
        (-0.05, -0.4, 0.045),
      ]) {
        canvas.drawCircle(Offset(w * sx, h * sy), h * r, spot);
      }
    case CatPattern.hairless:
      // Forehead wrinkles.
      final wrinkle = Paint()
        ..color = look.stripe
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.035
        ..strokeCap = StrokeCap.round;
      for (final y in [-0.4, -0.3]) {
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset(0, h * y + h * 0.08),
            width: w * 0.28,
            height: h * 0.18,
          ),
          pi * 1.15,
          pi * 0.7,
          false,
          wrinkle,
        );
      }
    case CatPattern.plain:
      break;
  }
  canvas.restore();

  canvas.drawRRect(
    body,
    Paint()
      ..color = const Color(0x33000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2,
  );

  // Stripes
  if (look.striped) {
    final sp = Paint()
      ..color = look.stripe
      ..strokeWidth = h * 0.07
      ..strokeCap = StrokeCap.round;
    for (final sx in [-w * 0.1, 0.0, w * 0.1]) {
      canvas.drawLine(Offset(sx, -h * 0.44), Offset(sx, -h * 0.3), sp);
    }
    for (final s in [-1.0, 1.0]) {
      canvas.drawLine(
        Offset(s * w * 0.45, -h * 0.05),
        Offset(s * w * 0.35, -h * 0.05),
        sp,
      );
      canvas.drawLine(
        Offset(s * w * 0.45, h * 0.13),
        Offset(s * w * 0.35, h * 0.13),
        sp,
      );
    }
  }

  // Paws
  final pawPaint = Paint()
    ..color = switch (pattern) {
      CatPattern.points => Color.lerp(look.stripe, Colors.white, 0.15)!,
      CatPattern.tuxedo => _white,
      _ => Color.lerp(look.fur, Colors.white, 0.35)!,
    };
  for (final px in [-w * 0.2, w * 0.2]) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(px, h * 0.43),
        width: h * 0.34,
        height: h * 0.2,
      ),
      pawPaint,
    );
  }

  // Eyes
  final eyeY = -h * 0.08;
  final eyeDX = w * 0.14;
  final darkFace = look.isDark || pattern == CatPattern.points;
  for (final ex in [-eyeDX, eyeDX]) {
    if (look.sleepy) {
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(ex, eyeY),
          width: h * 0.2,
          height: h * 0.14,
        ),
        0,
        pi,
        false,
        Paint()
          ..color = darkFace ? look.eye : const Color(0xFF2B2B2B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = h * 0.05
          ..strokeCap = StrokeCap.round,
      );
    } else {
      canvas.drawCircle(Offset(ex, eyeY), h * 0.085, Paint()..color = look.eye);
      canvas.drawCircle(
        Offset(ex + h * 0.03, eyeY - h * 0.03),
        h * 0.028,
        Paint()..color = Colors.white,
      );
    }
  }

  // Nose
  final nose = Path()
    ..moveTo(-h * 0.05, h * 0.05)
    ..lineTo(h * 0.05, h * 0.05)
    ..lineTo(0, h * 0.1)
    ..close();
  canvas.drawPath(nose, Paint()..color = const Color(0xFFE88A9A));

  // Mouth and whiskers (light on dark faces so they show).
  final lines = darkFace ? const Color(0x99FFFFFF) : detail;
  final mouth = Path()
    ..moveTo(0, h * 0.1)
    ..quadraticBezierTo(-h * 0.04, h * 0.17, -h * 0.09, h * 0.13)
    ..moveTo(0, h * 0.1)
    ..quadraticBezierTo(h * 0.04, h * 0.17, h * 0.09, h * 0.13);
  canvas.drawPath(
    mouth,
    Paint()
      ..color = lines
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round,
  );

  final whisker = Paint()
    ..color = lines
    ..strokeWidth = 1.2;
  for (final s in [-1.0, 1.0]) {
    canvas.drawLine(
      Offset(s * w * 0.1, h * 0.08),
      Offset(s * w * 0.3, h * 0.03),
      whisker,
    );
    canvas.drawLine(
      Offset(s * w * 0.1, h * 0.12),
      Offset(s * w * 0.3, h * 0.15),
      whisker,
    );
  }

  canvas.restore();
}
