import 'dart:async';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/audio_manager.dart';
import '../ads/ad_service.dart';
import '../challenge/challenge_service.dart';
import '../auth/auth_service.dart';
import '../services/age_gate.dart';
import '../services/connectivity_service.dart';
import '../services/friends_service.dart';
import '../services/leaderboard_service.dart';
import '../services/player_service.dart';
import '../services/server_api.dart';
import 'age_gate_screen.dart';
import 'main_menu_screen.dart';

const _background = Color(0xFF0E0F1A); // matches the logo's background
const _accent = Color(0xFFFF6B4A); // the logo's coral triangle
const _track = Color(0xFF262838);

/// Studio logo and a progress bar while the game gets ready, then the menu.
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  /// Keeps the logo up long enough to be seen, even on a fast phone.
  static const minDuration = Duration(milliseconds: 1500);

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  /// How much of the game has really loaded, 0.0-1.0.
  double _progress = 0;

  /// Runs 0.0-1.0 over [LoadingScreen.minDuration]. The bar shows whichever
  /// is lower, so it fills steadily instead of jumping to full on a fast phone.
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: LoadingScreen.minDuration,
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  void _setProgress(double value) {
    if (mounted) setState(() => _progress = value);
  }

  Future<void> _load() async {
    await Future.wait([_loadGame(), _clock.forward()]);
    _setProgress(1);
    // Let the bar finish filling before leaving.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    // The first launch asks the birth year before anything that depends on
    // it (ads, accounts, friends) starts.
    if (!AgeGate.instance.known) {
      final year = await Navigator.of(context)
          .push<int>(MaterialPageRoute(builder: (_) => const AgeGateScreen()));
      if (year != null) await AgeGate.instance.setBirthYear(year);
      _startForAge();
      if (!mounted) return;
    }
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, _, _) => const MainMenuScreen(),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  /// Firebase is the first 20% of the bar, the sounds are the rest.
  Future<void> _loadGame() async {
    // Find out whether we're online while Firebase starts up.
    final connectionChecked = ConnectivityService.instance.start();
    try {
      // On Android the settings come from android/app/google-services.json.
      await Firebase.initializeApp();
      await connectEmulatorsIfAsked();
      await startAppCheck();
    } catch (e) {
      debugPrint('Firebase init failed: $e');
    }
    await connectionChecked;
    await AgeGate.instance.load();
    PlayerService.instance.start();
    LeaderboardService.instance.start();
    if (AgeGate.instance.known) _startForAge();
    _setProgress(0.2);
    await AudioManager.instance.init(
      onProgress: (p) => _setProgress(0.2 + p * 0.8),
    );
  }

  /// What depends on the player's age: kids get an anonymous account and
  /// child-safe ads; everyone else gets friends and live matches too.
  void _startForAge() {
    if (AgeGate.instance.isKid) {
      unawaited(AuthService.instance.startKidsAccount());
    } else {
      FriendsService.instance.start();
      ChallengeService.instance.start();
    }
    // Ads start in the background (with the consent pop-up where needed).
    unawaited(AdService.instance.start());
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Light status bar icons so they show on the dark background.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/branding/jcan_dark.png',
                width: (width * 0.95).clamp(0, 520),
              ),
              SizedBox(
                width: (width * 0.5).clamp(0, 260),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: _progress),
                  duration: const Duration(milliseconds: 250),
                  builder: (_, loaded, _) => AnimatedBuilder(
                    animation: _clock,
                    builder: (_, _) => LinearProgressIndicator(
                      value: min(loaded, _clock.value),
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                      color: _accent,
                      backgroundColor: _track,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
