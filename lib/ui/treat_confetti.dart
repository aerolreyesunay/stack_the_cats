import 'dart:math';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../audio/audio_manager.dart';

/// Bursts a shower of fish treats over the whole screen, with a short round
/// of applause. Taps go straight through it, and it removes itself when
/// it's done.
void showTreatConfetti(BuildContext context) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  AudioManager.instance.playSfx(Sfx.applause);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => IgnorePointer(
      child: _TreatConfetti(
        onDone: () {
          if (entry.mounted) entry.remove();
        },
      ),
    ),
  );
  overlay.insert(entry);
}

class _Treat {
  _Treat(Random rng)
    : vx = (rng.nextDouble() * 2 - 1) * 340,
      vy = -(380 + rng.nextDouble() * 520),
      spin = (rng.nextDouble() * 2 - 1) * 9,
      size = 16 + rng.nextDouble() * 18,
      delay = rng.nextDouble() * 0.15,
      sway = rng.nextDouble() * 2 * pi,
      color = _colors[rng.nextInt(_colors.length)];

  static const _colors = [
    Color(0xFFE76F51), // coral
    Color(0xFFF4A259), // ginger
    Color(0xFFE9B949), // gold
    Color(0xFFF28FAD), // pink
    Color(0xFF6CC3B5), // mint
    Color(0xFF8FA8E8), // blue
  ];

  final double vx, vy, spin, size, delay, sway;
  final Color color;
}

class _TreatConfetti extends StatefulWidget {
  const _TreatConfetti({required this.onDone});
  final VoidCallback onDone;

  @override
  State<_TreatConfetti> createState() => _TreatConfettiState();
}

class _TreatConfettiState extends State<_TreatConfetti>
    with SingleTickerProviderStateMixin {
  static const _seconds = 2.6;
  static const _gravity = 900.0;
  static const _count = 46;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (_seconds * 1000).round()),
  );
  final _treats = List.generate(_count, (_) => _Treat(Random()));

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Bursts out from a little above the middle of the screen.
    final origin = Offset(size.width / 2, size.height * 0.38);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final elapsed = _controller.value * _seconds;
        return Stack(
          children: [for (final t in _treats) _place(t, elapsed, origin)],
        );
      },
    );
  }

  Widget _place(_Treat t, double elapsed, Offset origin) {
    final time = max(0.0, elapsed - t.delay);
    final x = origin.dx + t.vx * time + sin(time * 4 + t.sway) * 18;
    final y = origin.dy + t.vy * time + 0.5 * _gravity * time * time;
    // Fade out over the last 30%.
    final fade = (1 - (elapsed / _seconds - 0.7) / 0.3).clamp(0.0, 1.0);
    return Positioned(
      left: x - t.size / 2,
      top: y - t.size / 2,
      child: Opacity(
        opacity: fade,
        child: Transform.rotate(
          angle: t.spin * time,
          child: FaIcon(FontAwesomeIcons.fish, size: t.size, color: t.color),
        ),
      ),
    );
  }
}
