import 'dart:async';

import 'package:flutter/foundation.dart';

import '../economy/treats.dart';
import '../store/catalog.dart';
import 'player_service.dart';
import 'server_api.dart';

/// One signed-in game, as the server sees it.
///
/// The server pays for landings itself: the game reports each cat that
/// lands (its perfect streak and tier) in small batches, and the server
/// works out the treats, Tuna and Salmon with the same rules. Meanwhile
/// they show on screen straight away. Revive and realign are paid through
/// here too, so the server can price them and hold the per-game limits.
///
/// Calls go to the server one at a time, in order.
class GameSession {
  GameSession._(this.isSelfChallenge, {this.batchSize = 10});

  final bool isSelfChallenge;

  /// Cats reported in one go (fewer at the end, or before a revive). Live
  /// matches report every cat straight away: the server decides the
  /// result from the cats it has counted.
  final int batchSize;

  final _player = PlayerService.instance;

  String? _gameId;
  bool _broken = false;

  /// One queue for all games, so a finished game's last cats reach the
  /// server before the next game starts (the server only lets the newest
  /// game earn).
  static Future<void> _queue = Future.value();

  final List<Map<String, Object>> _batch = [];
  String _batchOpId = ServerApi.newOpId();

  /// Starts a normal game (in the background: nothing is paid), with the
  /// wallpaper it starts with (a premium one pays double treats at times).
  static GameSession? startNormal(String wallpaperId) {
    if (!PlayerService.instance.signedIn) return null;
    final session = GameSession._(false);
    GameSession._enqueue(() async {
      final result = await session._player.run('startGame', {
        'mode': 'normal',
        'wallpaperId': wallpaperId,
      }, quiet: true);
      session._gameId = result?['gameId'] as String?;
    });
    return session;
  }

  /// This player's side of a live match (nothing is paid until the end).
  static GameSession? startMatch(String matchId) {
    if (!PlayerService.instance.signedIn) return null;
    final session = GameSession._(false, batchSize: 1);
    GameSession._enqueue(() async {
      final result = await session._player.run('startGame', {
        'mode': 'match',
        'matchId': matchId,
      }, quiet: true);
      session._gameId = result?['gameId'] as String?;
    });
    return session;
  }

  /// Starts a Self Challenge, paying its entry. Returns null (and reports
  /// why) if it couldn't start.
  static Future<GameSession?> startSelfChallenge() async {
    final player = PlayerService.instance;
    const fee = WalletChange(treats: -SelfChallenge.cost);
    if (!player.canAfford(fee)) {
      player.problem.value = const ServerError('not-enough-treats');
      return null;
    }
    final started = Completer<String?>();
    _enqueue(() async {
      final result = await player.run('startGame', {
        'mode': 'self',
      }, change: fee);
      started.complete(result?['gameId'] as String?);
    });
    final gameId = await started.future;
    if (gameId == null) return null;
    return GameSession._(true).._gameId = gameId;
  }

  static void _enqueue(Future<void> Function() task) {
    _queue = _queue.then((_) => task()).catchError((Object e) {
      debugPrint('Game session: $e');
    });
  }

  /// A cat landed and the tower held. [treats] and [fish] are what the
  /// game shows for it (the server pays the same).
  void landed({
    required int combo,
    required CatTier tier,
    required int atMs,
    int treats = 0,
    Fish? fish,
  }) {
    if (_broken) return;
    _batch.add({'combo': combo, 'tier': tier.name, 't': atMs});
    final change = WalletChange(
      treats: treats,
      tuna: fish == Fish.tuna ? 1 : 0,
      salmon: fish == Fish.salmon ? 1 : 0,
      fromGame: true,
    );
    if (treats != 0 || fish != null) _player.showPending(_batchOpId, change);
    if (_batch.length >= batchSize) flush();
  }

  /// Sends the cats landed so far.
  void flush() {
    if (_batch.isEmpty || _broken) return;
    final landings = List.of(_batch);
    final opId = _batchOpId;
    _batch.clear();
    _batchOpId = ServerApi.newOpId();
    _enqueue(() async {
      final gameId = _gameId;
      if (gameId == null) {
        // The game never started on the server: nothing can be paid.
        _player.dropPending(opId);
        return;
      }
      try {
        await ServerApi.instance.call('landings', {
          'opId': opId,
          'gameId': gameId,
          'landings': landings,
        });
      } on ServerError catch (e) {
        _player.dropPending(opId);
        // Refused: stop reporting this game.
        if (e.reason != 'offline') _broken = true;
      }
    });
  }

  /// Pays for a revive or realign with [payWith], shown straight away.
  /// Returns false if the player can't afford [cost].
  bool buyUse({
    required String kind,
    required PayWith payWith,
    WalletChange cost = WalletChange.none,
  }) {
    if (!_player.canAfford(cost)) return false;
    flush(); // so the server prices it from the same score
    final opId = ServerApi.newOpId();
    _player.showPending(opId, cost);
    _enqueue(() async {
      final gameId = _gameId;
      if (gameId == null) return _player.dropPending(opId);
      try {
        await ServerApi.instance.call('buyUse', {
          'opId': opId,
          'gameId': gameId,
          'kind': kind,
          'payWith': payWith.name,
        });
      } on ServerError catch (e) {
        _player.dropPending(opId);
        _player.problem.value = e;
      }
    });
    return true;
  }

  bool _ended = false;

  /// Ends the game. The Self Challenge's Tuna and Salmon for [score] show
  /// straight away; the server pays them for the score it counted.
  void end({int score = 0}) {
    if (_ended) return;
    _ended = true;
    flush();
    final opId = ServerApi.newOpId();
    if (isSelfChallenge) {
      final reward = SelfChallenge.rewardFor(score);
      _player.showPending(
        opId,
        WalletChange(tuna: reward.tuna, salmon: reward.salmon),
      );
    }
    _enqueue(() async {
      final gameId = _gameId;
      if (gameId == null) return _player.dropPending(opId);
      try {
        await ServerApi.instance.call('endGame', {
          'opId': opId,
          'gameId': gameId,
        });
      } on ServerError {
        _player.dropPending(opId);
      }
    });
  }
}
