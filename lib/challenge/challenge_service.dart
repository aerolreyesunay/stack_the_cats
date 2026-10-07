import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../auth/auth_service.dart';
import '../services/connectivity_service.dart';
import '../services/player_service.dart';
import '../services/public_name.dart';
import '../services/server_api.dart';
import 'match_rules.dart';

/// The Realtime Database (live presence and matches). Firestore keeps
/// everything else.
const rtdbUrl =
    'https://stack-the-cats-9538a-default-rtdb.asia-southeast1.firebasedatabase.app';

/// Where a player is, as their friends see it.
enum Presence { offline, online, playing }

/// A challenge another player sent this player.
class ChallengeInvite {
  const ChallengeInvite({
    required this.from,
    required this.name,
    required this.photoUrl,
    required this.matchId,
    required this.sentAt,
  });

  final String from;
  final String name;
  final String? photoUrl;
  final String matchId;
  final DateTime sentAt;
}

/// Where a match is up to.
enum MatchState { invited, countdown, declined, cancelled, finished }

/// One player in a match, as stored.
class MatchPlayer {
  const MatchPlayer({
    required this.uid,
    required this.name,
    required this.photoUrl,
    required this.score,
    required this.alive,
    required this.joined,
    required this.connected,
    required this.left,
  });

  final String uid;
  final String name;
  final String? photoUrl;
  final int score;
  final bool alive;
  final bool joined;
  final bool connected;

  /// Pressed "leave" (forfeits).
  final bool left;

  factory MatchPlayer.fromMap(String uid, Map<Object?, Object?> m) =>
      MatchPlayer(
        uid: uid,
        name: (m['name'] as String?) ?? 'Cat stacker',
        photoUrl: m['photo'] as String?,
        score: (m['score'] as num?)?.toInt() ?? 0,
        alive: m['alive'] != false,
        joined: m['joined'] == true,
        connected: m['connected'] != false,
        left: m['left'] == true,
      );
}

/// A live view of a match.
class Match {
  const Match({
    required this.id,
    required this.seed,
    required this.state,
    required this.startAt,
    required this.me,
    required this.them,
    required this.stakes,
  });

  final String id;
  final int seed;
  final MatchState state;

  /// Friendly or a treat wager.
  final MatchStakes stakes;

  /// When the countdown ends and both players start (server time).
  final DateTime? startAt;
  final MatchPlayer me;
  final MatchPlayer them;

  static Match? fromSnapshot(String id, String myUid, DataSnapshot snap) {
    final data = snap.value;
    if (data is! Map) return null;
    final players = (data['players'] as Map?) ?? const {};
    final mine = players[myUid];
    final otherUid = players.keys.cast<String>().firstWhere(
      (k) => k != myUid,
      orElse: () => '',
    );
    final theirs = players[otherUid];
    if (mine is! Map || theirs is! Map) return null;
    final startMs = (data['startAt'] as num?)?.toInt();
    return Match(
      id: id,
      seed: (data['seed'] as num?)?.toInt() ?? 0,
      state: MatchState.values.firstWhere(
        (s) => s.name == data['state'],
        orElse: () => MatchState.invited,
      ),
      startAt: startMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(startMs),
      me: MatchPlayer.fromMap(myUid, mine),
      them: MatchPlayer.fromMap(otherUid, theirs),
      stakes: MatchStakes.fromStake((data['stake'] as num?)?.toInt()),
    );
  }
}

/// Live presence and head-to-head challenges.
///
/// Realtime Database layout:
///   status/{uid}            'online' | 'playing' | 'offline' (+ name)
///   invites/{to}/{from}     a pending challenge for {to}
///   matches/{matchId}       seed, state, startAt, stake and both players'
///                           live score / alive / joined / connected
///   queue/{stakes}/{uid}    a player looking for a random opponent
class ChallengeService {
  ChallengeService._();
  static final ChallengeService instance = ChallengeService._();

  /// How long a challenge waits for an answer.
  static const answerWindow = Duration(seconds: 30);

  /// How long a player can be disconnected before they forfeit.
  static const forfeitAfter = Duration(seconds: 30);

  /// Countdown before both players start.
  static const countdown = Duration(seconds: 4);

  /// How long a matched opponent has to turn up before the match is
  /// called off (and any stake returned).
  static const joinWindow = Duration(seconds: 12);

  /// The newest unanswered challenge for this player, or null.
  final ValueNotifier<ChallengeInvite?> incoming = ValueNotifier(null);

  FirebaseDatabase get _rtdb =>
      FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: rtdbUrl);

  String? get _uid => AuthService.instance.currentUser?.uid;

  /// Server clock minus this phone's clock, so both phones agree on when
  /// the countdown ends.
  int _serverOffsetMs = 0;
  DateTime get serverNow =>
      DateTime.now().add(Duration(milliseconds: _serverOffsetMs));

  bool _started = false;
  String? _listeningFor;
  final List<StreamSubscription<Object?>> _subs = [];
  Presence _wanted = Presence.online;

  /// Call once after Firebase is initialized.
  void start() {
    if (_started) return;
    _started = true;
    AuthService.instance.userChanges.listen((_) => _sync());
    ConnectivityService.instance.online.addListener(_sync);
    _sync();
  }

  /// Starts or stops presence and invites as the player signs in/out or
  /// goes on/offline.
  void _sync() {
    final user = AuthService.instance.currentUser;
    final online = ConnectivityService.instance.isOnline;
    final uid = (user != null && online) ? user.uid : null;
    if (uid == _listeningFor) return;
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    incoming.value = null;
    _listeningFor = uid;
    if (uid == null || user == null) return;

    _subs.add(
      _rtdb.ref('.info/serverTimeOffset').onValue.listen((e) {
        _serverOffsetMs = (e.snapshot.value as num?)?.toInt() ?? 0;
      }),
    );

    // Presence: mark online whenever connected, and let the server mark
    // this player offline if the connection drops.
    final statusRef = _rtdb.ref('status/$uid');
    _subs.add(
      _rtdb.ref('.info/connected').onValue.listen((e) async {
        if (e.snapshot.value != true) return;
        try {
          await statusRef.onDisconnect().set({
            'state': Presence.offline.name,
            'changedAt': ServerValue.timestamp,
          });
          await _writePresence(user, _wanted);
        } catch (err) {
          debugPrint('Presence failed: $err');
        }
      }, onError: (Object e) => debugPrint('Presence listener failed: $e')),
    );

    _subs.add(
      _rtdb.ref('invites/$uid').onValue.listen((e) {
        incoming.value = _newestInvite(e.snapshot);
      }, onError: (Object e) => debugPrint('Invites listener failed: $e')),
    );
  }

  ChallengeInvite? _newestInvite(DataSnapshot snap) {
    final data = snap.value;
    if (data is! Map) return null;
    ChallengeInvite? newest;
    for (final entry in data.entries) {
      final m = entry.value;
      if (m is! Map) continue;
      final sentAt = DateTime.fromMillisecondsSinceEpoch(
        (m['sentAt'] as num?)?.toInt() ?? 0,
      );
      if (serverNow.difference(sentAt) > answerWindow) continue; // expired
      final invite = ChallengeInvite(
        from: entry.key as String,
        name: (m['fromName'] as String?) ?? 'Cat stacker',
        photoUrl: m['fromPhoto'] as String?,
        matchId: m['matchId'] as String,
        sentAt: sentAt,
      );
      if (newest == null || invite.sentAt.isAfter(newest.sentAt)) {
        newest = invite;
      }
    }
    return newest;
  }

  Future<void> _writePresence(User user, Presence p) =>
      _rtdb.ref('status/${user.uid}').set({
        'state': p.name,
        // Any signed-in player can read this: first name and initial only.
        'name': publicName(user.displayName),
        'changedAt': ServerValue.timestamp,
      });

  /// Whether this player is in a game right now.
  bool get isPlaying => _wanted == Presence.playing;

  /// "Playing" while in a game, so friends don't challenge mid-run.
  void setPlaying(bool playing) {
    _wanted = playing ? Presence.playing : Presence.online;
    final user = AuthService.instance.currentUser;
    if (user == null || _listeningFor == null) return;
    _writePresence(
      user,
      _wanted,
    ).catchError((Object e) => debugPrint('Presence update failed: $e'));
  }

  /// Live presence of one player.
  Stream<Presence> presenceOf(String uid) =>
      _rtdb.ref('status/$uid/state').onValue.map((e) {
        final v = e.snapshot.value;
        return Presence.values.firstWhere(
          (p) => p.name == v,
          orElse: () => Presence.offline,
        );
      });

  String _displayName(User user) {
    final name = user.displayName?.trim() ?? '';
    if (name.isEmpty) return 'Cat stacker';
    return name.length > 40 ? name.substring(0, 40) : name;
  }

  // ---------- Starting a match ----------

  /// Challenges [friendUid]. Returns the new match's id.
  Future<String> sendChallenge({
    required String friendUid,
    required String friendName,
    String? friendPhoto,
  }) async {
    final user = AuthService.instance.currentUser;
    if (user == null) throw StateError('Not signed in');
    final ref = _rtdb.ref('matches').push();
    final id = ref.key!;
    await ref.set({
      'seed': Random().nextInt(1 << 31),
      'state': MatchState.invited.name,
      'createdAt': ServerValue.timestamp,
      // Challenges between friends are always Friendly.
      'mode': 'friendly',
      'stake': 0,
      'players': {
        user.uid: _newPlayer(_displayName(user), user.photoURL, joined: true),
        friendUid: _newPlayer(friendName, friendPhoto, joined: false),
      },
    });
    await _rtdb.ref('invites/$friendUid/${user.uid}').set({
      'matchId': id,
      'fromName': _displayName(user),
      'fromPhoto': user.photoURL,
      'sentAt': ServerValue.timestamp,
    });
    return id;
  }

  Map<String, Object?> _newPlayer(
    String name,
    String? photo, {
    required bool joined,
  }) => {
    'name': name,
    'photo': photo,
    'score': 0,
    'alive': true,
    'joined': joined,
    'connected': true,
    'left': false,
  };

  /// Accepts: both phones start counting down to the same moment.
  Future<void> accept(ChallengeInvite invite) async {
    final me = _uid;
    if (me == null) return;
    await _rtdb.ref('invites/$me/${invite.from}').remove();
    final startAt = serverNow.add(countdown).millisecondsSinceEpoch;
    await _rtdb.ref('matches/${invite.matchId}').update({
      'players/$me/joined': true,
      'state': MatchState.countdown.name,
      'startAt': startAt,
    });
  }

  Future<void> decline(ChallengeInvite invite) async {
    final me = _uid;
    if (me == null) return;
    await _rtdb.ref('invites/$me/${invite.from}').remove();
    await _rtdb
        .ref('matches/${invite.matchId}/state')
        .set(MatchState.declined.name);
  }

  /// The challenger gives up waiting.
  Future<void> cancel(String matchId, String friendUid) async {
    final me = _uid;
    if (me == null) return;
    await _rtdb.ref('invites/$friendUid/$me').remove();
    await _rtdb.ref('matches/$matchId/state').set(MatchState.cancelled.name);
  }

  // ---------- During a match ----------

  /// Live updates of a match. Also marks this player disconnected if their
  /// connection drops, so the opponent can claim the win after a while.
  Stream<Match> watch(String matchId) {
    final me = _uid!;
    final mine = _rtdb.ref('matches/$matchId/players/$me');
    // The server counts a long disconnection as leaving.
    mine.onDisconnect().update({
      'connected': false,
      'disconnectedAt': ServerValue.timestamp,
    });
    mine.update({'connected': true, 'joined': true});
    return _rtdb
        .ref('matches/$matchId')
        .onValue
        .map((e) => Match.fromSnapshot(matchId, me, e.snapshot))
        .where((m) => m != null)
        .cast<Match>();
  }

  Future<void> reportScore(String matchId, int score) =>
      _player(matchId).child('score').set(score);

  Future<void> reportFell(String matchId, int score) =>
      _player(matchId).update({'score': score, 'alive': false});

  /// Leaving mid-match forfeits it.
  Future<void> leave(String matchId) =>
      _player(matchId).update({'left': true, 'alive': false});

  /// Marks the match done (either player may).
  Future<void> finish(String matchId) =>
      _rtdb.ref('matches/$matchId/state').set(MatchState.finished.name);

  /// Calls the match off before it starts (the opponent never turned up).
  Future<void> callOff(String matchId) =>
      _rtdb.ref('matches/$matchId/state').set(MatchState.cancelled.name);

  /// Wagers: the server takes this player's stake. Shown straight away.
  /// Returns false if it couldn't (e.g. not enough treats).
  Future<bool> joinMatch(String matchId, int stake) async {
    final result = await PlayerService.instance.run(
      'joinMatch',
      {'matchId': matchId},
      opId: 'stake:$matchId',
      change: WalletChange(treats: -stake),
    );
    return result != null;
  }

  DatabaseReference _player(String matchId) =>
      _rtdb.ref('matches/$matchId/players/$_uid');

  /// Asks the server to decide the match and pay the prizes (it does so
  /// once, from both players' live state). Null while it's still being
  /// played, or if the server can't be reached.
  Future<({String outcome, int prize})?> settle(String matchId) async {
    try {
      final r = await ServerApi.instance.call('settleMatch', {
        'matchId': matchId,
      });
      if (r['decided'] != true) return null;
      return (
        outcome: (r['outcome'] as String?) ?? 'cancelled',
        prize: (r['prize'] as num?)?.toInt() ?? 0,
      );
    } on ServerError catch (e) {
      debugPrint('Settling match failed: ${e.reason}');
      return null;
    }
  }

  /// Turns the two players' live state into a result, counting a long
  /// disconnection as a forfeit.
  static MatchOutcome outcome(
    Match m, {
    required bool themGoneTooLong,
    required bool meGoneTooLong,
  }) => outcomeFor(
    Racer(
      score: m.me.score,
      alive: m.me.alive,
      forfeited: m.me.left || meGoneTooLong,
    ),
    Racer(
      score: m.them.score,
      alive: m.them.alive,
      forfeited: m.them.left || themGoneTooLong,
    ),
  );
}

/// An opponent found by [MatchFinder].
class FoundMatch {
  const FoundMatch({
    required this.matchId,
    required this.opponentUid,
    required this.opponentName,
  });

  final String matchId;
  final String opponentUid;
  final String opponentName;
}

/// Finds a random opponent looking for the same [stakes].
///
/// Players wait in `queue/{stakes}`. A searcher claims the longest-waiting
/// player there (a transaction, so only one searcher can claim them),
/// having first created the match. With nobody to claim, the searcher joins
/// the queue and waits to be claimed, still claiming anyone who has been
/// waiting longer. Before claiming someone, a waiting player takes itself
/// out of the queue (also a transaction), so nobody ends up in two
/// matches.
class MatchFinder {
  MatchFinder(this.stakes);

  final MatchStakes stakes;

  /// Queue entries older than this are ignored (a phone that went away
  /// without the server noticing yet).
  static const _stale = Duration(minutes: 2);

  final _service = ChallengeService.instance;
  FirebaseDatabase get _rtdb => _service._rtdb;

  late final User _user = AuthService.instance.currentUser!;
  String get _me => _user.uid;

  DatabaseReference get _queue => _rtdb.ref('queue/${stakes.queueKey}');
  DatabaseReference get _mine => _queue.child(_me);

  final _done = Completer<FoundMatch?>();
  StreamSubscription<DatabaseEvent>? _sub;
  Timer? _retry;
  DataSnapshot? _latest;
  bool _inQueue = false;
  bool _busy = false;

  /// Completes with the match, or null if [cancel] was called.
  Future<FoundMatch?> start() {
    // Listening keeps the queue cached, which the transactions rely on.
    _sub = _queue.onValue.listen(
      (e) {
        _latest = e.snapshot;
        if (!_checkClaimed()) _step();
      },
      onError: (Object e) {
        if (!_done.isCompleted) _done.completeError(e);
        _stop();
      },
    );
    _retry = Timer.periodic(const Duration(seconds: 2), (_) => _step());
    return _done.future;
  }

  /// Stops looking (and leaves the queue).
  Future<void> cancel() async {
    if (_done.isCompleted) return;
    _done.complete(null);
    _stop();
    if (_inQueue) await _withdraw();
  }

  void _stop() {
    _retry?.cancel();
    _sub?.cancel();
  }

  /// Someone claimed this player: off to that match.
  bool _checkClaimed() {
    final mine = _latest?.child(_me).value;
    if (_done.isCompleted || mine is! Map) return false;
    final matchId = mine['matchId'];
    final by = mine['by'];
    if (matchId is! String || by is! String) return false;
    _finish(
      FoundMatch(
        matchId: matchId,
        opponentUid: by,
        opponentName: (mine['byName'] as String?) ?? 'Cat stacker',
      ),
    );
    return true;
  }

  void _finish(FoundMatch found) {
    if (_done.isCompleted) return;
    _done.complete(found);
    _stop();
    _inQueue = false;
    _mine.onDisconnect().cancel().catchError(_log);
    _mine.remove().catchError(_log);
  }

  void _log(Object e) => debugPrint('Matchmaking: $e');

  Future<void> _step() async {
    if (_busy || _done.isCompleted || _latest == null) return;
    _busy = true;
    try {
      for (final other in _candidates()) {
        if (_done.isCompleted) return;
        // Out of the queue first; if that fails, someone just claimed us.
        if (_inQueue && !await _withdraw()) return;
        final matchId = await _createMatch(other);
        if (await _claim(other.key!, matchId)) {
          _finish(
            FoundMatch(
              matchId: matchId,
              opponentUid: other.key!,
              opponentName:
                  (other.child('name').value as String?) ?? 'Cat stacker',
            ),
          );
          return;
        }
        await _service.callOff(matchId).catchError(_log);
      }
      if (!_inQueue && !_done.isCompleted) await _join();
    } catch (e) {
      _log(e);
    } finally {
      _busy = false;
    }
  }

  /// Players to claim, longest-waiting first. While waiting, only those
  /// who joined earlier (so two waiting players never claim each other).
  List<DataSnapshot> _candidates() {
    final now = _service.serverNow.millisecondsSinceEpoch;
    int? atOf(DataSnapshot s) => (s.child('at').value as num?)?.toInt();
    final myAt = _inQueue ? atOf(_latest!.child(_me)) : null;
    final list = <DataSnapshot>[];
    for (final s in _latest!.children) {
      final at = atOf(s);
      if (s.key == _me || at == null || s.child('matchId').exists) continue;
      if (now - at > _stale.inMilliseconds) continue;
      if (myAt != null &&
          (at > myAt || (at == myAt && s.key!.compareTo(_me) > 0))) {
        continue;
      }
      list.add(s);
    }
    list.sort((a, b) => atOf(a)!.compareTo(atOf(b)!));
    return list;
  }

  Future<void> _join() async {
    await _mine.onDisconnect().remove();
    await _mine.set({
      // Random opponents aren't friends: first name and initial only.
      'name': publicName(_user.displayName),
      'photo': _user.photoURL,
      'at': ServerValue.timestamp,
    });
    _inQueue = true;
  }

  /// Leaves the queue unless someone has claimed this player. Returns
  /// whether it left.
  Future<bool> _withdraw() async {
    final result = await _mine.runTransaction((value) {
      if (value is Map && value['matchId'] != null) {
        return Transaction.abort();
      }
      return Transaction.success(null);
    });
    if (result.committed) {
      _inQueue = false;
      await _mine.onDisconnect().cancel().catchError(_log);
    }
    return result.committed;
  }

  /// Claims a waiting player for [matchId], unless someone else got there
  /// first (or they left).
  Future<bool> _claim(String uid, String matchId) async {
    final result = await _queue.child(uid).runTransaction((value) {
      if (value is! Map || value['matchId'] != null) {
        return Transaction.abort();
      }
      return Transaction.success({
        ...value,
        'matchId': matchId,
        'by': _me,
        'byName': publicName(_user.displayName),
      });
    });
    return result.committed;
  }

  /// The match, ready to go: both players have [ChallengeService.joinWindow]
  /// to open it, then the countdown runs.
  Future<String> _createMatch(DataSnapshot other) async {
    final ref = _rtdb.ref('matches').push();
    final startAt = _service.serverNow
        .add(ChallengeService.countdown + const Duration(seconds: 3))
        .millisecondsSinceEpoch;
    await ref.set({
      'seed': Random().nextInt(1 << 31),
      'state': MatchState.countdown.name,
      'startAt': startAt,
      'createdAt': ServerValue.timestamp,
      'mode': stakes.isWager ? 'wager' : 'friendly',
      'stake': stakes.wager,
      'players': {
        _me: _service._newPlayer(
          publicName(_user.displayName),
          _user.photoURL,
          joined: false,
        ),
        other.key!: _service._newPlayer(
          (other.child('name').value as String?) ?? 'Cat stacker',
          other.child('photo').value as String?,
          joined: false,
        ),
      },
    });
    return ref.key!;
  }
}
