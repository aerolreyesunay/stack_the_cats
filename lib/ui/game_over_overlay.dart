import 'package:flutter/material.dart';

import '../ads/ad_service.dart';
import '../economy/treats.dart';
import '../game/stack_game.dart';
import '../services/age_gate.dart';
import '../services/player_service.dart';
import '../store/catalog.dart';
import 'share_result.dart';
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
            // Kids' mode doesn't post to social media.
            if (game.score > 0 && !AgeGate.instance.isKid) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _brown,
                  side: const BorderSide(color: treatColor, width: 1.5),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                onPressed: _reviving
                    ? null
                    : () => showShareResult(
                        context,
                        score: game.score,
                        pool:
                            PlayerService.instance.player.value?.catPool ??
                            Cats.basic,
                      ),
                icon: const Icon(Icons.share_rounded, color: treatColor),
                label: const Text(
                  'Share my stack',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ],
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
  /// Each way can be used a few times per game (see [PayWith]). Options
  /// that can't be used right now stay visible but greyed out, saying why.
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
        final adReady = AdService.instance.rewardedReady.value;

        /// Why an option can't be used, or null if it can.
        String? blocked(PayWith how, {required String? otherwise}) =>
            uses.canUse(how) ? otherwise : 'Used up';

        final treatsBlock = blocked(
          PayWith.treats,
          otherwise: short > 0 ? 'Need $short more' : null,
        );
        final salmonBlock = blocked(
          PayWith.fish,
          otherwise: salmon <= 0 ? 'No Salmon' : null,
        );
        final adBlock = blocked(
          PayWith.ad,
          otherwise: adReady ? null : 'No video yet',
        );
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (player != null) ...[
                    _OptionButton(
                      onPressed: treatsBlock == null
                          ? () => _revive(PayWith.treats)
                          : null,
                      label: 'Revive',
                      trailing: TreatAmount(cost),
                      note: treatsBlock ?? '${uses.left(PayWith.treats)} left',
                    ),
                    _OptionButton(
                      onPressed: salmonBlock == null
                          ? () => _revive(PayWith.fish)
                          : null,
                      label: 'Revive',
                      trailing: const FishAmount(Fish.salmon, 1),
                      note: salmonBlock ?? '${uses.left(PayWith.fish)} left',
                    ),
                  ],
                  _OptionButton(
                    onPressed: adBlock == null
                        ? () => _revive(PayWith.ad)
                        : null,
                    label: 'Free revive',
                    trailing: const Icon(
                      Icons.smart_display_rounded,
                      color: treatColor,
                    ),
                    note: adBlock ?? '${uses.left(PayWith.ad)} left',
                  ),
                ],
              ),
              if (player == null)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Sign in to revive with treats or Salmon',
                    style: TextStyle(fontSize: 13, color: _muted),
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
    required this.note,
  });

  /// Null greys the option out.
  final VoidCallback? onPressed;
  final String label;
  final Widget trailing;

  /// "2 left", or why it can't be used ("Used up", "Need 40 more").
  final String note;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return GreyedOut(
      enabled: enabled,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: _brown,
          disabledForegroundColor: _brown,
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
            Text(note, style: const TextStyle(fontSize: 11, color: _muted)),
          ],
        ),
      ),
    );
  }
}
