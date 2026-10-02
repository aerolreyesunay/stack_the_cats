import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../economy/treats.dart';
import '../services/player_service.dart';

const treatColor = Color(0xFFE76F51);
const _brown = Color(0xFF5B3A29);

/// The fish that stands for a treat.
class TreatIcon extends StatelessWidget {
  const TreatIcon({super.key, this.size = 18, this.color = treatColor});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      FaIcon(FontAwesomeIcons.fish, size: size, color: color);
}

/// "🐟 250" — an amount of treats, e.g. a price.
class TreatAmount extends StatelessWidget {
  const TreatAmount(
    this.amount, {
    super.key,
    this.size = 16,
    this.color = treatColor,
  });

  final int amount;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TreatIcon(size: size, color: color),
        SizedBox(width: size * 0.35),
        Text(
          '$amount',
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// The signed-in player's live balance in a pill: treats, Tuna and
/// Salmon. Hidden when signed out.
class TreatBalance extends StatelessWidget {
  const TreatBalance({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlayerData?>(
      valueListenable: PlayerService.instance.player,
      builder: (context, player, _) {
        if (player == null) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _brown.withAlpha(40)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TreatAmount(player.treats, color: _brown),
              const SizedBox(width: 10),
              FishAmount(Fish.tuna, player.tuna, color: _brown),
              const SizedBox(width: 10),
              FishAmount(Fish.salmon, player.salmon, color: _brown),
            ],
          ),
        );
      },
    );
  }
}

/// A Tuna (a can) or a Salmon (a steak).
class FishIcon extends StatelessWidget {
  const FishIcon(this.fish, {super.key, this.size = 18});

  final Fish fish;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: fish == Fish.tuna
            ? const _TunaPainter()
            : const _SalmonPainter(),
      ),
    );
  }
}

/// "🥫 2" — a number of Tuna or Salmon.
class FishAmount extends StatelessWidget {
  const FishAmount(
    this.fish,
    this.amount, {
    super.key,
    this.size = 16,
    this.color = _brown,
  });

  final Fish fish;
  final int amount;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FishIcon(fish, size: size * 1.15),
        SizedBox(width: size * 0.3),
        Text(
          '$amount',
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// A blue tin of tuna with a silver lid and a little fish on the label.
class _TunaPainter extends CustomPainter {
  const _TunaPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final body = Rect.fromLTWH(w * 0.06, h * 0.3, w * 0.88, h * 0.58);
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, Radius.circular(w * 0.12)),
      Paint()..color = const Color(0xFF2F6DB5),
    );
    // Label band.
    canvas.drawRect(
      Rect.fromLTWH(body.left, h * 0.46, body.width, h * 0.26),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    // Fish on the label.
    final fish = Paint()..color = const Color(0xFF2F6DB5);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.46, h * 0.59),
        width: w * 0.36,
        height: h * 0.15,
      ),
      fish,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.62, h * 0.59)
        ..lineTo(w * 0.76, h * 0.5)
        ..lineTo(w * 0.76, h * 0.68)
        ..close(),
      fish,
    );
    // Silver lid.
    canvas.drawOval(
      Rect.fromLTWH(w * 0.06, h * 0.16, w * 0.88, h * 0.28),
      Paint()..color = const Color(0xFFB8C4CF),
    );
    canvas.drawOval(
      Rect.fromLTWH(w * 0.18, h * 0.2, w * 0.64, h * 0.18),
      Paint()..color = const Color(0xFFDCE3EA),
    );
  }

  @override
  bool shouldRepaint(_TunaPainter old) => false;
}

/// A salmon steak: pink with pale stripes and a darker skin edge.
class _SalmonPainter extends CustomPainter {
  const _SalmonPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // A rounded "U" (the shape of a salmon steak).
    final steak = Path()
      ..moveTo(w * 0.5, h * 0.92)
      ..cubicTo(w * 0.05, h * 0.8, w * -0.02, h * 0.2, w * 0.3, h * 0.1)
      ..quadraticBezierTo(w * 0.5, h * 0.3, w * 0.7, h * 0.1)
      ..cubicTo(w * 1.02, h * 0.2, w * 0.95, h * 0.8, w * 0.5, h * 0.92)
      ..close();
    canvas.drawPath(steak, Paint()..color = const Color(0xFFFF8A65));
    canvas.drawPath(
      steak,
      Paint()
        ..color = const Color(0xFFC0563A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.08,
    );
    // Pale fat lines curving round the middle.
    final fat = Paint()
      ..color = const Color(0xCCFFE0D2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.06
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.45),
        width: w * 0.7,
        height: h * 0.6,
      ),
      0.5,
      2.1,
      false,
      fat,
    );
    canvas.drawCircle(
      Offset(w * 0.5, h * 0.4),
      w * 0.06,
      fat..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_SalmonPainter old) => false;
}
