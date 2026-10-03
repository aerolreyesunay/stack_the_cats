import 'package:flutter/material.dart';

import '../audio/audio_manager.dart';
import '../economy/treats.dart';
import '../services/player_service.dart';
import 'treat_confetti.dart';
import 'treats_ui.dart';

const _brown = Color(0xFF5B3A29);
const _muted = Color(0xFF8A6A55);
const _cream = Color(0xFFFDEBD3);

/// Shows the 7-day sign-in reward and lets the player claim today's.
Future<void> showDailyRewardDialog(BuildContext context, DailyStatus status) {
  return showDialog<void>(
    context: context,
    builder: (_) => _DailyRewardDialog(status: status),
  );
}

class _DailyRewardDialog extends StatefulWidget {
  const _DailyRewardDialog({required this.status});

  final DailyStatus status;

  @override
  State<_DailyRewardDialog> createState() => _DailyRewardDialogState();
}

class _DailyRewardDialogState extends State<_DailyRewardDialog> {
  bool _busy = false;
  DailyReward? _claimed;
  bool _done = false;

  Future<void> _claim() async {
    setState(() => _busy = true);
    try {
      final reward = await PlayerService.instance.claimDaily();
      if (!mounted) return;
      AudioManager.instance.playSfx(Sfx.purrfect);
      if (reward != null) showTreatConfetti(context);
      setState(() {
        _busy = false;
        _claimed = reward;
        _done = true;
      });
    } catch (e) {
      debugPrint('Daily claim failed: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't claim right now. Check your connection."),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = widget.status.day;
    final claimed = _claimed;
    final done = _done;
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text(
        'Daily treats',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.w900, color: _brown),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            !done
                ? 'Day $today of 7. Come back every day for bigger treats!'
                : claimed == null
                ? 'See you tomorrow!'
                : 'You got ${claimed.label}! See you tomorrow.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              for (int day = 1; day <= 7; day++)
                _DayTile(
                  day: day,
                  reward: Treats.dailyRewards[day - 1],
                  done: day < today || (day == today && done),
                  isToday: day == today,
                ),
            ],
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        if (!done)
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: treatColor),
            onPressed: _busy ? null : _claim,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text('Claim ${widget.status.reward.label}'),
          )
        else
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Nice!', style: TextStyle(color: _brown)),
          ),
      ],
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({
    required this.day,
    required this.reward,
    required this.done,
    required this.isToday,
  });

  final int day;
  final DailyReward reward;
  final bool done;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 62,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: done ? treatColor.withAlpha(35) : _cream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isToday ? treatColor : Colors.transparent,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Text(
            'Day $day',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _muted,
            ),
          ),
          const SizedBox(height: 4),
          done
              ? const Icon(
                  Icons.check_circle_rounded,
                  color: treatColor,
                  size: 18,
                )
              : reward.fish != null
              ? FishIcon(reward.fish!, size: 18)
              : const TreatIcon(size: 16),
          const SizedBox(height: 2),
          Text(
            reward.fish?.label ?? '${reward.treats}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _brown,
            ),
          ),
        ],
      ),
    );
  }
}
