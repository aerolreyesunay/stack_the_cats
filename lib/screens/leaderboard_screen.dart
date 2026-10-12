import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../ui/info_dialog.dart';
import '../auth/auth_service.dart';
import '../economy/treats.dart';
import '../services/age_gate.dart';
import '../services/friends_service.dart';
import '../services/leaderboard_service.dart';
import '../services/player_service.dart';
import '../store/catalog.dart';
import '../ui/share_result.dart';

const _brown = Color(0xFF5B3A29);
const _muted = Color(0xFF8A6A55);
const _accent = Color(0xFFE76F51);
const _cream = Color(0xFFFDEBD3);
const _medals = [Color(0xFFE9B949), Color(0xFFA7B1BC), Color(0xFFC98B5B)];

/// Weekly and all-time top players. Players can send friend requests
/// straight from here.
class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Leaderboard'),
          backgroundColor: Colors.transparent,
          bottom: const TabBar(
            labelColor: _brown,
            unselectedLabelColor: _muted,
            indicatorColor: _accent,
            labelStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            tabs: [
              Tab(text: 'This week'),
              Tab(text: 'All time'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _BoardView(board: Board.weekly),
            _BoardView(board: Board.allTime),
          ],
        ),
      ),
    );
  }
}

class _BoardData {
  const _BoardData(this.entries, this.me);
  final List<LeaderboardEntry> entries;
  final MyStanding? me;
}

class _BoardView extends StatefulWidget {
  const _BoardView({required this.board});
  final Board board;

  @override
  State<_BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<_BoardView>
    with AutomaticKeepAliveClientMixin {
  final _service = LeaderboardService.instance;
  late Future<_BoardData> _data = _load();

  @override
  bool get wantKeepAlive => true; // don't reload when switching tabs

  Future<_BoardData> _load() async {
    // The player's own rank is a bonus: if it fails, still show the board.
    final me = _service
        .myStanding(widget.board)
        .then<MyStanding?>(
          (s) => s,
          onError: (Object e) {
            debugPrint('Own rank failed: $e');
            return null;
          },
        );
    final entries = await _service.withFullNames(
      await _service.top(widget.board),
      FriendsService.instance.friendIds.value,
    );
    return _BoardData(entries, await me);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _data = next);
    try {
      await next;
    } catch (_) {
      // Shown by the FutureBuilder.
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<_BoardData>(
      future: _data,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          debugPrint('Leaderboard failed: ${snap.error}');
          return _Message(
            icon: Icons.wifi_off_rounded,
            text: "Couldn't load the leaderboard.\nCheck your connection.",
            action: TextButton(onPressed: _refresh, child: const Text('Retry')),
          );
        }
        final data = snap.data!;
        return Column(
          children: [
            if (widget.board == Board.weekly) const _WeekCountdown(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: data.entries.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 80),
                          _Message(
                            icon: Icons.emoji_events_outlined,
                            text: 'No scores yet.\nPlay a game to be first!',
                          ),
                        ],
                      )
                    : _list(data),
              ),
            ),
            _MyFooter(board: widget.board, entries: data.entries, me: data.me),
          ],
        );
      },
    );
  }

  Widget _list(_BoardData data) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: data.entries.length,
      itemBuilder: (context, i) => _Row(
        board: widget.board,
        rank: i + 1,
        entry: data.entries[i],
        isMe: data.entries[i].uid == myUid,
      ),
    );
  }
}

/// "Resets in 3d 14h" above the weekly board.
class _WeekCountdown extends StatelessWidget {
  const _WeekCountdown();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final left = LeaderboardWeek.endsAt(now).difference(now.toUtc());
    final days = left.inDays;
    final hours = left.inHours % 24;
    final text = days > 0
        ? 'Resets in ${days}d ${hours}h'
        : 'Resets in ${hours}h ${left.inMinutes % 60}m';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.schedule_rounded, size: 16, color: _muted),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: _muted)),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.board,
    required this.rank,
    required this.entry,
    required this.isMe,
  });

  final Board board;
  final int rank;
  final LeaderboardEntry entry;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? _accent.withAlpha(30) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMe ? _accent : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          SizedBox(width: 36, child: _RankBadge(rank)),
          const SizedBox(width: 8),
          // Kids' mode shows initials only, not other players' photos.
          _Avatar(
            name: entry.name,
            photoUrl: AgeGate.instance.isKid ? null : entry.photoUrl,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isMe ? '${entry.name} (you)' : entry.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isMe ? FontWeight.w800 : FontWeight.w600,
                color: _brown,
              ),
            ),
          ),
          Text(
            '${entry.score}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: _brown,
            ),
          ),
          // Same width on every row so the scores line up. The player's
          // own row has Share (a poster of their rank) instead.
          SizedBox(
            width: 40,
            child: AgeGate.instance.isKid
                ? null
                : isMe
                ? _ShareRankButton(
                    board: board,
                    standing: MyStanding(rank: rank, score: entry.score),
                  )
                : _AddFriendButton(entry: entry),
          ),
        ],
      ),
    );
  }
}

/// Sends a leaderboard player a friend request. Shows an hourglass while
/// it's waiting for them, and a tick once they've accepted.
class _AddFriendButton extends StatefulWidget {
  const _AddFriendButton({required this.entry});

  final LeaderboardEntry entry;

  @override
  State<_AddFriendButton> createState() => _AddFriendButtonState();
}

class _AddFriendButtonState extends State<_AddFriendButton> {
  final _friends = FriendsService.instance;
  bool _busy = false;

  Future<void> _add() async {
    setState(() => _busy = true);
    final name = widget.entry.name;
    try {
      final result = await _friends.sendRequest(widget.entry.uid);
      if (!mounted) return;
      final (title, message) = switch (result) {
        RequestResult.sent => (
          'Friend request sent!',
          "You'll both get ${Treats.friendAcceptedReward} treats when "
              '$name accepts.',
        ),
        RequestResult.accepted => (
          catCheer(),
          'You and $name are now friends!',
        ),
        RequestResult.alreadySent => (
          'Request already sent',
          'Waiting for $name to accept.',
        ),
        RequestResult.alreadyFriends => (
          'Already friends',
          'You and $name are already friends.',
        ),
      };
      await showInfoDialog(
        context,
        title: title,
        message: message,
        treats: result == RequestResult.accepted
            ? Treats.friendAcceptedReward
            : null,
      );
    } catch (e) {
      debugPrint('Friend request failed: $e');
      if (mounted) {
        await showInfoDialog(
          context,
          title: "Couldn't send the request",
          message: 'Check your connection and try again.',
          icon: Icons.wifi_off_rounded,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Signed-out players can look but not add.
    if (AuthService.instance.currentUser == null) return const SizedBox();
    final uid = widget.entry.uid;
    return ListenableBuilder(
      listenable: Listenable.merge([_friends.friendIds, _friends.outgoing]),
      builder: (context, _) {
        if (_friends.friendIds.value.contains(uid)) {
          return const Tooltip(
            message: 'Friend',
            child: Icon(Icons.how_to_reg_rounded, color: _muted, size: 22),
          );
        }
        if (_friends.outgoing.value.contains(uid)) {
          return const Tooltip(
            message: 'Request sent',
            child: Icon(Icons.hourglass_top_rounded, color: _muted, size: 20),
          );
        }
        if (_busy) {
          return const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          );
        }
        return IconButton(
          tooltip: 'Add friend',
          color: _accent,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.person_add_alt_1_rounded),
          onPressed: _add,
        );
      },
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge(this.rank);
  final int rank;

  @override
  Widget build(BuildContext context) {
    if (rank <= 3) {
      return Icon(
        Icons.emoji_events_rounded,
        color: _medals[rank - 1],
        size: 26,
      );
    }
    return Text(
      '$rank',
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: _muted,
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.photoUrl});
  final String name;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    return CircleAvatar(
      radius: 17,
      backgroundColor: _cream,
      foregroundImage: url != null ? NetworkImage(url) : null,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: const TextStyle(color: _brown, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Pinned at the bottom: the player's own rank, or a nudge to sign in.
/// The player's place when it's below the list (with Share), or how to get
/// on the board. Hidden when their row is already in the list.
class _MyFooter extends StatelessWidget {
  const _MyFooter({
    required this.board,
    required this.entries,
    required this.me,
  });

  final Board board;
  final List<LeaderboardEntry> entries;
  final MyStanding? me;

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    final standing = me;
    final String text;
    if (user == null) {
      text = 'Sign in on the main menu to join the leaderboard';
    } else if (standing == null) {
      text = 'Finish a game to get on the board';
    } else if (standing.rank <= entries.length) {
      // Already visible (and highlighted, with Share) in the list.
      return const SizedBox.shrink();
    } else {
      text = 'You: #${standing.rank} with ${standing.score} cats';
    }
    final canShare = standing != null && !AgeGate.instance.isKid;
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(16, 14, canShare ? 6 : 16, 14),
        color: Colors.white,
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                textAlign: canShare ? TextAlign.start : TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _brown,
                ),
              ),
            ),
            if (canShare) _ShareRankButton(board: board, standing: standing),
          ],
        ),
      ),
    );
  }
}

/// Opens a poster of the player's rank on [board] to share.
class _ShareRankButton extends StatelessWidget {
  const _ShareRankButton({required this.board, required this.standing});

  final Board board;
  final MyStanding standing;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Share my rank',
      color: _accent,
      icon: const Icon(Icons.share_rounded),
      onPressed: () => showShareRank(
        context,
        board: board,
        standing: standing,
        pool: PlayerService.instance.player.value?.catPool ?? Cats.basic,
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: _muted),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: _muted),
          ),
          ?action,
        ],
      ),
    );
  }
}
