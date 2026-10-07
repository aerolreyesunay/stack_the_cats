import 'package:flutter/material.dart';

import 'treats_ui.dart';

const _brown = Color(0xFF5B3A29);

/// A round in-game button: a cream disc with a gold rim, a glossy top and a
/// soft shadow, that dips when pressed. [accent] makes it coral (the Store).
/// Greyed out while [onPressed] is null.
class HudButton extends StatefulWidget {
  const HudButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.accent = false,
    this.size = 50,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool accent;
  final double size;

  @override
  State<HudButton> createState() => _HudButtonState();
}

class _HudButtonState extends State<HudButton> {
  bool _down = false;

  void _setDown(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final s = widget.size;
    final accent = widget.accent;
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.tooltip,
        child: GestureDetector(
          onTapDown: enabled ? (_) => _setDown(true) : null,
          onTapUp: enabled ? (_) => _setDown(false) : null,
          onTapCancel: enabled ? () => _setDown(false) : null,
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: _down ? 0.9 : 1,
            duration: const Duration(milliseconds: 90),
            child: AnimatedOpacity(
              opacity: enabled ? 1 : 0.5,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: s,
                height: s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: accent
                        ? const [Color(0xFFF7A97C), treatColor]
                        : const [Colors.white, Color(0xFFFBE9D3)],
                  ),
                  border: Border.all(
                    color: accent
                        ? const Color(0xFFFFD9BC)
                        : const Color(0xFFE6C597),
                    width: 1.5,
                  ),
                  boxShadow: enabled
                      ? [
                          BoxShadow(
                            color: _brown.withAlpha(_down ? 45 : 70),
                            blurRadius: _down ? 4 : 10,
                            offset: Offset(0, _down ? 1 : 4),
                          ),
                        ]
                      : const [],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Gloss across the top.
                    Positioned(
                      top: s * 0.07,
                      child: Container(
                        width: s * 0.62,
                        height: s * 0.32,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(s),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withAlpha(accent ? 120 : 220),
                              Colors.white.withAlpha(0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Icon(
                      widget.icon,
                      size: s * 0.48,
                      color: accent ? Colors.white : _brown,
                      shadows: accent
                          ? [
                              Shadow(
                                color: _brown.withAlpha(90),
                                blurRadius: 3,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// While [active], gently pulses [child] (it grows a little, with a warm
/// glow) to suggest using it.
class AttentionPulse extends StatefulWidget {
  const AttentionPulse({
    super.key,
    required this.active,
    required this.child,
    this.color = treatColor,
  });

  final bool active;
  final Widget child;
  final Color color;

  @override
  State<AttentionPulse> createState() => _AttentionPulseState();
}

class _AttentionPulseState extends State<AttentionPulse>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(AttentionPulse old) {
    super.didUpdateWidget(old);
    if (widget.active == old.active) return;
    if (widget.active) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.animateTo(0, duration: const Duration(milliseconds: 200));
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_pulse.value);
        return Transform.scale(
          scale: 1 + 0.1 * t,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                if (t > 0)
                  BoxShadow(
                    color: widget.color.withAlpha((160 * t).round()),
                    blurRadius: 18 * t,
                    spreadRadius: 3 * t,
                  ),
              ],
            ),
            child: child,
          ),
        );
      },
    );
  }
}
