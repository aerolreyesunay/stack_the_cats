import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/audio_manager.dart';
import '../economy/treats.dart';
import '../screens/game_screen.dart';
import '../services/game_session.dart';
import '../services/player_service.dart';
import '../ui/treats_ui.dart';
import 'challenge_screen.dart';
import 'challenge_service.dart';
import 'match_rules.dart';

const _brown = Color(0xFF5B3A29);
const _muted = Color(0xFF8A6A55);
const _accent = Color(0xFFE76F51);

/// Pick a challenge: the Self Challenge, or a live match against a random
/// opponent (Friendly, or for a treat wager).
class ChallengeModesScreen extends StatefulWidget {
  const ChallengeModesScreen({super.key});

  @override
  State<ChallengeModesScreen> createState() => _ChallengeModesScreenState();
}

class _ChallengeModesScreenState extends State<ChallengeModesScreen> {
  int _wager = MatchPrizes.wagers.first;

  /// Waiting for the server to take the Self Challenge entry.
  bool _starting = false;

  Future<void> _startSelfChallenge() async {
    setState(() => _starting = true);
    final session = await GameSession.startSelfChallenge();
    if (!mounted) return;
    setState(() => _starting = false);
    if (session == null) return; // the reason is shown by itself
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GameScreen.selfChallenge(session)),
    );
    AudioManager.instance.playMusic(Music.menu);
  }

  Future<void> _findMatch(MatchStakes stakes) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MatchmakingScreen(stakes: stakes)),
    );
    AudioManager.instance.playMusic(Music.menu);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Challenges'),
        backgroundColor: Colors.transparent,
        actions: const [
          Padding(padding: EdgeInsets.only(right: 12), child: TreatBalance()),
        ],
      ),
      body: ValueListenableBuilder<PlayerData?>(
        valueListenable: PlayerService.instance.player,
        builder: (context, player, _) {
          if (player == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Sign in (and connect to the internet) for challenges.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: _muted),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _selfChallengeCard(player),
              const SizedBox(height: 22),
              const _SectionTitle(
                'Challenge Anyone',
                'Race a random player live. Same cats, one tower each, '
                    'no revives. Highest stack wins!',
              ),
              const SizedBox(height: 10),
              _friendlyCard(),
              const SizedBox(height: 12),
              _wagerCard(player),
            ],
          );
        },
      ),
    );
  }

  Widget _selfChallengeCard(PlayerData player) {
    final canPay = player.treats >= SelfChallenge.cost;
    return _Card(
      icon: Icons.flag_rounded,
      title: 'Self Challenge',
      subtitle:
          'Stack ${SelfChallenge.goal} cats with one tower. No revives or '
          'realigns. Every ${SelfChallenge.step} cats the cats speed up '
          'and the cushion sways more.',
      children: [
        const SizedBox(height: 10),
        _rewardLine('50 cats', const [Fish.tuna]),
        _rewardLine('75 cats', const [Fish.salmon]),
        _rewardLine('100 cats', const [Fish.tuna, Fish.salmon]),
        const SizedBox(height: 14),
        _PlayButton(
          onPressed: canPay && !_starting ? _startSelfChallenge : null,
          child: _starting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Start  ', style: TextStyle(fontSize: 17)),
                    TreatAmount(SelfChallenge.cost, color: Colors.white),
                  ],
                ),
        ),
        if (!canPay)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'You need ${SelfChallenge.cost} treats.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _muted),
            ),
          ),
      ],
    );
  }

  Widget _rewardLine(String cats, List<Fish> fish) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(cats, style: const TextStyle(color: _brown)),
          ),
          for (final f in fish) ...[
            FishIcon(f, size: 18),
            const SizedBox(width: 4),
            Text(f.label, style: const TextStyle(color: _brown)),
            const SizedBox(width: 12),
          ],
        ],
      ),
    );
  }

  Widget _friendlyCard() {
    const stakes = MatchStakes.friendly();
    return _Card(
      icon: Icons.handshake_rounded,
      title: 'Friendly',
      subtitle: 'Free to play. Everybody earns something.',
      children: [
        const SizedBox(height: 10),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Winner ', style: TextStyle(color: _brown)),
            TreatAmount(stakes.prizeFor(MatchOutcome.win)),
            const Text('   ·   Loser ', style: TextStyle(color: _brown)),
            TreatAmount(stakes.prizeFor(MatchOutcome.lose)),
          ],
        ),
        const SizedBox(height: 14),
        _PlayButton(
          onPressed: () => _findMatch(stakes),
          child: const Text('Find a match', style: TextStyle(fontSize: 17)),
        ),
      ],
    );
  }

  Widget _wagerCard(PlayerData player) {
    final unlocked = player.canWager;
    final canPay = unlocked && player.treats >= _wager;
    return _Card(
      icon: Icons.local_fire_department_rounded,
      title: 'Treat Wager',
      subtitle:
          'You both put in the same treats. The winner takes them all; a '
          'draw gives them back.',
      children: [
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final w in MatchPrizes.wagers)
              ChoiceChip(
                selected: w == _wager,
                showCheckmark: false,
                selectedColor: _accent.withAlpha(40),
                side: BorderSide(
                  color: w == _wager ? _accent : _brown.withAlpha(50),
                ),
                label: TreatAmount(w, size: 15),
                onSelected: (_) => setState(() => _wager = w),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Text('Winner takes ', style: TextStyle(color: _brown)),
            TreatAmount(_wager * 2),
          ],
        ),
        const SizedBox(height: 14),
        _PlayButton(
          onPressed: canPay
              ? () => _findMatch(MatchStakes.wager(_wager))
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Wager  ', style: TextStyle(fontSize: 17)),
              TreatAmount(_wager, color: Colors.white),
            ],
          ),
        ),
        if (!canPay)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              !unlocked
                  ? 'Unlocks after you stack ${PlayerData.wagerMinLandings} '
                        'cats in total (${player.landingsTotal} so far).'
                  : 'You need ${_wager - player.treats} more treats.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: _muted),
            ),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, this.subtitle);
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: _brown,
            ),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(color: _muted)),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: _accent, size: 26),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: _brown,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: _muted)),
          ...children,
        ],
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.onPressed, required this.child});
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: _accent,
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      onPressed: onPressed,
      child: child,
    );
  }
}

/// "Looking for an opponent…" until someone with the same stakes is found,
/// then straight into the match.
class MatchmakingScreen extends StatefulWidget {
  const MatchmakingScreen({super.key, required this.stakes});

  final MatchStakes stakes;

  /// Gives up after this long without an opponent.
  static const searchFor = Duration(seconds: 60);

  @override
  State<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends State<MatchmakingScreen> {
  MatchFinder? _finder;
  Timer? _giveUp;
  bool _searching = true;
  String? _problem;

  /// Went on to the match (which keeps "Playing" on from here).
  bool _handedOff = false;

  @override
  void initState() {
    super.initState();
    // Friends see "Playing" (and can't challenge) while searching.
    ChallengeService.instance.setPlaying(true);
    _search();
  }

  @override
  void dispose() {
    _giveUp?.cancel();
    _finder?.cancel();
    if (!_handedOff) ChallengeService.instance.setPlaying(false);
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _problem = null;
    });
    final finder = MatchFinder(widget.stakes);
    _finder = finder;
    _giveUp?.cancel();
    _giveUp = Timer(MatchmakingScreen.searchFor, () async {
      await finder.cancel();
      if (mounted) {
        setState(() {
          _searching = false;
          _problem = "No one's looking for a match right now.";
        });
      }
    });
    try {
      final found = await finder.start();
      _giveUp?.cancel();
      if (found == null || !mounted) return;
      AudioManager.instance.playSfx(Sfx.chimes.first);
      _handedOff = true;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChallengeScreen(
            matchId: found.matchId,
            friendUid: found.opponentUid,
            friendName: found.opponentName,
            isChallenger: false,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Matchmaking failed: $e');
      _giveUp?.cancel();
      if (mounted) {
        setState(() {
          _searching = false;
          _problem = "Couldn't search for a match. Check your connection.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stakes = widget.stakes;
    return Scaffold(
      appBar: AppBar(
        title: Text(stakes.isWager ? 'Treat Wager' : 'Friendly'),
        backgroundColor: Colors.transparent,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_searching) ...[
                const SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(strokeWidth: 4),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Looking for an opponent…',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _brown,
                  ),
                ),
              ] else
                Text(
                  _problem ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, color: _brown),
                ),
              const SizedBox(height: 10),
              if (stakes.isWager)
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'You both stake ',
                      style: TextStyle(color: _muted),
                    ),
                    TreatAmount(stakes.wager, size: 15),
                    const Text(
                      '  ·  Winner takes ',
                      style: TextStyle(color: _muted),
                    ),
                    TreatAmount(stakes.prizeFor(MatchOutcome.win), size: 15),
                  ],
                )
              else
                const Text(
                  'Same cats for both of you. Highest stack wins!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted),
                ),
              const SizedBox(height: 28),
              if (_searching)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel', style: TextStyle(fontSize: 16)),
                )
              else ...[
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _accent),
                  onPressed: _search,
                  child: const Text('Search again'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
