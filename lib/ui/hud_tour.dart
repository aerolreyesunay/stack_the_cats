import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'treats_ui.dart';

const _brown = Color(0xFF5B3A29);
const _muted = Color(0xFF8A6A55);
const _glow = Color(0xFFFFC46B);

/// One stop of the [HudTour]: the button it points at, and what to say.
class HudTourStep {
  const HudTourStep({
    required this.id,
    required this.target,
    required this.title,
    required this.body,
  });

  /// Remembered once seen, so each button is explained only once.
  final String id;
  final GlobalKey target;
  final String title;
  final String body;
}

/// A first-time walkthrough of the in-game buttons: the screen dims, a
/// glowing ring circles each button in turn, and a card explains it, with
/// Next and Skip.
class HudTour extends StatefulWidget {
  const HudTour({super.key, required this.steps, required this.onFinished});

  final List<HudTourStep> steps;

  /// Called after the last step, or on Skip.
  final VoidCallback onFinished;

  static const _prefsKey = 'hudTourSeen';

  /// The steps already seen, or null if that can't be read (then the tour
  /// isn't shown, rather than shown every time).
  static Future<Set<String>?> seen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_prefsKey) ?? const []).toSet();
    } catch (e) {
      debugPrint('Reading tour progress failed: $e');
      return null;
    }
  }

  static Future<void> markSeen(Iterable<String> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final all = {...?prefs.getStringList(_prefsKey), ...ids};
      await prefs.setStringList(_prefsKey, all.toList());
    } catch (e) {
      debugPrint('Saving tour progress failed: $e');
    }
  }

  @override
  State<HudTour> createState() => _HudTourState();
}

class _HudTourState extends State<HudTour> with SingleTickerProviderStateMixin {
  int _index = 0;

  /// Where the current button is, in this widget's coordinates.
  Rect? _target;

  late final _ring = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  bool get _isLast => _index == widget.steps.length - 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  void _measure() {
    if (!mounted) return;
    final button =
        widget.steps[_index].target.currentContext?.findRenderObject()
            as RenderBox?;
    final me = context.findRenderObject() as RenderBox?;
    Rect? rect;
    if (button != null && me != null && button.attached && button.hasSize) {
      rect = button.localToGlobal(Offset.zero, ancestor: me) & button.size;
    }
    setState(() => _target = rect);
  }

  void _next() {
    if (_isLast) {
      widget.onFinished();
      return;
    }
    setState(() => _index++);
    _measure();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final target = _target;
        return Stack(
          children: [
            // Dims everything but the button, and swallows taps meant for
            // the game underneath.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: AnimatedBuilder(
                  animation: _ring,
                  builder: (context, _) => CustomPaint(
                    painter: _SpotlightPainter(
                      target,
                      Curves.easeInOut.transform(_ring.value),
                    ),
                  ),
                ),
              ),
            ),
            if (target != null) _card(size, target),
          ],
        );
      },
    );
  }

  /// The explanation card, under the button (or above it if the button is
  /// low on the screen), kept on screen.
  Widget _card(Size size, Rect target) {
    final step = widget.steps[_index];
    final width = (size.width - 32).clamp(0.0, 300.0);
    final left = (target.center.dx - width / 2).clamp(
      16.0,
      size.width - 16 - width,
    );
    final below = target.center.dy < size.height / 2;
    return Positioned(
      left: left,
      width: width,
      top: below ? target.bottom + 18 : null,
      bottom: below ? null : size.height - target.top + 18,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: Material(
          key: ValueKey(_index),
          color: Colors.white,
          elevation: 8,
          shadowColor: _brown.withAlpha(120),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        step.title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: _brown,
                        ),
                      ),
                    ),
                    Text(
                      '${_index + 1} of ${widget.steps.length}',
                      style: const TextStyle(fontSize: 12, color: _muted),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  step.body,
                  style: const TextStyle(fontSize: 14, color: _muted),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (!_isLast)
                      TextButton(
                        onPressed: widget.onFinished,
                        child: const Text(
                          'Skip',
                          style: TextStyle(color: _muted),
                        ),
                      ),
                    const Spacer(),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: treatColor,
                      ),
                      onPressed: _next,
                      child: Text(_isLast ? "Let's stack!" : 'Next'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A dark veil with a hole over the button, ringed by a pulsing glow.
/// [t] (0-1) is how far the pulse has grown.
class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter(this.target, this.t);

  final Rect? target;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final veil = Paint()..color = const Color(0xB82B1A10);
    final target = this.target;
    if (target == null) {
      canvas.drawRect(Offset.zero & size, veil);
      return;
    }
    RRect around(double by) {
      final r = target.inflate(by);
      return RRect.fromRectAndRadius(r, Radius.circular(r.shortestSide / 2));
    }

    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRRect(around(7)),
      veil,
    );
    final ring = around(7 + 4 * t);
    canvas.drawRRect(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = _glow.withAlpha((110 * t).round())
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawRRect(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = _glow.withAlpha((150 + 105 * t).round()),
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.target != target || old.t != t;
}
