import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../game/stack_game.dart';
import '../services/connectivity_service.dart';
import 'brand_logos.dart';

const _brown = Color(0xFF5B3A29);
const _muted = Color(0xFF8A6A55);
const _accent = Color(0xFFE76F51);

/// Shown when a guest or offline run reaches the cat limit: congratulations,
/// and an invitation to sign in for unlimited stacking.
class LimitReachedOverlay extends StatefulWidget {
  const LimitReachedOverlay({
    super.key,
    required this.game,
    this.onPlayAgain,
    this.onMenu,
  });

  final StackGame game;

  /// "Stack again" and "Main menu" (may show an ad first). Default to
  /// restarting and leaving straight away.
  final VoidCallback? onPlayAgain;
  final VoidCallback? onMenu;

  @override
  State<LimitReachedOverlay> createState() => _LimitReachedOverlayState();
}

class _LimitReachedOverlayState extends State<LimitReachedOverlay> {
  bool _busy = false;
  bool _signedIn = false;

  Future<void> _signIn() async {
    setState(() => _busy = true);
    try {
      final user = await AuthService.instance.signInWithGoogle();
      if (mounted) setState(() => _signedIn = user != null);
    } catch (e) {
      debugPrint('Sign-in from limit card failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't sign in. Check your connection."),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    return Center(
      child: Container(
        margin: const EdgeInsets.all(28),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(color: Color(0x33000000), blurRadius: 20),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.celebration_rounded, size: 48, color: _accent),
            const SizedBox(height: 8),
            const Text(
              'Purrfect tower!',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                color: _brown,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You stacked ${game.score} cats!',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, color: _brown),
            ),
            const SizedBox(height: 16),
            _invitation(),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
              ),
              onPressed: _busy ? null : widget.onPlayAgain ?? game.restart,
              child: Text(
                _signedIn ? 'Play unlimited' : 'Stack again',
                style: const TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : widget.onMenu ?? game.onExitToMenu,
              child: const Text(
                'Main menu',
                style: TextStyle(fontSize: 16, color: _brown),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _invitation() {
    if (_signedIn) {
      return const Text(
        "You're signed in! Your next tower has no limit.",
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 15, color: _muted),
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService.instance.online,
      builder: (context, online, _) {
        if (!online) {
          return const Column(
            children: [
              Icon(Icons.wifi_off_rounded, color: _muted),
              SizedBox(height: 6),
              Text(
                'Sign in to keep stacking with no limit, earn treats and '
                'join the leaderboard. Connect to the internet, then sign '
                'in from the main menu.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: _muted),
              ),
            ],
          );
        }
        return Column(
          children: [
            const Text(
              'Sign in to keep stacking with no limit, earn treats and '
              'join the leaderboard.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: _muted),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: _brown,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              onPressed: _busy ? null : _signIn,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BrandLogo('Google', size: 20),
                        SizedBox(width: 10),
                        Text(
                          'Sign in with Google',
                          style: TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}
