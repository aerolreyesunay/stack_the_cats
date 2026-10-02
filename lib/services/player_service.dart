import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../auth/auth_service.dart';
import '../economy/invites.dart';
import '../store/catalog.dart';
import '../store/wallpapers.dart';
import '../economy/treats.dart';
import 'connectivity_service.dart';
import 'server_api.dart';

/// The signed-in player's saved data.
class PlayerData {
  const PlayerData({
    required this.uid,
    required this.treats,
    this.tuna = 0,
    this.salmon = 0,
    required this.dailyLastClaim,
    required this.dailyDay,
    this.inviteCode,
    this.invitedBy,
    this.shareDay,
    this.shareCount = 0,
    this.adDay,
    this.adCount = 0,
    this.createdAt,
    this.ownedCats = const {},
    this.ownedWallpapers = const {},
    this.wallpaperId,
    this.wallpaperRandom = false,
    this.recentOps = const {},
    this.landingsTotal = 0,
    this.earnDay,
    this.earnedTreats = 0,
    this.earnedTuna = 0,
    this.earnedSalmon = 0,
  });

  /// What normal games paid on [earnDay] (UTC), for the daily limit.
  final String? earnDay;
  final int earnedTreats;
  final int earnedTuna;
  final int earnedSalmon;

  /// Cats stacked in all games, as counted by the server.
  final int landingsTotal;

  /// Treat wagers unlock after this many cats (so throwaway accounts can't
  /// pass their welcome treats on). The server checks the same number.
  static const wagerMinLandings = 200;

  bool get canWager => landingsTotal >= wagerMinLandings;

  /// Picks a random owned wallpaper for every game instead of [wallpaper].
  final bool wallpaperRandom;

  /// Wallpapers this player can use (the free one plus any bought).
  List<Wallpaper> get wallpaperPool => [
    for (final w in Wallpapers.all)
      if (ownsWallpaper(w)) w,
  ];

  /// Store cats this player bought (basic cats aren't listed: everyone has
  /// them).
  final Set<String> ownedCats;

  /// Store wallpapers this player bought.
  final Set<String> ownedWallpapers;

  /// The wallpaper in use (null = the free one).
  final String? wallpaperId;

  /// The cats that can drop in this player's games.
  List<CatBreed> get catPool => Cats.ownedBy(ownedCats);

  Wallpaper get wallpaper => Wallpapers.byId(wallpaperId);

  bool ownsCat(CatBreed cat) => cat.isBasic || ownedCats.contains(cat.id);
  bool ownsWallpaper(Wallpaper w) => w.isFree || ownedWallpapers.contains(w.id);

  final String uid;
  final int treats;
  final int tuna;
  final int salmon;

  int fishCount(Fish fish) => fish == Fish.tuna ? tuna : salmon;

  final String? dailyLastClaim;
  final int dailyDay;

  /// This player's code for inviting friends.
  final String? inviteCode;

  /// Who invited this player, once they've entered someone's code.
  final String? invitedBy;

  /// The day ('yyyy-mm-dd') of the last paid share, and how many that day.
  final String? shareDay;
  final int shareCount;

  /// The day of the last Store video for treats, and how many that day.
  final String? adDay;
  final int adCount;

  final DateTime? createdAt;

  /// Wallet operations the server has finished (the newest few).
  final Set<String> recentOps;

  factory PlayerData.fromDoc(String uid, Map<String, dynamic> d) => PlayerData(
    uid: uid,
    treats: (d['treats'] as num?)?.toInt() ?? 0,
    tuna: (d['tuna'] as num?)?.toInt() ?? 0,
    salmon: (d['salmon'] as num?)?.toInt() ?? 0,
    dailyLastClaim: d['dailyLastClaim'] as String?,
    dailyDay: (d['dailyDay'] as num?)?.toInt() ?? 0,
    inviteCode: d['inviteCode'] as String?,
    invitedBy: d['invitedBy'] as String?,
    shareDay: d['shareDay'] as String?,
    shareCount: (d['shareCount'] as num?)?.toInt() ?? 0,
    adDay: d['adDay'] as String?,
    adCount: (d['adCount'] as num?)?.toInt() ?? 0,
    createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    ownedCats: {...((d['ownedCats'] as List?) ?? const []).cast<String>()},
    ownedWallpapers: {
      ...((d['ownedWallpapers'] as List?) ?? const []).cast<String>(),
    },
    wallpaperId: d['wallpaper'] as String?,
    wallpaperRandom: d['wallpaperRandom'] == true,
    recentOps: {...((d['recentOps'] as List?) ?? const []).cast<String>()},
    landingsTotal: (d['landingsTotal'] as num?)?.toInt() ?? 0,
    earnDay: d['earnDay'] as String?,
    earnedTreats: (d['earnedTreats'] as num?)?.toInt() ?? 0,
    earnedTuna: (d['earnedTuna'] as num?)?.toInt() ?? 0,
    earnedSalmon: (d['earnedSalmon'] as num?)?.toInt() ?? 0,
  );

  PlayerData copyWith({
    int? treats,
    int? tuna,
    int? salmon,
    String? dailyLastClaim,
    int? dailyDay,
    String? shareDay,
    int? shareCount,
    String? adDay,
    int? adCount,
    Set<String>? ownedCats,
    Set<String>? ownedWallpapers,
    String? wallpaperId,
    bool? wallpaperRandom,
  }) => PlayerData(
    uid: uid,
    treats: treats ?? this.treats,
    tuna: tuna ?? this.tuna,
    salmon: salmon ?? this.salmon,
    dailyLastClaim: dailyLastClaim ?? this.dailyLastClaim,
    dailyDay: dailyDay ?? this.dailyDay,
    inviteCode: inviteCode,
    invitedBy: invitedBy,
    shareDay: shareDay ?? this.shareDay,
    shareCount: shareCount ?? this.shareCount,
    adDay: adDay ?? this.adDay,
    adCount: adCount ?? this.adCount,
    createdAt: createdAt,
    ownedCats: ownedCats ?? this.ownedCats,
    ownedWallpapers: ownedWallpapers ?? this.ownedWallpapers,
    wallpaperId: wallpaperId ?? this.wallpaperId,
    wallpaperRandom: wallpaperRandom ?? this.wallpaperRandom,
    recentOps: recentOps,
    landingsTotal: landingsTotal,
    earnDay: earnDay,
    earnedTreats: earnedTreats,
    earnedTuna: earnedTuna,
    earnedSalmon: earnedSalmon,
  );

  ShareAllowance get shares => ShareAllowance.compute(
    day: shareDay,
    count: shareCount,
    today: DailyStatus.dateKey(DateTime.now()),
  );

  /// Store videos for treats left today.
  int get storeAdsLeft {
    final today = DailyStatus.dateKey(DateTime.now());
    final used = adDay == today ? adCount : 0;
    return Treats.maxStoreAdsPerDay - used;
  }

  DailyStatus get daily => DailyStatus.compute(
    lastClaim: dailyLastClaim,
    lastDay: dailyDay,
    now: DateTime.now(),
  );
}

/// A change shown on screen before the server has saved it.
class WalletChange {
  const WalletChange({
    this.treats = 0,
    this.tuna = 0,
    this.salmon = 0,
    this.cat,
    this.wallpaper,
    this.fromGame = false,
  });

  static const none = WalletChange();

  /// Earned in a normal game (counts towards the daily limit).
  final bool fromGame;

  final int treats;
  final int tuna;
  final int salmon;

  /// A cat or wallpaper being added (the wallpaper also goes up).
  final String? cat;
  final String? wallpaper;

  WalletChange operator +(WalletChange other) => WalletChange(
    treats: treats + other.treats,
    tuna: tuna + other.tuna,
    salmon: salmon + other.salmon,
    cat: other.cat ?? cat,
    wallpaper: other.wallpaper ?? wallpaper,
    fromGame: fromGame || other.fromGame,
  );

  PlayerData applyTo(PlayerData p) => p.copyWith(
    treats: p.treats + treats,
    tuna: p.tuna + tuna,
    salmon: p.salmon + salmon,
    ownedCats: cat == null ? null : {...p.ownedCats, cat!},
    ownedWallpapers: wallpaper == null
        ? null
        : {...p.ownedWallpapers, wallpaper!},
    wallpaperId: wallpaper,
  );
}

/// The signed-in player's wallet (users/{uid} in Firestore).
///
/// Treats, Tuna, Salmon and Store items are changed only by the server
/// ([ServerApi]). So the game still feels instant, each change shows on
/// screen straight away as a pending [WalletChange], until the saved data
/// lists its operation id (or the server refuses it, which undoes it).
///
/// [player] is null when signed out, and also while offline: offline mode
/// plays as a guest (no treats, no leaderboard). The sign-in itself is kept,
/// so the player is back the moment the connection returns.
class PlayerService {
  PlayerService._();
  static final PlayerService instance = PlayerService._();

  /// The current player as shown (saved data plus pending changes), updated
  /// live. Null while signed out or offline.
  final ValueNotifier<PlayerData?> player = ValueNotifier(null);

  /// Something the server refused or couldn't do, for a message on screen.
  final ValueNotifier<ServerError?> problem = ValueNotifier(null);

  int get treats => player.value?.treats ?? 0;
  bool get signedIn => player.value != null;

  /// The latest saved data from Firestore, kept even while offline hides it.
  PlayerData? _latest;

  /// Changes on screen that the server hasn't saved yet, by operation id.
  final Map<String, WalletChange> _pending = {};

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;

  final _connection = ConnectivityService.instance.online;

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection('users').doc(uid);

  ServerApi get _api => ServerApi.instance;

  /// Call once after Firebase is initialized.
  void start() {
    if (_authSub != null) return;
    _authSub = AuthService.instance.userChanges.listen(_onUser);
    _connection.addListener(_publish);
  }

  void _publish() {
    var shown = _latest;
    if (shown != null) {
      for (final change in _pending.values) {
        shown = change.applyTo(shown!);
      }
    }
    player.value = _connection.value ? shown : null;
  }

  void _setLatest(PlayerData? data) {
    _latest = data;
    // Saved now: no longer pending.
    if (data != null) {
      _pending.removeWhere((id, _) => data.recentOps.contains(id));
    }
    _publish();
  }

  Future<void> _onUser(User? user) async {
    await _docSub?.cancel();
    _docSub = null;
    _pending.clear();
    if (user == null) {
      _setLatest(null);
      return;
    }
    try {
      await _ensureProfile(user);
    } catch (e) {
      debugPrint('Profile setup failed: $e');
    }
    _docSub = _doc(user.uid).snapshots().listen((snap) {
      final data = snap.data();
      if (data != null) _setLatest(PlayerData.fromDoc(user.uid, data));
    }, onError: (Object e) => debugPrint('Player listen failed: $e'));
  }

  /// Creates the player's document on first sign-in and keeps their name
  /// and photo up to date for leaderboards and friends.
  Future<void> _ensureProfile(User user) async {
    final ref = _doc(user.uid);
    final profile = {
      'displayName': user.displayName ?? 'Cat stacker',
      'photoUrl': user.photoURL,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final isNew = await _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists) {
        tx.update(ref, profile);
        return false;
      }
      tx.set(ref, {
        ...profile,
        // A welcome gift for signing in the first time (the only treats the
        // app itself may give: the rules check the amount).
        'treats': Treats.welcomeBonus,
        'dailyDay': 0,
        'dailyLastClaim': null,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
    if (isNew) welcomeBonusGiven.value = true;
  }

  /// True right after a brand-new player's wallet is created with the
  /// welcome bonus; the menu celebrates it and resets this.
  final ValueNotifier<bool> welcomeBonusGiven = ValueNotifier(false);

  // ---------- Pending changes ----------

  /// Shows [change] straight away under [opId] (added to anything already
  /// pending under it).
  void showPending(String opId, WalletChange change) {
    _pending[opId] = (_pending[opId] ?? WalletChange.none) + change;
    _publish();
  }

  /// Undoes a pending change (the server refused it).
  void dropPending(String opId) {
    if (_pending.remove(opId) != null) _publish();
  }

  /// Runs [action] on the server, showing [change] meanwhile. Undoes it
  /// and reports the problem if the server refuses. Returns the result, or
  /// null on failure.
  Future<Map<String, dynamic>?> run(
    String action,
    Map<String, Object?> params, {
    WalletChange change = WalletChange.none,
    String? opId,
    bool quiet = false,
  }) async {
    final id = opId ?? ServerApi.newOpId();
    showPending(id, change);
    try {
      return await _api.call(action, {'opId': id, ...params});
    } on ServerError catch (e) {
      dropPending(id);
      if (!quiet) problem.value = e;
      return null;
    }
  }

  /// What normal games may still pay today: the daily limit, less what the
  /// server has paid today and what's on its way.
  ({int treats, int tuna, int salmon}) gameAllowance() {
    final saved = _latest;
    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    final sameDay = saved?.earnDay == today;
    var treats = Treats.dailyGameTreats - (sameDay ? saved!.earnedTreats : 0);
    var tuna = Treats.dailyGameTuna - (sameDay ? saved!.earnedTuna : 0);
    var salmon = Treats.dailyGameSalmon - (sameDay ? saved!.earnedSalmon : 0);
    for (final change in _pending.values.where((c) => c.fromGame)) {
      treats -= change.treats;
      tuna -= change.tuna;
      salmon -= change.salmon;
    }
    return (treats: treats, tuna: tuna, salmon: salmon);
  }

  /// Whether the player (as shown) can afford [change].
  bool canAfford(WalletChange change) {
    final p = player.value;
    if (p == null) return false;
    return p.treats + change.treats >= 0 &&
        p.tuna + change.tuna >= 0 &&
        p.salmon + change.salmon >= 0;
  }

  // ---------- Store ----------

  /// Buys a cat. Instant on screen; the server saves it. Returns false if
  /// already owned or not enough treats.
  bool buyCat(CatBreed cat) {
    final current = player.value;
    if (current == null || current.ownsCat(cat)) return false;
    final change = WalletChange(treats: -cat.price, cat: cat.id);
    if (!canAfford(change)) return false;
    run('buyCat', {'catId': cat.id}, change: change);
    return true;
  }

  /// Buys a wallpaper and puts it up straight away.
  bool buyWallpaper(Wallpaper wallpaper) {
    final current = player.value;
    if (current == null || current.ownsWallpaper(wallpaper)) return false;
    final change = WalletChange(
      treats: -wallpaper.price,
      wallpaper: wallpaper.id,
    );
    if (!canAfford(change)) return false;
    run('buyWallpaper', {'wallpaperId': wallpaper.id}, change: change);
    return true;
  }

  /// Unlocks a wallpaper for free (after watching a video ad) and puts it
  /// up straight away.
  bool unlockWallpaperWithAd(Wallpaper wallpaper) {
    final current = player.value;
    if (current == null || !wallpaper.adUnlockable) return false;
    if (current.ownsWallpaper(wallpaper)) return false;
    run('unlockWallpaper', {
      'wallpaperId': wallpaper.id,
    }, change: WalletChange(wallpaper: wallpaper.id));
    return true;
  }

  /// Store exchange: one [fish] for its [Fish.treatValue] in treats.
  bool exchangeFish(Fish fish) {
    final change = fish == Fish.tuna
        ? WalletChange(tuna: -1, treats: fish.treatValue)
        : WalletChange(salmon: -1, treats: fish.treatValue);
    if (player.value == null || !canAfford(change)) return false;
    run('exchangeFish', {'fish': fish.name}, change: change);
    return true;
  }

  /// Treats for watching a Store video (a few times a day). Returns false
  /// if today's are used up.
  bool rewardStoreAd() {
    final current = player.value;
    if (current == null || current.storeAdsLeft <= 0) return false;
    run('storeAdReward', {
      'today': DailyStatus.dateKey(DateTime.now()),
    }, change: const WalletChange(treats: Treats.storeAdReward));
    return true;
  }

  /// Switches to a wallpaper the player owns. (Not part of the wallet, so
  /// the app saves it itself.)
  void useWallpaper(Wallpaper wallpaper) {
    final current = _latest;
    if (current == null || !(player.value?.ownsWallpaper(wallpaper) ?? false)) {
      return;
    }
    _setLatest(current.copyWith(wallpaperId: wallpaper.id));
    _save(current.uid, {'wallpaper': wallpaper.id});
  }

  /// Random wallpaper every game, or always the chosen one.
  void setWallpaperRandom(bool random) {
    final current = _latest;
    if (current == null) return;
    _setLatest(current.copyWith(wallpaperRandom: random));
    _save(current.uid, {'wallpaperRandom': random});
  }

  void _save(String uid, Map<String, Object?> changes) {
    _doc(uid)
        .update(changes)
        .catchError((Object e) => debugPrint('Saving settings failed: $e'));
  }

  // ---------- Rewards ----------

  /// Pays the treat for sharing an invite, up to the daily limit. Returns
  /// whether a treat was paid.
  Future<bool> rewardShare() async {
    final current = player.value;
    if (current == null || !current.shares.canEarn) return false;
    final result = await run(
      'rewardShare',
      {'today': DailyStatus.dateKey(DateTime.now())},
      change: const WalletChange(treats: Treats.shareReward),
      quiet: true,
    );
    return result != null;
  }

  /// Claims today's sign-in reward. Returns the treats given, or null if
  /// there was nothing to claim.
  Future<int?> claimDaily() async {
    final current = player.value;
    if (current == null || !current.daily.claimable) return null;
    final result = await run('claimDaily', {
      'today': DailyStatus.dateKey(DateTime.now()),
    }, quiet: true);
    return (result?['reward'] as num?)?.toInt();
  }
}
