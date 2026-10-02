import 'dart:async';
import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../audio/audio_manager.dart';
import '../economy/treats.dart';
import '../game/stack_game.dart';
import '../ads/ad_service.dart';
import '../ads/banner_slot.dart';
import '../auth/auth_service.dart';
import '../challenge/challenge_service.dart';
import '../services/connectivity_service.dart';
import '../services/game_session.dart';
import '../ui/limit_reached_overlay.dart';
import '../ui/self_challenge_overlay.dart';
import 'settings_screen.dart';
import '../store/catalog.dart';
import '../store/store_screen.dart';
import '../store/wallpapers.dart';
import '../ui/treat_confetti.dart';
import '../services/player_service.dart';
import '../ui/game_over_overlay.dart';
import '../ui/treats_ui.dart';

/// The screen that holds the actual game.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key}) : selfChallenge = null;

  /// A Self Challenge, with its first run already paid for.
  const GameScreen.selfChallenge(GameSession this.selfChallenge, {super.key});

  final GameSession? selfChallenge;

  static const hudOverlay = 'hud';

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final _player = PlayerService.instance;

  late final StackGame _game = StackGame(
    onExitToMenu: () => Navigator.of(context).pop(),
    rulesForNewRun: _rulesForNewRun,
    // Shown straight away; the server checks and pays them.
    onLanded:
        ({
          required combo,
          required tier,
          required atMs,
          required treats,
          fish,
        }) => _session?.landed(
          combo: combo,
          tier: tier,
          atMs: atMs,
          treats: treats,
          fish: fish,
        ),
    // Games pay up to a daily limit (the server keeps the same one).
    earnAllowance: _player.gameAllowance,
    onEarnLimitReached: _sayEarnLimit,
    onCelebrate: () {
      if (mounted) showTreatConfetti(context);
    },
    onRunEnded: (score) {
      // The server puts the score on the leaderboard once it has the last
      // cats. (Guest and offline runs don't go on it.)
      _session?.flush();
      // The Self Challenge pays its Tuna and Salmon when the run ends.
      if (_game.rules.isSelfChallenge) _session?.end(score: score);
    },
    // Cats and wallpaper the player owns (basic ones for guests).
    catPool: () => _player.player.value?.catPool ?? Cats.basic,
    wallpaper: _currentWallpaper,
  );

  /// With "Random each game" on: the wallpaper picked for this run.
  Wallpaper? _runWallpaper;
  String? _lastChosenWallpaper;

  Wallpaper _currentWallpaper() {
    final data = _player.player.value;
    if (data == null) return Wallpapers.classic;
    return data.wallpaperRandom
        ? (_runWallpaper ?? data.wallpaper)
        : data.wallpaper;
  }

  void _pickRunWallpaper() {
    final pool = _player.player.value?.wallpaperPool ?? const [];
    _runWallpaper = pool.isEmpty ? null : pool[Random().nextInt(pool.length)];
  }

  /// A wallpaper bought or chosen in the Store mid-run goes up straight
  /// away, even in random mode.
  void _onPlayerChanged() {
    final id = _player.player.value?.wallpaperId;
    if (id != _lastChosenWallpaper) {
      if (_lastChosenWallpaper != null) _runWallpaper = Wallpapers.byId(id);
      _lastChosenWallpaper = id;
    }
  }

  /// "That's today's treats from games", once a day.
  static String? _limitSaidOn;

  void _sayEarnLimit() {
    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    if (_limitSaidOn == today || !mounted) return;
    _limitSaidOn = today;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "That's all the treats games can earn today. Keep stacking for "
          'the leaderboard; treats are back tomorrow!',
        ),
      ),
    );
  }

  /// This run on the server (null for guests).
  late GameSession? _session = widget.selfChallenge;

  bool get _isSelfChallenge => widget.selfChallenge != null;

  /// Asked at the start of every run. Unlimited stacking and treats need a
  /// sign-in and a connection.
  RunRules _rulesForNewRun() {
    _pickRunWallpaper();
    // (Each Self Challenge run is started, and paid, before it begins.)
    if (_isSelfChallenge) return RunRules.selfChallenge;
    final signedIn = AuthService.instance.currentUser != null;
    final full = signedIn && ConnectivityService.instance.isOnline;
    _session?.end();
    _session = full ? GameSession.startNormal() : null;
    return full ? RunRules.full : RunRules.guest;
  }

  @override
  void initState() {
    super.initState();
    // Counts finished games for the full-screen ad between games.
    _game.isOver.addListener(_onOverChanged);
    _lastChosenWallpaper = _player.player.value?.wallpaperId;
    _player.player.addListener(_onPlayerChanged);
    // The realign tip may show again this visit (if still in the first runs).
    _RealignTip._shownThisVisit = false;
    AudioManager.instance.playMusic(Music.game);
    // Friends see "Playing" and can't challenge mid-run.
    ChallengeService.instance.setPlaying(true);
    // If ads couldn't start earlier (e.g. no connection yet), try again.
    AdService.instance.start();
  }

  @override
  void dispose() {
    _session?.end(score: _game.score);
    ChallengeService.instance.setPlaying(false);
    // Leaving the game: nothing from it keeps playing over the menu.
    AudioManager.instance.stopAllSfx();
    _game.canRealign.dispose();
    _game.isOver.removeListener(_onOverChanged);
    _player.player.removeListener(_onPlayerChanged);
    _game.isOver.dispose();
    super.dispose();
  }

  /// Pauses the game and asks before throwing away the current run.
  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
  }) async {
    _game.pauseEngine();
    AudioManager.instance.stopAllSfx();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: Color(0xFF5B3A29),
          ),
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep playing'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: treatColor),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    _game.resumeEngine();
    return ok ?? false;
  }

  Future<void> _confirmRestart() async {
    final ok = await _confirm(
      title: 'Restart?',
      message: 'Your current tower will be lost. Treats you earned are kept.',
      action: 'Restart',
    );
    if (ok) _game.restart();
  }

  /// Opens Settings with the game paused, and carries on afterwards.
  Future<void> _openSettings() => _openPaused(const SettingsScreen());

  /// The Store mid-run: buys apply straight away (new cats start dropping,
  /// a new wallpaper goes up).
  Future<void> _openStore() => _openPaused(const StoreScreen());

  /// Opens [screen] with the game paused, and carries on afterwards.
  Future<void> _openPaused(Widget screen) async {
    _game.pauseEngine();
    AudioManager.instance.stopAllSfx();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _game.resumeEngine();
  }

  Future<void> _confirmHome() async {
    final ok = await _confirm(
      title: 'Back to menu?',
      message: 'This run will end. Treats you earned are kept.',
      action: 'Main menu',
    );
    if (ok && mounted) {
      _game.quitRun();
      Navigator.of(context).pop();
    }
  }

  /// Plays a rewarded ad (game paused), then runs [action] if the player
  /// watched it to the end.
  Future<bool> _watchAdFor(VoidCallback action) async {
    _game.pauseEngine();
    final earned = await AdService.instance.showRewarded();
    if (!mounted) return false;
    _game.resumeEngine();
    if (earned) {
      action();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Watch the whole ad to get it free.')),
      );
    }
    return earned;
  }

  /// Between games: a full-screen ad if one is due (every 5 games), then
  /// [next] (play again, or back to the menu).
  Future<void> _afterAdIfDue(VoidCallback next) async {
    await AdService.instance.maybeShowBetweenGames();
    if (mounted) next();
  }

  void _onOverChanged() {
    if (_game.isOver.value) AdService.instance.gameFinished();
  }

  /// Realign: the game pauses and the player picks how to pay, with
  /// treats, a Tuna or by watching an ad.
  Future<void> _chooseRealign() async {
    if (!_game.canRealign.value) return;
    _game.pauseEngine();
    AudioManager.instance.stopAllSfx();
    final choice = await showDialog<PayWith>(
      context: context,
      builder: (context) => _RealignDialog(uses: _game.realigns),
    );
    if (!mounted) return;
    _game.resumeEngine();
    if (choice == null) return; // cancelled
    final done = await _payForUse(
      kind: 'realign',
      payWith: choice,
      cost: switch (choice) {
        PayWith.treats => const WalletChange(treats: -Treats.realignCost),
        PayWith.fish => const WalletChange(tuna: -1),
        PayWith.ad => WalletChange.none,
      },
      then: () => _game.realign(choice),
    );
    // They've realigned, so they know how: no more tips.
    if (done) _RealignTip.markLearned();
  }

  /// Revive, paid with treats, a Salmon or an ad.
  Future<bool> _revive(PayWith how) => _payForUse(
    kind: 'revive',
    payWith: how,
    cost: switch (how) {
      PayWith.treats => WalletChange(
        treats: -Treats.reviveCostFor(_game.score),
      ),
      PayWith.fish => const WalletChange(salmon: -1),
      PayWith.ad => WalletChange.none,
    },
    then: () => _game.revive(how),
  );

  /// Pays for a revive or realign (an ad is watched first), then runs
  /// [then] straight away. The server checks the price and the limits.
  Future<bool> _payForUse({
    required String kind,
    required PayWith payWith,
    required WalletChange cost,
    required VoidCallback then,
  }) async {
    if (payWith == PayWith.ad) {
      return _watchAdFor(() {
        _session?.buyUse(kind: kind, payWith: payWith);
        then();
      });
    }
    final session = _session;
    if (session == null) return false;
    if (!session.buyUse(kind: kind, payWith: payWith, cost: cost)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              payWith == PayWith.treats
                  ? 'Not enough treats.'
                  : 'You have no ${kind == 'revive' ? 'Salmon' : 'Tuna'} left.',
            ),
          ),
        );
      }
      return false;
    }
    then();
    return true;
  }

  bool _startingRetry = false;

  /// Self Challenge "Try again": pays the entry again, then restarts.
  Future<void> _retrySelfChallenge() async {
    if (_startingRetry) return;
    _startingRetry = true;
    final session = await GameSession.startSelfChallenge();
    _startingRetry = false;
    if (session == null || !mounted) return;
    _session = session;
    _afterAdIfDue(_game.restart);
  }

  @override
  Widget build(BuildContext context) {
    // The back gesture asks first too, unless the run is already over.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_game.isOver.value) {
          Navigator.of(context).pop();
        } else {
          _confirmHome();
        }
      },
      child: _scaffold(),
    );
  }

  Widget _scaffold() {
    return Scaffold(
      body: SafeArea(
        // The banner sits below the game, never on top of it.
        child: Column(
          children: [
            Expanded(child: _gameWidget()),
            // Banner ads in normal games only.
            if (!_isSelfChallenge) const BannerSlot(),
          ],
        ),
      ),
    );
  }

  Widget _gameWidget() {
    return GameWidget<StackGame>(
      game: _game,
      initialActiveOverlays: const [GameScreen.hudOverlay],
      overlayBuilderMap: _isSelfChallenge
          ? _selfChallengeOverlays()
          : _normalOverlays(),
    );
  }

  /// The Self Challenge ends with the same result card whether the tower
  /// fell or reached 100.
  Map<String, OverlayWidgetBuilder<StackGame>> _selfChallengeOverlays() {
    Widget result(BuildContext context, StackGame game) => SelfChallengeOverlay(
      game: game,
      onTryAgain: _retrySelfChallenge,
      onMenu: () => _afterAdIfDue(() => Navigator.of(context).pop()),
    );
    return {
      GameScreen.hudOverlay: (context, game) => _Hud(
        game: game,
        onRealign: _chooseRealign,
        onRestart: null,
        onHome: _confirmHome,
        onSettings: _openSettings,
        onStore: _openStore,
      ),
      StackGame.limitOverlay: result,
      StackGame.gameOverOverlay: result,
    };
  }

  Map<String, OverlayWidgetBuilder<StackGame>> _normalOverlays() {
    return {
      GameScreen.hudOverlay: (context, game) => _Hud(
        game: game,
        onRealign: _chooseRealign,
        onRestart: _confirmRestart,
        onHome: _confirmHome,
        onSettings: _openSettings,
        onStore: _openStore,
      ),
      StackGame.limitOverlay: (context, game) => LimitReachedOverlay(
        game: game,
        onPlayAgain: () => _afterAdIfDue(game.restart),
        onMenu: () => _afterAdIfDue(() => Navigator.of(context).pop()),
      ),
      StackGame.gameOverOverlay: (context, game) => GameOverOverlay(
        game: game,
        onRevive: _revive,
        onPlayAgain: () => _afterAdIfDue(game.restart),
        onMenu: () => _afterAdIfDue(() => Navigator.of(context).pop()),
      ),
    };
  }
}

/// Home, Restart and Settings down the left; the treat balance and the
/// Realign button down the right.
class _Hud extends StatelessWidget {
  const _Hud({
    required this.game,
    required this.onRealign,
    required this.onRestart,
    required this.onHome,
    required this.onSettings,
    required this.onStore,
  });

  final StackGame game;
  final VoidCallback onSettings;
  final VoidCallback onStore;
  final VoidCallback onRealign;

  /// Null hides Restart (the Self Challenge restarts from its result card).
  final VoidCallback? onRestart;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final player = PlayerService.instance.player;
    return Stack(
      children: [
        Positioned(
          top: 8,
          left: 8,
          // Hidden on the game over card, which has its own buttons.
          child: ValueListenableBuilder<bool>(
            valueListenable: game.isOver,
            builder: (context, over, _) => over
                ? const SizedBox.shrink()
                // Stacked down the left edge, clear of the score.
                : Column(
                    children: [
                      _HudIconButton(
                        icon: Icons.home_rounded,
                        tooltip: 'Main menu',
                        onPressed: onHome,
                      ),
                      if (onRestart case final restart?) ...[
                        const SizedBox(height: 6),
                        _HudIconButton(
                          icon: Icons.refresh_rounded,
                          tooltip: 'Restart',
                          onPressed: restart,
                        ),
                      ],
                      const SizedBox(height: 6),
                      _HudIconButton(
                        icon: Icons.settings_rounded,
                        tooltip: 'Settings',
                        onPressed: onSettings,
                      ),
                    ],
                  ),
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const TreatBalance(),
              // Realign, under the balance. Signed-in players only; greyed
              // out until the tower has two cats (and while one is falling).
              ListenableBuilder(
                listenable: Listenable.merge([
                  player,
                  game.canRealign,
                  game.isOver,
                ]),
                builder: (context, _) {
                  if (player.value == null || game.isOver.value) {
                    return const SizedBox.shrink();
                  }
                  // The tip hangs below Realign (clear of the score), and
                  // the Store sits under them.
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (game.rules.allowRealign) ...[
                          _RealignButton(
                            onPressed: game.canRealign.value ? onRealign : null,
                          ),
                          _RealignTip(canRealign: game.canRealign),
                          const SizedBox(height: 8),
                        ],
                        _StoreButton(onPressed: onStore),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HudIconButton extends StatelessWidget {
  const _HudIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const brown = Color(0xFF5B3A29);
    return IconButton.filled(
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: brown,
        side: BorderSide(color: brown.withAlpha(40)),
      ),
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}

/// A little speech bubble next to the Realign button the first time it can
/// be used in a run: "Tower wobbly? Tap to straighten it!". It keeps coming
/// back (once per visit, fading after a few seconds) until the player taps
/// "Got it" or uses Realign; after that it's never shown again.
class _RealignTip extends StatefulWidget {
  const _RealignTip({required this.canRealign});
  final ValueNotifier<bool> canRealign;

  static const _prefsKey = 'realignTipLearned';
  static const _showFor = Duration(seconds: 8);

  /// Shown at most once per visit to the game screen.
  static bool _shownThisVisit = false;

  /// The player knows how to realign: never show the tip again.
  static Future<void> markLearned() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, true);
    } catch (e) {
      debugPrint('Saving realign tip failed: $e');
    }
  }

  @override
  State<_RealignTip> createState() => _RealignTipState();
}

class _RealignTipState extends State<_RealignTip> {
  bool _visible = false;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    widget.canRealign.addListener(_maybeShow);
    _maybeShow();
  }

  @override
  void dispose() {
    widget.canRealign.removeListener(_maybeShow);
    _hide?.cancel();
    super.dispose();
  }

  Future<void> _maybeShow() async {
    if (!widget.canRealign.value || _RealignTip._shownThisVisit) return;
    _RealignTip._shownThisVisit = true;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_RealignTip._prefsKey) == true || !mounted) return;
    setState(() => _visible = true);
    _hide = Timer(_RealignTip._showFor, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _gotIt() {
    _hide?.cancel();
    setState(() => _visible = false);
    _RealignTip.markLearned();
  }

  @override
  Widget build(BuildContext context) {
    const brown = Color(0xFF5B3A29);
    // Takes no space while hidden (so the Store button sits right under
    // Realign), and grows in smoothly when shown.
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      alignment: Alignment.topRight,
      child: !_visible
          ? const SizedBox.shrink()
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Little arrow pointing up at the button.
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 17),
                  child: CustomPaint(
                    size: const Size(14, 8),
                    painter: _ArrowPainter(brown),
                  ),
                ),
                Container(
                  constraints: const BoxConstraints(maxWidth: 170),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: brown,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Tower wobbly? Tap here to straighten it!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: _gotIt,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Got it',
                            style: TextStyle(
                              color: brown,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// The Store button under Realign.
class _StoreButton extends StatelessWidget {
  const _StoreButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const brown = Color(0xFF5B3A29);
    return IconButton.filled(
      tooltip: 'Store',
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: brown,
        side: BorderSide(color: brown.withAlpha(90)),
      ),
      onPressed: onPressed,
      icon: const Icon(Icons.storefront_rounded),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Points up.
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.color != color;
}

/// The round Realign button under the treat balance.
class _RealignButton extends StatelessWidget {
  const _RealignButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    const brown = Color(0xFF5B3A29);
    return IconButton.filled(
      tooltip: 'Realign',
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: brown,
        disabledBackgroundColor: Colors.white.withAlpha(150),
        disabledForegroundColor: brown.withAlpha(90),
        side: BorderSide(color: brown.withAlpha(onPressed != null ? 90 : 30)),
      ),
      onPressed: onPressed,
      icon: const Icon(Icons.align_vertical_center_rounded),
    );
  }
}

/// "Realign your tower?" — pay with treats or a Tuna, or watch an ad.
/// Each way can be used a few times per game.
class _RealignDialog extends StatelessWidget {
  const _RealignDialog({required this.uses});

  final UseCounter uses;

  static const _brown = Color(0xFF5B3A29);
  static const _muted = Color(0xFF8A6A55);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        PlayerService.instance.player,
        AdService.instance.rewardedReady,
      ]),
      builder: (context, _) {
        final player = PlayerService.instance.player.value;
        final treats = player?.treats ?? 0;
        final tuna = player?.tuna ?? 0;
        final short = Treats.realignCost - treats;
        final adReady = AdService.instance.rewardedReady.value;
        void pick(PayWith how) => Navigator.of(context).pop(how);

        // "2 left this game", plus an optional note in front.
        Widget usesLeft(PayWith how, {String? note}) => Padding(
          padding: const EdgeInsets.only(top: 3, bottom: 8),
          child: Text(
            [
              ?note,
              uses.canUse(how)
                  ? '${uses.left(how)} left this game'
                  : 'Used up this game',
            ].join('  ·  '),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: _muted),
          ),
        );

        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Realign your tower?',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w900, color: _brown),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Every cat slides back into a straight column.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted),
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: treatColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: short <= 0 && uses.canUse(PayWith.treats)
                    ? () => pick(PayWith.treats)
                    : null,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Use ', style: TextStyle(fontSize: 16)),
                    TreatAmount(Treats.realignCost, color: Colors.white),
                  ],
                ),
              ),
              usesLeft(
                PayWith.treats,
                note: short > 0 ? 'You need $short more treats' : null,
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _brown,
                  side: const BorderSide(color: treatColor, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: tuna > 0 && uses.canUse(PayWith.fish)
                    ? () => pick(PayWith.fish)
                    : null,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Use ', style: TextStyle(fontSize: 16)),
                    FishAmount(Fish.tuna, 1),
                  ],
                ),
              ),
              usesLeft(PayWith.fish, note: 'You have $tuna Tuna'),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _brown,
                  side: const BorderSide(color: treatColor, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: adReady && uses.canUse(PayWith.ad)
                    ? () => pick(PayWith.ad)
                    : null,
                icon: const Icon(
                  Icons.smart_display_rounded,
                  color: treatColor,
                ),
                label: Text(
                  adReady ? 'Watch an ad (free)' : 'No ad available right now',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              usesLeft(PayWith.ad),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: _muted)),
            ),
          ],
        );
      },
    );
  }
}
