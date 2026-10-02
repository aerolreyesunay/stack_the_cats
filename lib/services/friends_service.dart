import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import '../auth/auth_service.dart';
import '../economy/invites.dart';
import '../economy/treats.dart';
import 'player_service.dart';

/// A friend as shown in the friends list.
class Friend {
  const Friend({
    required this.uid,
    required this.name,
    required this.photoUrl,
    required this.best,
  });

  final String uid;
  final String name;
  final String? photoUrl;

  /// All-time best score, or 0 if they haven't played yet.
  final int best;
}

/// A request from another player to become friends.
class FriendRequest {
  const FriendRequest({
    required this.from,
    required this.name,
    required this.photoUrl,
  });

  final String from;
  final String name;
  final String? photoUrl;
}

/// What happened when the player entered a friend's code.
enum RedeemResult {
  /// Now friends, and the friend earned the invite bonus for a new player.
  friendJoined,

  /// Now friends (this player isn't new, or already used a code before).
  friendAdded,
  alreadyFriends,
  ownCode,
  notFound,
  invalid,
}

/// What happened when the player tapped "add friend" on someone.
enum RequestResult { sent, accepted, alreadyFriends, alreadySent }

/// Invite codes, friend requests, invite rewards and the friends list.
///
/// Firestore layout:
///   profiles/{uid}              public name, photo and invite code
///   inviteCodes/{code}          which player a code belongs to
///   friendRequests/{from_to}    a pending request, until accepted/declined
///   friendships/{uidA_uidB}     one per pair of friends (uids sorted).
///                               Accepted requests are marked friendBonus,
///                               and each friend claims their bonus once
///                               by adding their uid to rewardsClaimed.
///   referrals/{joinerUid}       a new player who joined with someone's
///                               code; the inviter claims the bonus once
class FriendsService {
  FriendsService._();
  static final FriendsService instance = FriendsService._();

  /// Friends who joined with this player's code since last time; the menu
  /// shows a message and resets it to 0.
  final ValueNotifier<int> friendsJoinedBonus = ValueNotifier(0);

  /// Names of players who just accepted this player's request (bonus paid);
  /// the menu shows a message and empties it.
  final ValueNotifier<List<String>> requestsAccepted = ValueNotifier(const []);

  /// Live: uids of this player's friends.
  final ValueNotifier<Set<String>> friendIds = ValueNotifier(const {});

  /// Live: requests other players sent to this player.
  final ValueNotifier<List<FriendRequest>> incoming = ValueNotifier(const []);

  /// Live: uids this player has sent requests to.
  final ValueNotifier<Set<String>> outgoing = ValueNotifier(const {});

  bool _started = false;

  /// The player whose profile and listeners were set up this launch.
  String? _setUpFor;
  final List<StreamSubscription<Object?>> _subs = [];

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  String? get _uid => AuthService.instance.currentUser?.uid;

  /// Call once after Firebase is initialized. Waits for the player's wallet
  /// to load (it must exist before the invite code is saved into it).
  void start() {
    if (_started) return;
    _started = true;
    PlayerService.instance.player.addListener(_onPlayer);
    AuthService.instance.userChanges.listen((user) {
      if (user == null) _reset();
    });
  }

  void _reset() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    _setUpFor = null;
    friendIds.value = const {};
    incoming.value = const [];
    outgoing.value = const {};
  }

  Future<void> _onPlayer() async {
    final user = AuthService.instance.currentUser;
    final data = PlayerService.instance.player.value;
    if (user == null || data == null || _setUpFor == user.uid) return;
    _reset();
    _setUpFor = user.uid;
    try {
      await _ensureProfile(user, data.inviteCode);
      _listen(user.uid);
      await claimReferralRewards();
    } catch (e) {
      debugPrint('Friends setup failed: $e');
      _setUpFor = null; // try again next time
    }
  }

  void _listen(String me) {
    void onError(Object e) => debugPrint('Friends listener failed: $e');

    _subs.add(
      _db
          .collection('friendships')
          .where('members', arrayContains: me)
          .snapshots()
          .listen((snap) {
            friendIds.value = {
              for (final doc in snap.docs) _otherMember(doc.data(), me),
            };
            _claimFriendBonuses(me, snap.docs);
          }, onError: onError),
    );
    _subs.add(
      _db
          .collection('friendRequests')
          .where('to', isEqualTo: me)
          .snapshots()
          .listen((snap) {
            incoming.value = [
              for (final doc in snap.docs)
                FriendRequest(
                  from: doc.data()['from'] as String,
                  name: (doc.data()['fromName'] as String?) ?? 'Cat stacker',
                  photoUrl: doc.data()['fromPhoto'] as String?,
                ),
            ];
          }, onError: onError),
    );
    _subs.add(
      _db
          .collection('friendRequests')
          .where('from', isEqualTo: me)
          .snapshots()
          .listen((snap) {
            outgoing.value = {
              for (final doc in snap.docs) doc.data()['to'] as String,
            };
          }, onError: onError),
    );
  }

  static String _otherMember(Map<String, dynamic> friendship, String me) =>
      (friendship['members'] as List).cast<String>().firstWhere(
        (u) => u != me,
        orElse: () => me,
      );

  static String _pairId(String a, String b) =>
      a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';

  String _displayName(User user) {
    final name = user.displayName?.trim() ?? '';
    if (name.isEmpty) return 'Cat stacker';
    return name.length > 40 ? name.substring(0, 40) : name;
  }

  /// Makes sure the player has a public profile and an invite code.
  Future<void> _ensureProfile(User user, String? existingCode) async {
    final code = existingCode ?? await _claimNewCode(user.uid);
    await _db.collection('profiles').doc(user.uid).set({
      'name': _displayName(user),
      'photoUrl': user.photoURL,
      'inviteCode': code,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Picks a random code nobody has yet and reserves it.
  Future<String> _claimNewCode(String uid) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      final code = Invites.randomCode();
      final codeRef = _db.collection('inviteCodes').doc(code);
      final claimed = await _db.runTransaction<bool>((tx) async {
        if ((await tx.get(codeRef)).exists) return false;
        tx.set(codeRef, {'uid': uid});
        tx.update(_db.collection('users').doc(uid), {'inviteCode': code});
        return true;
      });
      if (claimed) return code;
    }
    throw StateError('Could not find a free invite code');
  }

  // ---------- Invites ----------

  /// Opens the phone's share sheet with the invite. Returns the treats
  /// earned (0 if cancelled or the daily limit is reached).
  Future<int> shareInvite(String code) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        text: Invites.shareMessage(code),
        subject: 'Play Stack the Cats with me!',
      ),
    );
    if (result.status != ShareResultStatus.success) return 0;
    final paid = await PlayerService.instance.rewardShare();
    return paid ? Treats.shareReward : 0;
  }

  /// Adds the owner of [input] as a friend straight away (sharing a code is
  /// the invitation). If this player is new and hasn't used a code before,
  /// the code's owner also earns the invite bonus.
  Future<RedeemResult> redeemCode(String input) async {
    final me = _uid;
    final code = Invites.normalize(input);
    if (me == null || code == null) return RedeemResult.invalid;

    final owner =
        (await _db.collection('inviteCodes').doc(code).get()).data()?['uid']
            as String?;
    if (owner == null) return RedeemResult.notFound;
    if (owner == me) return RedeemResult.ownCode;
    if (friendIds.value.contains(owner)) return RedeemResult.alreadyFriends;

    final player = PlayerService.instance.player.value;
    final created = player?.createdAt;
    final isNew =
        created != null &&
        DateTime.now().difference(created) < Invites.newPlayerWindow;
    final rewardsInviter = isNew && player?.invitedBy == null;

    final batch = _db.batch();
    batch.set(_db.collection('friendships').doc(_pairId(me, owner)), {
      'members': [me, owner]..sort(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (rewardsInviter) {
      batch.set(_db.collection('referrals').doc(me), {
        'referrer': owner,
        'code': code,
        'claimed': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.update(_db.collection('users').doc(me), {'invitedBy': owner});
    }
    await batch.commit();
    return rewardsInviter
        ? RedeemResult.friendJoined
        : RedeemResult.friendAdded;
  }

  /// Pays this player (on the server) for each new friend who joined with
  /// their code since last time. Returns how many.
  Future<int> claimReferralRewards() async {
    final me = _uid;
    if (me == null) return 0;
    final pending = await _db
        .collection('referrals')
        .where('referrer', isEqualTo: me)
        .where('claimed', isEqualTo: false)
        .get();
    if (pending.docs.isEmpty) return 0;
    final result = await PlayerService.instance.run(
      'claimReferrals',
      const {},
      quiet: true,
    );
    final count = (result?['count'] as num?)?.toInt() ?? 0;
    if (count > 0) friendsJoinedBonus.value = count;
    return count;
  }

  // ---------- Friend requests ----------

  /// Asks another player to be friends (e.g. from the leaderboard). If they
  /// already asked this player, it accepts their request instead.
  Future<RequestResult> sendRequest(String to) async {
    final me = AuthService.instance.currentUser;
    if (me == null || to == me.uid) return RequestResult.alreadyFriends;
    if (friendIds.value.contains(to)) return RequestResult.alreadyFriends;
    if (outgoing.value.contains(to)) return RequestResult.alreadySent;
    if (incoming.value.any((r) => r.from == to)) {
      await acceptRequest(to);
      return RequestResult.accepted;
    }
    await _db.collection('friendRequests').doc('${me.uid}_$to').set({
      'from': me.uid,
      'to': to,
      'fromName': _displayName(me),
      'fromPhoto': me.photoURL,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return RequestResult.sent;
  }

  /// Accepts a request: both become friends, and the server pays both
  /// bonuses (each player's app asks for theirs when it sees the new
  /// friendship).
  Future<void> acceptRequest(String from) async {
    final me = _uid;
    if (me == null) return;
    // Their request was accepted here: no "accepted your request" message.
    _acceptedHere.add(from);
    final batch = _db.batch();
    batch.set(_db.collection('friendships').doc(_pairId(me, from)), {
      'members': [me, from]..sort(),
      'friendBonus': true,
      'rewardsClaimed': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.delete(_db.collection('friendRequests').doc('${from}_$me'));
    await batch.commit();
  }

  /// Players whose requests this player accepted on this phone.
  final Set<String> _acceptedHere = {};

  Future<void> declineRequest(String from) async {
    final me = _uid;
    if (me == null) return;
    await _db.collection('friendRequests').doc('${from}_$me').delete();
  }

  /// Claims (from the server) this player's bonus for accepted requests
  /// they haven't been paid for yet, whichever side accepted.
  Future<void> _claimFriendBonuses(
    String me,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> friendships,
  ) async {
    final unpaid = [
      for (final doc in friendships)
        if (doc.data()['friendBonus'] == true &&
            !((doc.data()['rewardsClaimed'] as List?) ?? const []).contains(me))
          doc,
    ];
    // One claim at a time, so a quick second update can't pay twice.
    if (unpaid.isEmpty || _claimingBonus) return;
    _claimingBonus = true;
    try {
      final result = await PlayerService.instance.run(
        'claimFriendBonuses',
        const {},
        quiet: true,
      );
      final paid = ((result?['friends'] as List?) ?? const [])
          .whereType<String>()
          .where((uid) => !_acceptedHere.contains(uid))
          .toList();
      if (paid.isEmpty) return;
      final names = await Future.wait(paid.map(_loadFriend));
      requestsAccepted.value = [for (final f in names) f.name];
    } catch (e) {
      debugPrint('Claiming friend bonus failed: $e');
    } finally {
      _claimingBonus = false;
    }
  }

  bool _claimingBonus = false;

  // ---------- Friends list ----------

  /// This player's friends, best players first.
  Future<List<Friend>> friends() async {
    final result = await Future.wait(friendIds.value.map(_loadFriend));
    return result..sort((a, b) => b.best.compareTo(a.best));
  }

  Future<Friend> _loadFriend(String uid) async {
    final docs = await Future.wait([
      _db.collection('profiles').doc(uid).get(),
      _db.collection('scores').doc(uid).get(),
    ]);
    final profile = docs[0].data() ?? const {};
    return Friend(
      uid: uid,
      name: (profile['name'] as String?) ?? 'Cat stacker',
      photoUrl: profile['photoUrl'] as String?,
      best: (docs[1].data()?['best'] as num?)?.toInt() ?? 0,
    );
  }
}
