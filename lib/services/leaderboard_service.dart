import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_service.dart';

/// Which leaderboard to show.
enum Board { weekly, allTime }

/// Leaderboard weeks run Monday 00:00 to Monday 00:00 UTC, the same
/// moment for every player (8:00 AM Monday in the Philippines).
class LeaderboardWeek {
  LeaderboardWeek._();

  /// The ISO-8601 week, e.g. '2026-W40'.
  static String key(DateTime now) {
    final utc = now.toUtc();
    final day = DateTime.utc(utc.year, utc.month, utc.day);
    // An ISO week belongs to the year its Thursday falls in.
    final thursday = day.add(Duration(days: DateTime.thursday - day.weekday));
    final week =
        thursday.difference(DateTime.utc(thursday.year, 1, 1)).inDays ~/ 7 + 1;
    return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
  }

  /// When the current week's leaderboard closes.
  static DateTime endsAt(DateTime now) {
    final utc = now.toUtc();
    final day = DateTime.utc(utc.year, utc.month, utc.day);
    return day.add(Duration(days: 8 - day.weekday));
  }
}

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.uid,
    required this.name,
    required this.photoUrl,
    required this.score,
  });

  final String uid;

  /// "First L." (kids: their made-up name). Swapped for the full name for
  /// friends and the player themself, see [LeaderboardService.withFullNames].
  final String name;
  final String? photoUrl;
  final int score;

  LeaderboardEntry withName(String name) =>
      LeaderboardEntry(uid: uid, name: name, photoUrl: photoUrl, score: score);

  factory LeaderboardEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? const {};
    return LeaderboardEntry(
      uid: d.id,
      name: (data['name'] as String?) ?? 'Cat stacker',
      photoUrl: data['photoUrl'] as String?,
      score: (data['best'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The signed-in player's place on a board.
class MyStanding {
  const MyStanding({required this.rank, required this.score});
  final int rank;
  final int score;
}

/// Reads the leaderboards. (Best scores are written by the server, from
/// the cats it counted in each game.)
///
/// Firestore layout:
///   scores/{uid}                 all-time best
///   weekly/{week}/scores/{uid}   best this week
class LeaderboardService {
  LeaderboardService._();
  static final LeaderboardService instance = LeaderboardService._();

  static const topCount = 100;

  StreamSubscription<User?>? _authSub;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _collection(
    Board board, [
    DateTime? now,
  ]) => switch (board) {
    Board.allTime => _db.collection('scores'),
    Board.weekly =>
      _db
          .collection('weekly')
          .doc(LeaderboardWeek.key(now ?? DateTime.now()))
          .collection('scores'),
  };

  /// Call once after Firebase is initialized.
  void start() {
    _authSub ??= AuthService.instance.userChanges.listen(_onUser);
  }

  /// A better best from another phone becomes this phone's best.
  Future<void> _onUser(User? user) async {
    if (user == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final localBest = prefs.getInt('best') ?? 0;
      final doc = await _collection(Board.allTime).doc(user.uid).get();
      final cloudBest = (doc.data()?['best'] as num?)?.toInt() ?? 0;
      if (cloudBest > localBest) await prefs.setInt('best', cloudBest);
    } catch (e) {
      debugPrint('Reading cloud best failed: $e');
    }
  }

  /// The top players on a board, best first.
  Future<List<LeaderboardEntry>> top(Board board) async {
    final snap = await _collection(board)
        .orderBy('best', descending: true)
        .limit(topCount)
        .get();
    return snap.docs.map(LeaderboardEntry.fromDoc).toList();
  }

  /// The board shows everyone as "First L."; friends (and the player
  /// themself) see each other's full names, from their profiles, which
  /// only friends can read. A name that can't be read stays short.
  Future<List<LeaderboardEntry>> withFullNames(
    List<LeaderboardEntry> entries,
    Set<String> friendIds,
  ) async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return entries;
    Future<LeaderboardEntry> full(LeaderboardEntry e) async {
      if (e.uid != me && !friendIds.contains(e.uid)) return e;
      try {
        final doc = await _db.collection('profiles').doc(e.uid).get();
        final name = (doc.data()?['name'] as String?)?.trim() ?? '';
        return name.isEmpty ? e : e.withName(name);
      } catch (err) {
        debugPrint('Reading a friend\'s name failed: $err');
        return e;
      }
    }

    return Future.wait(entries.map(full));
  }

  /// The signed-in player's rank, or null if they're signed out or have no
  /// score on this board yet.
  Future<MyStanding?> myStanding(Board board) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final col = _collection(board);
    final doc = await col.doc(user.uid).get();
    final best = (doc.data()?['best'] as num?)?.toInt();
    if (best == null) return null;
    final ahead = await col.where('best', isGreaterThan: best).count().get();
    return MyStanding(rank: (ahead.count ?? 0) + 1, score: best);
  }
}
