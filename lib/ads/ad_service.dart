import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../audio/audio_manager.dart';
import '../services/connectivity_service.dart';
import 'ad_pacing.dart';

/// AdMob ad unit ids.
///
/// These are Google's official TEST ads. Never show real ads while
/// developing: tapping your own real ads can get the AdMob account banned.
/// Before publishing, replace them with the ids from your AdMob account
/// (and the app id in android/app/src/main/AndroidManifest.xml).
class AdIds {
  AdIds._();

  static const banner = 'ca-app-pub-3940256099942544/9214589741';
  static const interstitial = 'ca-app-pub-3940256099942544/1033173712';
  static const rewarded = 'ca-app-pub-3940256099942544/5224354917';
}

/// Banners, a full-screen ad every few games, and optional rewarded ads
/// ("watch an ad to revive").
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  /// True once ads may be requested (consent handled, SDK started).
  final ValueNotifier<bool> ready = ValueNotifier(false);

  /// True while a rewarded ad is loaded and can be offered.
  final ValueNotifier<bool> rewardedReady = ValueNotifier(false);

  final AdPacing _pacing = AdPacing();
  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  bool _starting = false;

  bool get _online => ConnectivityService.instance.isOnline;

  /// Asks for consent where the law requires it (e.g. Europe), then starts
  /// the ads SDK and preloads ads. Safe to call more than once.
  Future<void> start() async {
    if (ready.value || _starting) return;
    _starting = true;
    try {
      await _gatherConsent();
      if (!await ConsentInformation.instance.canRequestAds()) return;
      await MobileAds.instance.initialize();
      ready.value = true;
      _loadInterstitial();
      _loadRewarded();
    } catch (e) {
      debugPrint('Ads failed to start: $e');
    } finally {
      _starting = false;
    }
  }

  Future<void> _gatherConsent() {
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => ConsentForm.loadAndShowConsentFormIfRequired((error) {
        if (error != null) debugPrint('Consent form: ${error.message}');
        if (!done.isCompleted) done.complete();
      }),
      (error) {
        debugPrint('Consent info: ${error.message}');
        if (!done.isCompleted) done.complete();
      },
    );
    return done.future;
  }

  // ---------- Full-screen ads between games ----------

  void _loadInterstitial() {
    if (!ready.value || !_online || _interstitial != null) return;
    InterstitialAd.load(
      adUnitId: AdIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (e) => debugPrint('Interstitial failed: $e'),
      ),
    );
  }

  /// Call whenever a game ends.
  void gameFinished() => _pacing.gameFinished();

  /// Shows a full-screen ad if one is due (every 5 games), and waits until
  /// it's closed. Does nothing otherwise.
  Future<void> maybeShowBetweenGames() async {
    final ad = _interstitial;
    if (ad == null || !_pacing.isDue(DateTime.now())) {
      _loadInterstitial();
      return;
    }
    _interstitial = null;
    _pacing.adShown(DateTime.now());
    await _showFullScreen(ad, (ad) => ad.show());
    _loadInterstitial();
  }

  // ---------- Rewarded ads ----------

  void _loadRewarded() {
    if (!ready.value || !_online || _rewarded != null) return;
    RewardedAd.load(
      adUnitId: AdIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewarded = ad;
          rewardedReady.value = true;
        },
        onAdFailedToLoad: (e) => debugPrint('Rewarded failed: $e'),
      ),
    );
  }

  /// Plays a rewarded ad. Returns true only if the player watched it to the
  /// end (and so earned the reward).
  Future<bool> showRewarded() async {
    final ad = _rewarded;
    if (ad == null) return false;
    _rewarded = null;
    rewardedReady.value = false;
    var earned = false;
    await _showFullScreen(
      ad,
      (ad) => ad.show(onUserEarnedReward: (_, _) => earned = true),
    );
    _loadRewarded();
    return earned;
  }

  /// Shows a full-screen ad with the game's sound paused, and completes
  /// when it's closed.
  Future<void> _showFullScreen<T extends AdWithoutView>(
    T ad,
    Future<void> Function(T ad) show,
  ) async {
    final closed = Completer<void>();
    final callback = FullScreenContentCallback<T>(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('Ad failed to show: $error');
        ad.dispose();
        if (!closed.isCompleted) closed.complete();
      },
    );
    if (ad is InterstitialAd) {
      ad.fullScreenContentCallback =
          callback as FullScreenContentCallback<InterstitialAd>;
    } else if (ad is RewardedAd) {
      ad.fullScreenContentCallback =
          callback as FullScreenContentCallback<RewardedAd>;
    }
    final audio = AudioManager.instance;
    audio.stopAllSfx();
    audio.pauseMusic();
    try {
      await show(ad);
      await closed.future;
    } finally {
      audio.resumeMusic();
    }
  }
}
