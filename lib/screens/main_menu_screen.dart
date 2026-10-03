import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../audio/audio_manager.dart';
import '../challenge/challenge_modes_screen.dart';
import '../game/cat.dart';
import '../store/catalog.dart';
import '../store/store_screen.dart';
import '../economy/treats.dart';
import '../services/age_gate.dart';
import '../services/friends_service.dart';
import '../services/player_service.dart';
import '../ui/account_panel.dart';
import '../ui/daily_reward_dialog.dart';
import '../ui/info_dialog.dart';
import '../ui/treat_confetti.dart';
import '../ui/treats_ui.dart';
import 'friends_screen.dart';
import 'game_screen.dart';
import 'leaderboard_screen.dart';
import 'settings_screen.dart';

const _brown = Color(0xFF5B3A29);
const _accent = Color(0xFFE76F51);

/// The welcome screen players see when the app opens.
class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  final _player = PlayerService.instance.player;

  /// The daily reward pops up by itself once per app launch.
  static bool _dailyShownThisLaunch = false;

  @override
  void initState() {
    super.initState();
    AudioManager.instance.playMusic(Music.menu);
    _player.addListener(_maybeShowDaily);
    _welcome.addListener(_maybeShowWelcome);
    _friendsJoined.addListener(_showFriendsJoined);
    _accepted.addListener(_showRequestsAccepted);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowWelcome();
      _maybeShowDaily();
      _showFriendsJoined();
      _showRequestsAccepted();
    });
  }

  @override
  void dispose() {
    _player.removeListener(_maybeShowDaily);
    _welcome.removeListener(_maybeShowWelcome);
    _friendsJoined.removeListener(_showFriendsJoined);
    _accepted.removeListener(_showRequestsAccepted);
    super.dispose();
  }

  final _friendsJoined = FriendsService.instance.friendsJoinedBonus;
  final _accepted = FriendsService.instance.requestsAccepted;
  final _welcome = PlayerService.instance.welcomeBonusGiven;

  /// A brand-new player's welcome gift, before anything else.
  Future<void> _maybeShowWelcome() async {
    if (!_welcome.value || !mounted) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    _welcome.value = false;
    showTreatConfetti(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Welcome to Stack the Cats!',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w900, color: _brown),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TreatAmount(Treats.welcomeBonus, size: 34),
            SizedBox(height: 12),
            Text(
              'Here are some treats to get you started. Use them to revive '
              'or realign your tower!',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _accent),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Let's stack!"),
          ),
        ],
      ),
    );
    _maybeShowDaily(); // the daily reward waits its turn
    _showWaiting();
  }

  bool _showingAccepted = false;

  /// "Maria accepted your friend request! +5 treats", as a pop-up with
  /// treat confetti. Only on this screen: if it happens during a game (or
  /// on another page, or under another pop-up), it waits until the player
  /// is back here.
  Future<void> _showRequestsAccepted() async {
    final names = _accepted.value;
    if (names.isEmpty || !mounted || _showingAccepted) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    _accepted.value = const [];
    _showingAccepted = true;
    final treats = names.length * Treats.friendAcceptedReward;
    await showInfoDialog(
      context,
      title: catCheer(),
      message: names.length == 1
          ? '${names.first} accepted your friend request. You\'re now '
                'friends!'
          : '${names.join(', ')} accepted your friend requests. You\'re '
                'now friends!',
      icon: Icons.favorite_rounded,
      treats: treats,
      celebrate: true,
    );
    _showingAccepted = false;
    _showWaiting();
  }

  /// Back on this screen (from a game, another page or a pop-up): show
  /// anything that waited.
  void _showWaiting() {
    if (!mounted) return;
    _showRequestsAccepted();
    _showFriendsJoined();
  }

  bool _showingJoined = false;

  /// "A friend joined with your code! +200 treats", as a pop-up with treat
  /// confetti, on this screen only (it waits otherwise).
  Future<void> _showFriendsJoined() async {
    final count = _friendsJoined.value;
    if (count <= 0 || !mounted || _showingJoined) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    _friendsJoined.value = 0;
    _showingJoined = true;
    await showInfoDialog(
      context,
      title: catCheer(),
      message: count == 1
          ? 'A friend joined with your invite code and stacked their first '
                '${Treats.referralMinLandings} cats!'
          : '$count friends joined with your invite code and stacked '
                'their first ${Treats.referralMinLandings} cats!',
      icon: Icons.card_giftcard_rounded,
      treats: count * Treats.friendJoinedReward,
      celebrate: true,
    );
    _showingJoined = false;
    _showWaiting();
  }

  void _maybeShowDaily() {
    final data = _player.value;
    if (_dailyShownThisLaunch || data == null || !data.daily.claimable) return;
    if (_welcome.value) return; // the welcome gift goes first
    // Only over this screen, not over the game or another page.
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    _dailyShownThisLaunch = true;
    showDailyRewardDialog(context, data.daily).then((_) => _showWaiting());
  }

  final _catsKey = GlobalKey<_MenuCatsState>();

  Future<void> _play() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const GameScreen()));
    // Back from the game: switch to menu music again.
    AudioManager.instance.playMusic(Music.menu);
    _catsKey.currentState?.playIntro();
    _showWaiting();
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    // Back on the menu: the cats stack themselves up again.
    _catsKey.currentState?.playIntro();
    _showWaiting();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Center(child: _menu()),
            Positioned(top: 12, right: 12, child: _header()),
          ],
        ),
      ),
    );
  }

  /// A gift button while today's reward is waiting. (The treat balance
  /// only shows during a game.)
  Widget _header() {
    return ValueListenableBuilder<PlayerData?>(
      valueListenable: _player,
      builder: (context, data, _) {
        final daily = data?.daily;
        if (daily == null || !daily.claimable) return const SizedBox.shrink();
        return IconButton(
          tooltip: 'Daily treats',
          color: _accent,
          icon: const Icon(Icons.card_giftcard_rounded),
          onPressed: () => showDailyRewardDialog(context, daily),
        );
      },
    );
  }

  /// The menu in the middle of the screen and the studio logo at the very
  /// bottom. On a short screen it all scrolls, the logo after the buttons
  /// (never on top of them).
  Widget _menu() {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: Column(
              children: [
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
                  child: _menuItems(),
                ),
                const Spacer(),
                const SizedBox(height: 16),
                Image.asset(
                  'assets/branding/jcan_logo_small.png',
                  height: 26,
                  semanticLabel: 'jCan Studios',
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuItems() {
    return Column(
      children: [
        const Text(
          'Stack\nthe Cats',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 48,
            height: 1.05,
            fontWeight: FontWeight.w900,
            color: _brown,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(width: 180, height: 215, child: _MenuCats(key: _catsKey)),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              padding: const EdgeInsets.symmetric(vertical: 18),
            ),
            onPressed: _play,
            child: const Text(
              'Play',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        // Only for signed-in players (offline counts as signed out).
        ValueListenableBuilder<PlayerData?>(
          valueListenable: _player,
          builder: (context, data, _) => data == null
              ? const SizedBox.shrink()
              : Column(
                  children: [
                    const SizedBox(height: 12),
                    _MenuButton(
                      icon: Icons.emoji_events_rounded,
                      label: 'Challenges',
                      onPressed: () => _open(const ChallengeModesScreen()),
                    ),
                    const SizedBox(height: 12),
                    // Leaderboard and Friends side by side (no Friends
                    // in kids' mode).
                    Row(
                      children: [
                        Expanded(
                          child: _MenuButton(
                            icon: Icons.leaderboard_rounded,
                            label: 'Leaderboard',
                            onPressed: () => _open(const LeaderboardScreen()),
                          ),
                        ),
                        if (!AgeGate.instance.isKid) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            // Shows how many friend requests are waiting.
                            child: ValueListenableBuilder<List<FriendRequest>>(
                              valueListenable: FriendsService.instance.incoming,
                              builder: (context, requests, _) => _MenuButton(
                                icon: Icons.group_rounded,
                                label: 'Friends',
                                badge: requests.length,
                                onPressed: () => _open(const FriendsScreen()),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        // Settings and (for signed-in players) the Store, side by side.
        ValueListenableBuilder<PlayerData?>(
          valueListenable: _player,
          builder: (context, data, _) => Row(
            children: [
              Expanded(
                child: _MenuButton(
                  icon: Icons.settings_rounded,
                  label: 'Settings',
                  onPressed: () => _open(const SettingsScreen()),
                ),
              ),
              if (data != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _MenuButton(
                    icon: Icons.storefront_rounded,
                    label: 'Store',
                    onPressed: () => _open(const StoreScreen()),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        const AccountPanel(),
      ],
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  /// A little count bubble, e.g. waiting friend requests. Hidden when 0.
  final int badge;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: _brown,
          side: const BorderSide(color: _brown, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        onPressed: onPressed,
        icon: Badge(
          isLabelVisible: badge > 0,
          backgroundColor: _accent,
          label: Text('$badge'),
          child: Icon(icon),
        ),
        label: Text(label, style: const TextStyle(fontSize: 18)),
      ),
    );
  }
}

/// The title screen's stack of three cats. They drop in one at a time when
/// the menu appears, then do a tiny hop every [hopEvery] while it's open.
class _MenuCats extends StatefulWidget {
  const _MenuCats({super.key});

  static const hopEvery = Duration(seconds: 30);

  @override
  State<_MenuCats> createState() => _MenuCatsState();
}

class _MenuCatsState extends State<_MenuCats> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: Duration(
      milliseconds: (_MenuCatsPainter.introSeconds * 1000).round(),
    ),
  );
  late final AnimationController _hop = AnimationController(
    vsync: this,
    duration: Duration(
      milliseconds: (_MenuCatsPainter.hopSeconds * 1000).round(),
    ),
  );
  Timer? _hopTimer;

  @override
  void initState() {
    super.initState();
    // Wait for the loading screen to finish fading out.
    playIntro(after: const Duration(milliseconds: 550));
  }

  Timer? _introDelay;

  /// Drops the cats in again, e.g. when coming back to the menu. [after]
  /// lets a screen transition finish first; the cats stay hidden meanwhile.
  void playIntro({Duration after = const Duration(milliseconds: 300)}) {
    _hop.reset();
    _intro.value = 0; // all hidden until the drop starts
    _introDelay?.cancel();
    _introDelay = Timer(after, () {
      if (mounted) _intro.forward(from: 0);
    });
    _hopTimer?.cancel();
    _hopTimer = Timer.periodic(_MenuCats.hopEvery, (_) {
      // Only while the menu is actually on screen.
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        _hop.forward(from: 0);
      }
    });
  }

  @override
  void dispose() {
    _hopTimer?.cancel();
    _introDelay?.cancel();
    _intro.dispose();
    _hop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_intro, _hop]),
      builder: (context, _) => CustomPaint(
        painter: _MenuCatsPainter(
          introTime: _intro.value * _MenuCatsPainter.introSeconds,
          hopTime: _hop.isAnimating
              ? _hop.value * _MenuCatsPainter.hopSeconds
              : null,
        ),
      ),
    );
  }
}

/// Draws the three cats, partway through dropping in or hopping.
class _MenuCatsPainter extends CustomPainter {
  const _MenuCatsPainter({required this.introTime, required this.hopTime});

  /// Seconds into the drop-in (finished once past [introSeconds]).
  final double introTime;

  /// Seconds into a hop, or null when not hopping.
  final double? hopTime;

  // Drop-in: each cat starts [_dropGap] after the one below it, falls for
  // [_fallTime], then squashes as it lands.
  static const _dropGap = 0.22;
  static const _fallTime = 0.32;
  static const _squashTime = 0.18;
  static const _fallFrom = 45.0;
  static const introSeconds = 2 * _dropGap + _fallTime + _squashTime;

  // Hop: a small wave from the bottom cat to the top one.
  static const _hopGap = 0.07;
  static const _hopTime = 0.32;
  static const _hopHeight = 7.0;
  static const hopSeconds = 2 * _hopGap + _hopTime;

  static const _looks = [
    CatLook(breed: Cats.grey, striped: false, tailRight: false, sleepy: true),
    CatLook(breed: Cats.black, striped: false, tailRight: true, sleepy: false),
    CatLook(breed: Cats.ginger, striped: true, tailRight: false, sleepy: false),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * 0.62;
    final h = w * 0.58;
    final offsets = [0.0, -8.0, 6.0];
    // Falling cats appear from just above their spot, never over the title
    // (room is left at the sides for tails).
    canvas.clipRect(Rect.fromLTRB(-60, -40, size.width + 60, size.height + 10));
    for (int i = 0; i < _looks.length; i++) {
      var cy = size.height - h / 2 - i * h;
      var squash = 0.0;
      var opacity = 1.0;

      // Dropping in: hidden until its turn, then falls, fades in, squashes.
      final local = introTime - i * _dropGap;
      if (local < 0) continue;
      if (local < _fallTime) {
        final p = local / _fallTime;
        cy -= (1 - Curves.easeIn.transform(p)) * _fallFrom;
        opacity = Curves.easeOut.transform(p);
      } else if (local < _fallTime + _squashTime) {
        squash = 1 - (local - _fallTime) / _squashTime;
      }

      // Hopping: a little arc, each cat just after the one below.
      final hop = hopTime;
      if (hop != null) {
        final p = ((hop - i * _hopGap) / _hopTime).clamp(0.0, 1.0);
        cy -= sin(p * pi) * _hopHeight;
      }

      final center = Offset(size.width / 2 + offsets[i], cy);
      if (opacity < 1) {
        canvas.saveLayer(
          null,
          Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
        );
      }
      paintCat(canvas, _looks[i], center, w, h, squash: squash);
      if (opacity < 1) canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_MenuCatsPainter old) =>
      old.introTime != introTime || old.hopTime != hopTime;
}
