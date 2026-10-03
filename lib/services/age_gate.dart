import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The player's birth year, asked once on the first launch, which decides
/// whether the game runs in kids' mode.
///
/// Kids' mode (under 13) shows only child-safe ads, signs in with an
/// anonymous account under a made-up name (no Google or Facebook), and turns
/// off friends, invites, live matches and wagers. The server holds the same
/// limits for anonymous accounts.
class AgeGate {
  AgeGate._();
  static final AgeGate instance = AgeGate._();

  static const _key = 'birthYear';

  int? _birthYear;

  /// Whether the birth year has been asked yet.
  bool get known => _birthYear != null;

  /// Kids' mode. True until the age is known, so nothing that isn't safe
  /// for children starts before then.
  bool get isKid => isKidBornIn(_birthYear, DateTime.now().year);

  /// Under 13, by birth year. Someone who turns 13 this year may still be
  /// 12, so they count as a kid too.
  @visibleForTesting
  static bool isKidBornIn(int? birthYear, int thisYear) =>
      birthYear == null || thisYear - birthYear <= 13;

  /// The years offered, newest first.
  static List<int> yearsToPick(int thisYear) => [
    for (var y = thisYear; y >= thisYear - 100; y--) y,
  ];

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _birthYear = prefs.getInt(_key);
    } catch (e) {
      debugPrint('Age not loaded: $e');
    }
  }

  Future<void> setBirthYear(int year) async {
    _birthYear = year;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key, year);
    } catch (e) {
      debugPrint('Age not saved: $e');
    }
  }
}

/// The made-up name a kids' mode player goes by on leaderboards, e.g.
/// "Sleepy Kitten 42". The same for the same account every time, and the
/// server works out the same name (functions/src/economy.ts, kidName).
class KidName {
  KidName._();

  static const _adjectives = [
    'Sleepy',
    'Fluffy',
    'Happy',
    'Brave',
    'Tiny',
    'Speedy',
    'Sunny',
    'Cozy',
    'Jolly',
    'Snowy',
    'Lucky',
    'Bouncy',
    'Silly',
    'Clever',
    'Gentle',
    'Mighty',
  ];
  static const _nouns = [
    'Kitten',
    'Tabby',
    'Whiskers',
    'Paws',
    'Mittens',
    'Purrball',
    'Tiger',
    'Pebble',
    'Biscuit',
    'Muffin',
    'Noodle',
    'Pumpkin',
    'Socks',
    'Button',
    'Pudding',
    'Mochi',
  ];

  static String forUid(String uid) {
    // FNV-1a, 32 bits.
    var h = 2166136261;
    for (final c in uid.codeUnits) {
      h = ((h ^ c) * 16777619) & 0xFFFFFFFF;
    }
    return '${_adjectives[h % 16]} ${_nouns[(h >> 4) % 16]} '
        '${10 + (h >> 8) % 90}';
  }
}
