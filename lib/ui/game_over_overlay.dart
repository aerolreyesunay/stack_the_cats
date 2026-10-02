import 'package:flutter/material.dart';

import '../ads/ad_service.dart';
import '../economy/treats.dart';
import '../game/stack_game.dart';
import '../services/player_service.dart';
import 'treats_ui.dart';

const _brown = Color(0xFF5B3A29);
const _muted = Color(0xFF8A6A55);

/// The card that pops up when the tower falls.
class GameOverOverlay extends StatefulWidget {
  const GameOverOverlay({
    super.key,
    required this.game,
    this.onRevive,
    this.onPlayAgain,
    this.onMenu,
  });

  final StackGame game;

  /// Pays for a revive with treats, a Salmon or an ad. Returns whether it
  /// went through.
  final Future<bool> Function(PayWith how)? onRevive;

  /// "Stack again" and "Main menu" (may show an ad first). Default to
  /// restarting and leaving straight away.
  final VoidCallback? onPlayAgain;
  final VoidCallback? onMenu;

  @override
  State<GameOverOverlay> createState() => _GameOverOverlayState();
}

class _GameOverOverlayState extends State<GameOverOverlay> {
  bool _reviving = false;

  Future<void> _revive(PayWith how) async {
    final onRevive = widget.onRevive;
    if (onRevive == null) return;
    setState(() => _reviving = true);
    final ok = await onRevive(how);
    // On success this card is removed, so only reset on failure.
    if (!ok && mounted) setState(() => _reviving = false);
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
            Text(
              game.newBest ? 'New best!' : 'Tower down!',
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                color: _brown,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${game.score} ${game.score == 1 ? 'cat' : 'cats'} stacked',
              style: const TextStyle(fontSize: 20, color: _brown),
            ),
            if (!game.isGuestRun)
              Text(
                'Best: ${game.best}',
                style: const TextStyle(fontSize: 16, color: _muted),
              ),
            if (game.earnsTreats && game.runTreats > 0) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Earned ',
                    style: TextStyle(fontSize: 16, color: _brown),
                  ),
                  TreatAmount(game.runTreats),
                ],
              ),
            ],
            if (game.runTuna > 0 || game.runSalmon > 0) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Caught ',
                    style: TextStyle(fontSize: 16, color: _brown),
                  ),
                  if (game.runTuna > 0) FishAmount(Fish.tuna, game.runTuna),
                  if (game.runTuna > 0 && game.runSalmon > 0)
                    const SizedBox(width: 10),
                  if (game.runSalmon > 0)
                    FishAmount(Fish.salmon, game.runSalmon),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Text(
              '"${game.gameOverLine}"',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontStyle: FontStyle.italic,
                color: _muted,
              ),
            ),
            const SizedBox(height: 20),
            if (game.canRevive) _reviveOptions(),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE76F51),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
              ),
              onPressed: _reviving ? null : widget.onPlayAgain ?? game.restart,
              child: const Text('Stack again', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _reviving ? null : widget.onMenu ?? game.onExitToMenu,
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

  /// Revive with treats or a Salmon (signed in), or for watching an ad.
  /// Each way can be used a few times per game (see [PayWith]).
  Widget _reviveOptions() {
    return ListenableBuilder(
      listenable: Listenable.merge([
        PlayerService.instance.player,
        AdService.instance.rewardedReady,
      ]),
      builder: (context, _) {
        final game = widget.game;
        final uses = game.revives;
        final player = PlayerService.instance.player.value;
        final adReady =
            AdService.instance.rewardedReady.value && uses.canUse(PayWith.ad);
        if (player == null && !adReady) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Text(
              'Sign in to earn treats and revive',
              style: TextStyle(fontSize: 14, color: _muted),
            ),
          );
        }
        if (_reviving) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          );
        }
        // Bigger towers cost more to bring back.
        final cost = Treats.reviveCostFor(game.score);
        final short = player == null ? 0 : cost - player.treats;
        final salmon = player?.salmon ?? 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (player != null && uses.canUse(PayWith.treats))
                    _OptionButton(
                      onPressed: short <= 0
                          ? () => _revive(PayWith.treats)
                          : null,
                      label: 'Revive',
                      trailing: TreatAmount(cost),
                      left: uses.left(PayWith.treats),
                    ),
                  if (player != null && uses.canUse(PayWith.fish))
                    _OptionButton(
                      onPressed: salmon > 0
                          ? () => _revive(PayWith.fish)
                          : null,
                      label: 'Revive',
                      trailing: const FishAmount(Fish.salmon, 1),
                      left: uses.left(PayWith.fish),
                    ),
                  if (adReady)
                    _OptionButton(
                      onPressed: () => _revive(PayWith.ad),
                      label: 'Free revive',
                      trailing: const Icon(
                        Icons.smart_display_rounded,
                        color: treatColor,
                      ),
                      left: uses.left(PayWith.ad),
                    ),
                ],
              ),
              if (player != null &&
                  short > 0 &&
                  salmon == 0 &&
                  !adReady &&
                  uses.canUse(PayWith.treats))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '$short more treats needed',
                    style: const TextStyle(fontSize: 13, color: _muted),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.onPressed,
    required this.label,
    required this.trailing,
    required this.left,
  });

  final VoidCallback? onPressed;
  final String label;
  final Widget trailing;

  /// Uses of this option left this game.
  final int left;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: _brown,
        side: const BorderSide(color: treatColor, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          trailing,
          const SizedBox(width: 6),
          Text(
            '$left left',
            style: const TextStyle(fontSize: 11, color: _muted),
          ),
        ],
      ),
    );
  }
}
