/// When a full-screen ad is due: after every [gamesBetweenAds] finished
/// games, and never twice within [minGap] (so quick restarts don't get a
/// burst of ads).
class AdPacing {
  AdPacing({
    this.gamesBetweenAds = 3,
    this.minGap = const Duration(seconds: 90),
  });

  final int gamesBetweenAds;
  final Duration minGap;

  int _gamesSinceAd = 0;
  DateTime? _lastAdAt;

  int get gamesSinceAd => _gamesSinceAd;

  /// Call when a game ends.
  void gameFinished() => _gamesSinceAd++;

  bool isDue(DateTime now) {
    if (_gamesSinceAd < gamesBetweenAds) return false;
    final last = _lastAdAt;
    return last == null || now.difference(last) >= minGap;
  }

  /// Call after a full-screen ad was shown.
  void adShown(DateTime now) {
    _gamesSinceAd = 0;
    _lastAdAt = now;
  }
}
