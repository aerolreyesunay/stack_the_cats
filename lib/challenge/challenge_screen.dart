import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../audio/audio_manager.dart';
import '../game/stack_game.dart';
import '../services/game_session.dart';
import '../ui/treat_confetti.dart';
import '../ui/treats_ui.dart';
import 'challenge_service.dart';
import 'match_rules.dart';

const _brown = Color(0xFF5B3A29);
const _muted = Color(0xFF8A6A55);
const _accent = Color(0xFFE76F51);
const _cream = Color(0xFFFDEBD3);

/// A live head-to-head match: waiting for the friend, the countdown, the
/// race itself and the result.
class ChallengeScreen extends StatefulWidget {
  const ChallengeScreen({
    super.key,
    required this.matchId,
    required this.friendUid,
    required this.friendName,
    required this.isChallenger,
  });

  final String matchId;
  final String friendUid;
  final String friendName;

  /// True for the player who sent the challenge (they wait for an answer).
  final bool isChallenger;

  @override
  State<ChallengeScreen> createState() => _ChallengeScreenState();
}

class _ChallengeScreenState extends State<ChallengeScreen> {
  final _service = ChallengeService.instance;

  StreamSubscription<Match>? _sub;
  final _match = ValueNotifier<Match?>(null);
  final _outcome = ValueNotifier<MatchOutcome>(MatchOutcome.undecided);

  StackGame? _game;
  Timer? _ticker;

  /// This player's cats, counted on the server (which decides the result
  /// from them, not from the live score).
  GameSession? _session;

  /// Seconds left in the countdown (3, 2, 1, 0 = "Go!"), or null.
  final _countdown = ValueNotifier<int?>(null);
  bool _started = false;

  /// Shown until the opponent has opened the match too.
  final _waitingForThem = ValueNotifier<bool>(false);

  DateTime? _themDisconnectedAt;
  bool _paid = false;

  /// Treats paid (or to be paid) to this player at the end.
  int _prize = 0;

  /// Wagers: this player's stake was taken (and maybe given back).
  bool _stakeTried = false;
  bool _staked = false;
  bool _refunded = false;

  /// The match was called off because this player couldn't pay the stake.
  bool _couldNotPay = false;
  late final DateTime _openedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _service.setPlaying(true);
    AudioManager.instance.playMusic(Music.game);
    _sub = _service.watch(widget.matchId).listen(_onMatch);
    // Ticks the countdown, the answer timeout and disconnect forfeits.
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _sub?.cancel();
    _session?.end();
    _service.setPlaying(false);
    AudioManager.instance.stopAllSfx();
    _match.dispose();
    _outcome.dispose();
    _countdown.dispose();
    _waitingForThem.dispose();
    _game?.canRealign.dispose();
    _game?.isOver.dispose();
    super.dispose();
  }

  void _onMatch(Match m) {
    _match.value = m;
    if (_game == null &&
        (m.state == MatchState.countdown || m.state == MatchState.finished)) {
      _createGame(m.seed);
    }
    if (m.state == MatchState.countdown) _takeStake(m);
    // Called off before it started: the server returns the stake.
    if (m.state == MatchState.cancelled && !_started) _refund();
    _themDisconnectedAt = m.them.connected
        ? null
        : (_themDisconnectedAt ?? DateTime.now());
    _checkOutcome();
  }

  void _createGame(int seed) {
    _session = GameSession.startMatch(widget.matchId);
    final game = StackGame(
      onExitToMenu: () => Navigator.of(context).maybePop(),
      rulesForNewRun: () => RunRules.challenge(seed),
      onLanded: ({
        required combo,
        required tier,
        required atMs,
        required treats,
        fish,
      }) => _session?.landed(combo: combo, tier: tier, atMs: atMs),
    )..holdStart = true;
    game.onScore = (score) =>
        _service.reportScore(widget.matchId, score).catchError(_logError);
    game.onTowerFell = (score) {
      // My tower fell: tell the other player (even at 0 cats).
      _service.reportFell(widget.matchId, score).catchError(_logError);
    };
    setState(() => _game = game);
  }

  void _logError(Object e) => debugPrint('Challenge update failed: $e');

  /// Wagers: the server takes this player's stake as the match begins.
  /// The race waits until it has.
  Future<void> _takeStake(Match m) async {
    if (!m.stakes.isWager || _stakeTried) return;
    _stakeTried = true;
    if (await _service.joinMatch(widget.matchId, m.stakes.wager)) {
      _staked = true;
    } else {
      _couldNotPay = true;
      await _service.callOff(widget.matchId).catchError(_logError);
    }
    if (mounted) setState(() {});
  }

  /// Wagers called off before the start: asks the server for the stake
  /// back (it checks the match really didn't start).
  Future<void> _refund() async {
    if (!_staked || _refunding) return;
    _refunding = true;
    final result = await _settleWithRetries();
    if (!mounted) return;
    setState(() => _refunded = (result?.prize ?? 0) > 0);
  }

  bool _refunding = false;

  /// Asks the server to settle, again every couple of seconds until it
  /// agrees the match is over (both players' last moves may still be on
  /// their way).
  Future<({String outcome, int prize})?> _settleWithRetries() async {
    for (var attempt = 0; attempt < 20; attempt++) {
      final result = await _service.settle(widget.matchId);
      if (result != null) return result;
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return null;
    }
    return null;
  }

  void _tick() {
    final m = _match.value;
    if (m == null) return;

    // The challenger gives up if there's no answer in time.
    if (widget.isChallenger &&
        m.state == MatchState.invited &&
        DateTime.now().difference(_openedAt) > ChallengeService.answerWindow) {
      _service.cancel(widget.matchId, widget.friendUid).catchError(_logError);
    }

    // Countdown, then both start at the same server moment, once both
    // players are in. An opponent who never turns up calls it off.
    final startAt = m.startAt;
    // (A wager also waits for the server to take this player's stake.)
    final stakeReady = !m.stakes.isWager || _staked;
    if (!_started && startAt != null && _game != null && !_couldNotPay) {
      final left = startAt.difference(_service.serverNow);
      _waitingForThem.value = !m.them.joined;
      if (!m.them.joined || !stakeReady) {
        _countdown.value = null;
        if (m.state == MatchState.countdown &&
            -left > ChallengeService.joinWindow) {
          _service.callOff(widget.matchId).catchError(_logError);
        }
      } else if (left <= Duration.zero) {
        _started = true;
        _game!.holdStart = false;
        _countdown.value = 0; // "Go!"
        Future.delayed(const Duration(milliseconds: 700), () {
          if (mounted) _countdown.value = null;
        });
      } else {
        _countdown.value = (left.inMilliseconds / 1000).ceil().clamp(1, 3);
      }
    }
    _checkOutcome();
  }

  void _checkOutcome() {
    final m = _match.value;
    if (m == null || !_started || _outcome.value != MatchOutcome.undecided) {
      return;
    }
    final themGone =
        _themDisconnectedAt != null &&
        DateTime.now().difference(_themDisconnectedAt!) >
            ChallengeService.forfeitAfter;
    final result = ChallengeService.outcome(
      m,
      themGoneTooLong: themGone,
      meGoneTooLong: false,
    );
    if (result == MatchOutcome.undecided) return;
    // What it should pay; the server decides and pays for real.
    _prize = m.stakes.prizeFor(result);
    _outcome.value = result;
    _game?.haltForResult();
    _service.finish(widget.matchId).catchError(_logError);
    _settle();
  }

  /// The server's verdict and prize. (Either player's app may ask; the
  /// server pays both, once.)
  Future<void> _settle() async {
    final result = await _settleWithRetries();
    if (result == null || !mounted) return;
    final outcome = switch (result.outcome) {
      'win' => MatchOutcome.win,
      'lose' => MatchOutcome.lose,
      'draw' => MatchOutcome.draw,
      _ => _outcome.value,
    };
    setState(() {
      _prize = result.prize;
      _paid = result.prize > 0;
    });
    _outcome.value = outcome;
    if (_paid && outcome == MatchOutcome.win) showTreatConfetti(context);
  }

  // ---------- Leaving ----------

  bool get _decided => _outcome.value != MatchOutcome.undecided;

  Future<void> _leave() async {
    final m = _match.value;
    final waiting = m == null || m.state == MatchState.invited;
    final over =
        _decided ||
        m?.state == MatchState.declined ||
        m?.state == MatchState.cancelled;
    if (m != null && !over && !waiting && !_started) {
      // Not started yet: call it off (any stake comes back).
      await _service.callOff(widget.matchId).catchError(_logError);
      // The stake comes back (the server checks; this carries on after
      // the screen closes).
      if (_staked) unawaited(_service.settle(widget.matchId));
    } else if (!over && !waiting) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Leave the challenge?',
            style: TextStyle(fontWeight: FontWeight.w900, color: _brown),
          ),
          content: Text(
            m.stakes.isWager
                ? '${widget.friendName} will win if you leave now, and '
                      'you\'ll lose your ${m.stakes.wager} treat stake.'
                : '${widget.friendName} will win if you leave now.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep playing'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _accent),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Leave'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await _service.leave(widget.matchId).catchError(_logError);
    } else if (waiting && widget.isChallenger) {
      await _service
          .cancel(widget.matchId, widget.friendUid)
          .catchError(_logError);
    }
    if (mounted) Navigator.of(context).pop();
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        body: SafeArea(
          child: ValueListenableBuilder<Match?>(
            valueListenable: _match,
            builder: (context, m, _) {
              if (m == null) {
                return const Center(child: CircularProgressIndicator());
              }
              // Once started, the race plays out whatever the state says.
              final game = _game;
              if (_started && game != null) return _play(game);
              switch (m.state) {
                case MatchState.invited:
                  return _waiting(m);
                case MatchState.declined:
                  return _ended('${m.them.name} said no this time.');
                case MatchState.cancelled:
                  return _ended(
                    _couldNotPay
                        ? 'Not enough treats for this wager.'
                        : widget.isChallenger
                        ? '${m.them.name} didn\'t answer.'
                        : !m.them.joined
                        ? '${m.them.name} didn\'t show up.'
                        : 'The challenge was cancelled.',
                    note: _refunded
                        ? 'Your ${m.stakes.wager} treats were returned.'
                        : null,
                  );
                case MatchState.countdown:
                case MatchState.finished:
                  if (game == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return _play(game);
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _waiting(Match m) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Avatar(name: m.them.name, photoUrl: m.them.photoUrl, radius: 40),
            const SizedBox(height: 20),
            Text(
              widget.isChallenger ? 'Waiting for ${m.them.name}…' : 'Joining…',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _brown,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Same cats for both of you. One tower each, '
              'no revives. Highest stack wins!',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted),
            ),
            const SizedBox(height: 10),
            _Prize(stakes: m.stakes),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            TextButton(onPressed: _leave, child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }

  Widget _ended(String message, {String? note}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.sentiment_neutral_rounded,
              size: 56,
              color: _muted,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, color: _brown),
            ),
            if (note != null) ...[
              const SizedBox(height: 8),
              Text(
                note,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _accent),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _play(StackGame game) {
    return GameWidget<StackGame>(
      game: game,
      initialActiveOverlays: const ['challengeHud'],
      overlayBuilderMap: {
        'challengeHud': (context, game) => _Hud(
          match: _match,
          countdown: _countdown,
          waitingForThem: _waitingForThem,
          onLeave: _leave,
        ),
        StackGame.challengeOverlay: (context, game) => ValueListenableBuilder(
          valueListenable: _outcome,
          builder: (context, outcome, _) => _ResultCard(
            outcome: outcome,
            match: _match.value,
            paid: _paid,
            prize: _prize,
            onDone: () => Navigator.of(context).pop(),
          ),
        ),
      },
    );
  }
}

/// The prize line: "Winner gets 🐟30 · Loser gets 🐟10", or for a wager
/// "Winner takes 🐟200".
class _Prize extends StatelessWidget {
  const _Prize({required this.stakes});
  final MatchStakes stakes;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: _brown, fontSize: 16);
    if (stakes.isWager) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Winner takes ', style: style),
          TreatAmount(stakes.prizeFor(MatchOutcome.win)),
        ],
      );
    }
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Winner gets ', style: style),
        TreatAmount(stakes.prizeFor(MatchOutcome.win)),
        const Text('  ·  Loser gets ', style: style),
        TreatAmount(stakes.prizeFor(MatchOutcome.lose)),
      ],
    );
  }
}

/// Leave button, the opponent's live score, and the 3-2-1 countdown.
class _Hud extends StatelessWidget {
  const _Hud({
    required this.match,
    required this.countdown,
    required this.waitingForThem,
    required this.onLeave,
  });

  final ValueNotifier<Match?> match;
  final ValueNotifier<int?> countdown;
  final ValueNotifier<bool> waitingForThem;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: 8,
          left: 8,
          child: IconButton.filled(
            tooltip: 'Leave',
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: _brown,
              side: BorderSide(color: _brown.withAlpha(40)),
            ),
            onPressed: onLeave,
            icon: const Icon(Icons.close_rounded),
          ),
        ),
        Positioned(
          top: 10,
          right: 10,
          child: ValueListenableBuilder<Match?>(
            valueListenable: match,
            builder: (context, m, _) =>
                m == null ? const SizedBox() : _OpponentPanel(player: m.them),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: ValueListenableBuilder<bool>(
              valueListenable: waitingForThem,
              builder: (context, waiting, _) => !waiting
                  ? const SizedBox()
                  : Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          'Waiting for '
                          '${match.value?.them.name.split(' ').first ?? 'your opponent'}'
                          ' to join…',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _brown,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: ValueListenableBuilder<int?>(
              valueListenable: countdown,
              builder: (context, n, _) {
                if (n == null) return const SizedBox();
                return Center(
                  child: Text(
                    n == 0 ? 'Go!' : '$n',
                    style: TextStyle(
                      fontSize: n == 0 ? 72 : 96,
                      fontWeight: FontWeight.w900,
                      color: _accent,
                      shadows: const [
                        Shadow(color: Colors.white, blurRadius: 12),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _OpponentPanel extends StatelessWidget {
  const _OpponentPanel({required this.player});
  final MatchPlayer player;

  @override
  Widget build(BuildContext context) {
    final status = !player.connected
        ? 'Reconnecting…'
        : player.left
        ? 'Left'
        : player.alive
        ? 'Stacking'
        : 'Tower fell';
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 14, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _brown.withAlpha(40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Avatar(name: player.name, photoUrl: player.photoUrl, radius: 15),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_firstName(player.name)}  ${player.score}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _brown,
                ),
              ),
              Text(
                status,
                style: TextStyle(
                  fontSize: 11,
                  color: player.alive && player.connected ? _muted : _accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _firstName(String name) {
    final first = name.split(' ').first;
    return first.length > 12 ? '${first.substring(0, 12)}…' : first;
  }
}

/// While waiting for the other tower: "Your tower fell! Maria is on 12".
/// Then the result.
class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.outcome,
    required this.match,
    required this.paid,
    required this.prize,
    required this.onDone,
  });

  final MatchOutcome outcome;
  final Match? match;
  final bool paid;

  /// Treats this player gets for the result.
  final int prize;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final m = match;
    final them = m?.them;
    final title = switch (outcome) {
      MatchOutcome.win => 'You win!',
      MatchOutcome.lose => '${them?.name ?? 'They'} wins!',
      MatchOutcome.draw => "It's a draw!",
      MatchOutcome.undecided => 'Your tower fell!',
    };
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
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                color: _brown,
              ),
            ),
            const SizedBox(height: 14),
            if (m != null)
              Text(
                'You ${m.me.score}  ·  ${them!.name.split(' ').first} '
                '${them.score}',
                style: const TextStyle(fontSize: 20, color: _brown),
              ),
            const SizedBox(height: 12),
            if (outcome == MatchOutcome.undecided) ...[
              Text(
                'Waiting for ${them?.name.split(' ').first ?? 'them'} to '
                'finish. They need ${(m?.me.score ?? 0) + 1} to win.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted),
              ),
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
            ] else ...[
              if (prize > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      outcome == MatchOutcome.draw && m?.stakes.isWager == true
                          ? (paid ? 'Stake returned: ' : 'Stake back: ')
                          : (paid ? 'You earned ' : 'Prize: '),
                      style: const TextStyle(fontSize: 16, color: _brown),
                    ),
                    TreatAmount(prize, size: 18),
                  ],
                )
              else if (m?.stakes.isWager == true)
                Text(
                  'You lost your ${m!.stakes.wager} treat stake.',
                  style: const TextStyle(color: _muted),
                ),
              if (outcome != MatchOutcome.win) ...[
                const SizedBox(height: 6),
                Text(
                  outcome == MatchOutcome.draw
                      ? 'Evenly matched! Try again?'
                      : 'So close! Try again.',
                  style: const TextStyle(color: _muted),
                ),
              ],
            ],
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
              ),
              onPressed: onDone,
              child: Text(
                outcome == MatchOutcome.undecided ? 'Leave' : 'Done',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.photoUrl, this.radius = 18});
  final String name;
  final String? photoUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    return CircleAvatar(
      radius: radius,
      backgroundColor: _cream,
      foregroundImage: url != null ? NetworkImage(url) : null,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(
          color: _brown,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }
}
