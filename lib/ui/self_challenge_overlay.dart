import 'package:flutter/material.dart';

import '../economy/treats.dart';
import '../game/stack_game.dart';
import '../services/player_service.dart';
import 'treats_ui.dart';

const _brown = Color(0xFF5B3A29);
const _muted = Color(0xFF8A6A55);
const _accent = Color(0xFFE76F51);

/// The end of a Self Challenge, whether the tower fell or reached 100:
/// how far it got, the Tuna and Salmon won, and "Try again".
class SelfChallengeOverlay extends StatelessWidget {
  const SelfChallengeOverlay({
    super.key,
    required this.game,
    required this.onTryAgain,
    required this.onMenu,
  });

  final StackGame game;

  /// Pays the entry again and restarts.
  final VoidCallback onTryAgain;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final score = game.score;
    final complete = score >= SelfChallenge.goal;
    final reward = SelfChallenge.rewardFor(score);
    final won = reward.tuna > 0 || reward.salmon > 0;
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
            if (complete)
              const Icon(Icons.emoji_events_rounded, size: 48, color: _accent),
            Text(
              complete ? 'Challenge complete!' : 'Tower down!',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: _brown,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '$score of ${SelfChallenge.goal} cats',
              style: const TextStyle(fontSize: 20, color: _brown),
            ),
            const SizedBox(height: 14),
            if (won)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'You won ',
                    style: TextStyle(fontSize: 18, color: _brown),
                  ),
                  if (reward.tuna > 0)
                    FishAmount(Fish.tuna, reward.tuna, size: 20),
                  if (reward.tuna > 0 && reward.salmon > 0)
                    const SizedBox(width: 12),
                  if (reward.salmon > 0)
                    FishAmount(Fish.salmon, reward.salmon, size: 20),
                ],
              )
            else
              const Text(
                'Reach 50 cats to win a Tuna!',
                style: TextStyle(fontSize: 16, color: _muted),
              ),
            const SizedBox(height: 14),
            const _RewardTable(),
            const SizedBox(height: 20),
            ValueListenableBuilder<PlayerData?>(
              valueListenable: PlayerService.instance.player,
              builder: (context, player, _) {
                final canPay = (player?.treats ?? 0) >= SelfChallenge.cost;
                return FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 14,
                    ),
                  ),
                  onPressed: canPay ? onTryAgain : null,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Try again  ', style: TextStyle(fontSize: 18)),
                      TreatAmount(
                        SelfChallenge.cost,
                        color: Colors.white,
                        size: 16,
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onMenu,
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
}

/// 50 cats: Tuna · 75 cats: Salmon · 100 cats: both.
class _RewardTable extends StatelessWidget {
  const _RewardTable();

  @override
  Widget build(BuildContext context) {
    Widget row(String cats, List<Fish> fish) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              cats,
              style: const TextStyle(fontSize: 13, color: _muted),
            ),
          ),
          for (final f in fish) ...[
            FishIcon(f, size: 16),
            const SizedBox(width: 4),
            Text(f.label, style: const TextStyle(fontSize: 13, color: _muted)),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
    return Column(
      children: [
        row('50 cats', const [Fish.tuna]),
        row('75 cats', const [Fish.salmon]),
        row('100 cats', const [Fish.tuna, Fish.salmon]),
      ],
    );
  }
}
