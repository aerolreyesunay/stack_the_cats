import 'dart:math';

import '../store/catalog.dart';

/// Prices and rewards for Treats, the in-game currency.
class Treats {
  Treats._();

  // ---------- Spending ----------
  static const realignCost = 250;

  /// Revive costs [reviveBaseCost] for towers up to [reviveBaseCats] cats,
  /// then [reviveCostPerExtraCat] more for every cat above that
  /// (e.g. 60 cats = 280).
  static const reviveBaseCost = 250;
  static const reviveBaseCats = 50;
  static const reviveCostPerExtraCat = 3;

  static int reviveCostFor(int score) =>
      reviveBaseCost + reviveCostPerExtraCat * max(0, score - reviveBaseCats);

  // ---------- Earning ----------
  /// Daily sign-in rewards for day 1-7 of a streak.
  static const dailyRewards = [10, 20, 30, 50, 75, 100, 200];

  /// After this many perfects in a row, every further perfect pays.
  static const perfectStreakStart = 3;
  static const perfectStreakReward = 10;

  /// Paid each time a run reaches a multiple of this many cats, except
  /// where a Tuna or Salmon is given instead (see [Fish.forMilestone]).
  static const stackMilestone = 50;
  static const stackMilestoneReward = 50;

  static const shareReward = 1;
  static const maxPaidSharesPerDay = 50;
  static const friendJoinedReward = 200;

  /// The new player must stack this many cats before their inviter is paid
  /// (the server checks it).
  static const referralMinLandings = 100;

  /// The most normal games pay one account per day (UTC). The server keeps
  /// the same limit.
  static const dailyGameTreats = 2000;
  static const dailyGameTuna = 3;
  static const dailyGameSalmon = 2;

  /// Paid to both players when a friend request is accepted.
  static const friendAcceptedReward = 5;

  /// Given once, when a player signs in for the very first time. (Also
  /// hard-coded in firestore.rules: keep the two the same.)
  static const welcomeBonus = 300;

  /// Treats for watching a rewarded video in the Store when short, a few
  /// times a day.
  static const storeAdReward = 100;
  static const maxStoreAdsPerDay = 10;

  /// Purrfect bonuses for Store cats (see [CatTier]).
  static const specialPerfectBonus = 1;
  static const specialStreakBonus = 3;
  static const exoticPerfectBonus = 5;
  static const exoticStreakMultiplier = 2;

  /// Treats earned by a landing, given the perfect streak *after* it
  /// (0 if it wasn't perfect), the score after it, and the landed cat's
  /// tier.
  ///
  /// A Purrfect outside a streak pays nothing for basic cats, +1 for
  /// Special and +5 for Exotic. In a streak (from the 4th in a row) it pays
  /// 10 for basic cats, 10 + 3 for Special and 10 × 2 for Exotic.
  static int forLanding({
    required int combo,
    required int score,
    CatTier tier = CatTier.basic,
  }) {
    var earned = 0;
    final perfect = combo > 0;
    final inStreak = combo > perfectStreakStart;
    if (inStreak) {
      earned += switch (tier) {
        CatTier.basic => perfectStreakReward,
        CatTier.special => perfectStreakReward + specialStreakBonus,
        CatTier.exotic => perfectStreakReward * exoticStreakMultiplier,
      };
    } else if (perfect) {
      earned += switch (tier) {
        CatTier.basic => 0,
        CatTier.special => specialPerfectBonus,
        CatTier.exotic => exoticPerfectBonus,
      };
    }
    if (score > 0 &&
        score % stackMilestone == 0 &&
        Fish.forMilestone(score) == null) {
      earned += stackMilestoneReward;
    }
    return earned;
  }
}

/// The rarer currencies: a Tuna or a Salmon.
enum Fish {
  tuna(treatValue: 250, label: 'Tuna'),
  salmon(treatValue: 375, label: 'Salmon');

  const Fish({required this.treatValue, required this.label});

  /// Treats given for one in the Store exchange.
  final int treatValue;
  final String label;

  /// A Tuna every [tunaEvery] cats in a normal game, and a Salmon (instead
  /// of the Tuna) every [salmonEvery]; both replace that milestone's treats.
  static const tunaEvery = 100;
  static const salmonEvery = 200;

  /// The fish given for reaching [score] cats in a normal game, if any.
  static Fish? forMilestone(int score) {
    if (score <= 0) return null;
    if (score % salmonEvery == 0) return Fish.salmon;
    if (score % tunaEvery == 0) return Fish.tuna;
    return null;
  }
}

/// How many times something can be bought in one game with each way of
/// paying (revive: treats, Salmon or an ad; realign: treats, Tuna or an
/// ad).
enum PayWith {
  treats(limit: 2),
  fish(limit: 3),
  ad(limit: 3);

  const PayWith({required this.limit});
  final int limit;
}

/// Uses of revive (or realign) so far this game, per way of paying.
class UseCounter {
  final Map<PayWith, int> _used = {};

  int used(PayWith how) => _used[how] ?? 0;
  int left(PayWith how) => how.limit - used(how);
  bool canUse(PayWith how) => left(how) > 0;
  bool get anyLeft => PayWith.values.any(canUse);

  void use(PayWith how) => _used[how] = used(how) + 1;
  void reset() => _used.clear();
}

/// The Self Challenge: reach [goal] cats with one tower and fixed speeds.
class SelfChallenge {
  SelfChallenge._();

  static const cost = 25;
  static const goal = 100;

  /// 300 up to 25 cats, 350 up to 50, 425 up to 75, then 500.
  static double swingSpeedFor(int score) {
    if (score < 25) return 300;
    if (score < 50) return 350;
    if (score < 75) return 425;
    return 500;
  }

  /// What a run that reached [score] cats wins: 50-74 a Tuna, 75-99 a
  /// Salmon, and the full 100 both.
  static ({int tuna, int salmon}) rewardFor(int score) {
    if (score >= goal) return (tuna: 1, salmon: 1);
    if (score >= 75) return (tuna: 0, salmon: 1);
    if (score >= 50) return (tuna: 1, salmon: 0);
    return (tuna: 0, salmon: 0);
  }
}

/// Live matches against a random opponent.
class MatchPrizes {
  MatchPrizes._();

  /// Friendly matches (and challenges between friends).
  static const friendlyWin = 30;
  static const friendlyLose = 10;
  static const friendlyDraw = 20;

  /// Treat wagers: both players stake the amount, the winner takes both.
  static const wagers = [100, 200, 300, 500];
}

/// Where a player is in the 7-day sign-in streak.
class DailyStatus {
  const DailyStatus({required this.day, required this.claimable});

  /// The streak day (1-7) that can be claimed now, or that was claimed today.
  final int day;
  final bool claimable;

  int get reward => Treats.dailyRewards[day - 1];

  /// [lastClaim] is the local date of the last claim ('yyyy-mm-dd'), and
  /// [lastDay] the streak day claimed then. A missed day or finishing
  /// day 7 starts the streak over at day 1.
  static DailyStatus compute({
    required String? lastClaim,
    required int lastDay,
    required DateTime now,
  }) {
    final today = dateKey(now);
    if (lastClaim == today) {
      return DailyStatus(day: lastDay.clamp(1, 7), claimable: false);
    }
    final yesterday = dateKey(DateTime(now.year, now.month, now.day - 1));
    final continues = lastClaim == yesterday && lastDay >= 1 && lastDay < 7;
    return DailyStatus(day: continues ? lastDay + 1 : 1, claimable: true);
  }

  /// A local calendar date as 'yyyy-mm-dd'.
  static String dateKey(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';
}
