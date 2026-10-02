import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/audio_manager.dart';
import '../economy/treats.dart';
import '../ui/treats_ui.dart';
import 'challenge_screen.dart';
import 'challenge_service.dart';

const _brown = Color(0xFF5B3A29);
const _muted = Color(0xFF8A6A55);
const _accent = Color(0xFFE76F51);

/// Used to show challenge pop-ups from anywhere in the app.
final appNavigatorKey = GlobalKey<NavigatorState>();

/// Shows "Maria challenges you!" whenever a challenge arrives, on whatever
/// screen the player is on (except mid-game: friends see them as "Playing"
/// and can't challenge them then).
class ChallengeInviteListener extends StatefulWidget {
  const ChallengeInviteListener({super.key, required this.child});
  final Widget child;

  @override
  State<ChallengeInviteListener> createState() =>
      _ChallengeInviteListenerState();
}

class _ChallengeInviteListenerState extends State<ChallengeInviteListener> {
  final _incoming = ChallengeService.instance.incoming;
  String? _showing; // match id of the open pop-up

  @override
  void initState() {
    super.initState();
    _incoming.addListener(_onInvite);
  }

  @override
  void dispose() {
    _incoming.removeListener(_onInvite);
    super.dispose();
  }

  Future<void> _onInvite() async {
    final invite = _incoming.value;
    final navigator = appNavigatorKey.currentState;
    final context = appNavigatorKey.currentContext;
    if (invite == null || navigator == null || context == null) return;
    if (_showing == invite.matchId) return;
    final service = ChallengeService.instance;
    if (service.isPlaying) {
      // Arrived just as this player started a game: politely say no.
      service.decline(invite).catchError((Object e) {
        debugPrint('Declining challenge failed: $e');
      });
      return;
    }
    _showing = invite.matchId;
    AudioManager.instance.playSfx(Sfx.chimes.first);
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _InviteDialog(invite: invite),
    );
    _showing = null;
    try {
      if (accepted == true) {
        await service.accept(invite);
        await navigator.push(
          MaterialPageRoute(
            builder: (_) => ChallengeScreen(
              matchId: invite.matchId,
              friendUid: invite.from,
              friendName: invite.name,
              isChallenger: false,
            ),
          ),
        );
      } else if (accepted == false) {
        await service.decline(invite);
      }
      // null: it expired while open; nothing to do.
    } catch (e) {
      debugPrint('Answering challenge failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _InviteDialog extends StatefulWidget {
  const _InviteDialog({required this.invite});
  final ChallengeInvite invite;

  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  Timer? _timer;
  double _left = 1; // fraction of the answer window left

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final service = ChallengeService.instance;
      final age = service.serverNow.difference(widget.invite.sentAt);
      final left =
          1 - age.inMilliseconds / ChallengeService.answerWindow.inMilliseconds;
      // Closes by itself if it expires or the challenger cancels.
      final stillThere =
          service.incoming.value?.matchId == widget.invite.matchId;
      if (left <= 0 || !stillThere) {
        _timer?.cancel();
        Navigator.of(context).pop();
        return;
      }
      setState(() => _left = left);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final invite = widget.invite;
    final url = invite.photoUrl;
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 76,
                height: 76,
                child: CircularProgressIndicator(
                  value: _left,
                  strokeWidth: 4,
                  color: _accent,
                  backgroundColor: _accent.withAlpha(40),
                ),
              ),
              CircleAvatar(
                radius: 32,
                foregroundImage: url != null ? NetworkImage(url) : null,
                child: Text(invite.name.characters.first.toUpperCase()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${invite.name} challenges you!',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900, color: _brown),
          ),
        ],
      ),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Same cats, one tower each. Highest stack wins!',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted),
          ),
          SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Winner gets ', style: TextStyle(color: _brown)),
              TreatAmount(MatchPrizes.friendlyWin),
              Text('  ·  Loser gets ', style: TextStyle(color: _brown)),
              TreatAmount(MatchPrizes.friendlyLose),
            ],
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _accent),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Accept'),
        ),
      ],
    );
  }
}
