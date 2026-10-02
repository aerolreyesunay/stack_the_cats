import '../economy/treats.dart';

/// One player's side of a live challenge, as seen by the other.
class Racer {
  const Racer({
    required this.score,
    required this.alive,
    this.forfeited = false,
  });

  final int score;

  /// Still stacking (their tower hasn't fallen yet).
  final bool alive;

  /// Left the match or lost connection for too long.
  final bool forfeited;
}

enum MatchOutcome { undecided, win, lose, draw }

/// Who has won a challenge, from [me]'s point of view.
///
/// The match is decided as soon as the result can't change: once a tower
/// has fallen, the other player wins the moment they pass that score, so
/// nobody has to keep stacking forever. If both towers fall, the higher
/// score wins and equal scores are a draw.
MatchOutcome outcomeFor(Racer me, Racer them) {
  if (me.forfeited && them.forfeited) return MatchOutcome.draw;
  if (them.forfeited) return MatchOutcome.win;
  if (me.forfeited) return MatchOutcome.lose;

  if (!them.alive && me.score > them.score) return MatchOutcome.win;
  if (!me.alive && them.score > me.score) return MatchOutcome.lose;

  if (!me.alive && !them.alive) {
    if (me.score > them.score) return MatchOutcome.win;
    if (me.score < them.score) return MatchOutcome.lose;
    return MatchOutcome.draw;
  }
  return MatchOutcome.undecided;
}

/// What a live match is played for: a Friendly (small prizes for both) or a
/// treat wager (both stake, the winner takes both stakes).
class MatchStakes {
  const MatchStakes.friendly() : wager = 0;
  const MatchStakes.wager(this.wager);

  /// From a match's saved 'stake' (0 or missing = Friendly).
  factory MatchStakes.fromStake(int? stake) => (stake ?? 0) > 0
      ? MatchStakes.wager(stake!)
      : const MatchStakes.friendly();

  /// Treats each player stakes (0 for a Friendly).
  final int wager;

  bool get isWager => wager > 0;

  /// Players looking for the same stakes are matched with each other.
  String get queueKey => isWager ? 'wager$wager' : 'friendly';

  /// Treats paid to a player at the end. In a wager the stake was already
  /// taken, so a win pays both stakes back and a draw returns your own.
  int prizeFor(MatchOutcome outcome) => isWager
      ? switch (outcome) {
          MatchOutcome.win => wager * 2,
          MatchOutcome.draw => wager,
          _ => 0,
        }
      : switch (outcome) {
          MatchOutcome.win => MatchPrizes.friendlyWin,
          MatchOutcome.lose => MatchPrizes.friendlyLose,
          MatchOutcome.draw => MatchPrizes.friendlyDraw,
          MatchOutcome.undecided => 0,
        };

  @override
  bool operator ==(Object other) =>
      other is MatchStakes && other.wager == wager;

  @override
  int get hashCode => wager.hashCode;
}
