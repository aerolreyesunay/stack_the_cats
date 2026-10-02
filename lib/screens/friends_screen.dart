import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/info_dialog.dart';
import '../challenge/challenge_screen.dart';
import '../challenge/challenge_service.dart';
import '../economy/invites.dart';
import '../economy/treats.dart';
import '../services/friends_service.dart';
import '../services/player_service.dart';
import '../ui/treats_ui.dart';

const _brown = Color(0xFF5B3A29);
const _muted = Color(0xFF8A6A55);
const _accent = Color(0xFFE76F51);
const _cream = Color(0xFFFDEBD3);

/// Invite friends with a code, add friends by their code, and see them.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _service = FriendsService.instance;
  final _codeField = TextEditingController();
  late Future<List<Friend>> _friends = _service.friends();
  bool _sharing = false;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    // Pick up treats for friends who joined since the app started.
    _service.claimReferralRewards().catchError((Object e) {
      debugPrint('Claiming invite rewards failed: $e');
      return 0;
    });
    // New friends (an accepted request, or a code) refresh the list.
    _service.friendIds.addListener(_reloadFriends);
  }

  @override
  void dispose() {
    _service.friendIds.removeListener(_reloadFriends);
    _codeField.dispose();
    super.dispose();
  }

  void _reloadFriends() {
    if (mounted) setState(() => _friends = _service.friends());
  }

  final Set<String> _answering = {};

  Future<void> _answer(FriendRequest request, {required bool accept}) async {
    setState(() => _answering.add(request.from));
    try {
      if (accept) {
        await _service.acceptRequest(request.from);
        if (mounted) {
          await showInfoDialog(
            context,
            title: catCheer(),
            message: 'You and ${request.name} are now friends!',
            icon: Icons.favorite_rounded,
            treats: Treats.friendAcceptedReward,
          );
        }
      } else {
        await _service.declineRequest(request.from);
      }
    } catch (e) {
      debugPrint('Answering friend request failed: $e');
      if (mounted) {
        await showInfoDialog(
          context,
          title: "Couldn't do that",
          message: 'Check your connection and try again.',
          icon: Icons.wifi_off_rounded,
        );
      }
    } finally {
      if (mounted) setState(() => _answering.remove(request.from));
    }
  }

  void _say(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _share(String code) async {
    setState(() => _sharing = true);
    try {
      final earned = await _service.shareInvite(code);
      if (earned > 0 && mounted) {
        await showInfoDialog(
          context,
          title: catCheer(),
          message: 'Thanks for sharing your invite!',
          icon: Icons.share_rounded,
          treats: earned,
        );
      }
    } catch (e) {
      debugPrint('Share failed: $e');
      if (mounted) _say("Couldn't open sharing. Please try again.");
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _addFriend() async {
    FocusScope.of(context).unfocus();
    setState(() => _adding = true);
    try {
      final result = await _service.redeemCode(_codeField.text);
      if (!mounted) return;
      final (title, message) = switch (result) {
        RedeemResult.friendJoined || RedeemResult.friendAdded => (
          "You're now friends!",
          'You can see each other in your friends lists and challenge each '
              'other.',
        ),
        RedeemResult.alreadyFriends => (
          'Already friends',
          "You're already friends with this player.",
        ),
        RedeemResult.ownCode => (
          "That's your code!",
          'Enter a friend\'s code.',
        ),
        RedeemResult.notFound => ('Code not found', 'No player has that code.'),
        RedeemResult.invalid => (
          'Not a code',
          'Invite codes are 6 letters and numbers.',
        ),
      };
      await showInfoDialog(context, title: title, message: message);
      if (!mounted) return;
      if (result == RedeemResult.friendJoined ||
          result == RedeemResult.friendAdded) {
        _codeField.clear();
        setState(() => _friends = _service.friends());
      }
    } catch (e) {
      debugPrint('Adding friend failed: $e');
      if (mounted) _say("Couldn't add that friend. Check your connection.");
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _refresh() async {
    final next = _service.friends();
    setState(() => _friends = next);
    try {
      await next;
    } catch (_) {
      // Shown by the FutureBuilder.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
        backgroundColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ValueListenableBuilder<List<FriendRequest>>(
              valueListenable: _service.incoming,
              builder: (context, requests, _) => _requestsCard(requests),
            ),
            ValueListenableBuilder<PlayerData?>(
              valueListenable: PlayerService.instance.player,
              builder: (context, player, _) => _inviteCard(player),
            ),
            const SizedBox(height: 12),
            _addCard(),
            const SizedBox(height: 20),
            _friendsList(),
          ],
        ),
      ),
    );
  }

  Widget _requestsCard(List<FriendRequest> requests) {
    if (requests.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _Card(
        children: [
          Text(
            'Friend requests (${requests.length})',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _brown,
            ),
          ),
          _RewardLine(
            text:
                'Accept and you both get '
                '${Treats.friendAcceptedReward} treats',
          ),
          const SizedBox(height: 6),
          for (final r in requests)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  _Avatar(name: r.name, photoUrl: r.photoUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      r.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _brown,
                      ),
                    ),
                  ),
                  if (_answering.contains(r.from))
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  else ...[
                    TextButton(
                      onPressed: () => _answer(r, accept: false),
                      style: TextButton.styleFrom(foregroundColor: _muted),
                      child: const Text('Decline'),
                    ),
                    FilledButton(
                      onPressed: () => _answer(r, accept: true),
                      style: FilledButton.styleFrom(backgroundColor: _accent),
                      child: const Text('Accept'),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _inviteCard(PlayerData? player) {
    final code = player?.inviteCode;
    final shares = player?.shares;
    return _Card(
      children: [
        const Text(
          'Your invite code',
          style: TextStyle(fontSize: 14, color: _muted),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              code ?? '······',
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                letterSpacing: 6,
                color: _brown,
              ),
            ),
            IconButton(
              tooltip: 'Copy code',
              color: _muted,
              icon: const Icon(Icons.copy_rounded),
              onPressed: code == null
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: code));
                      _say('Code copied');
                    },
            ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: code == null || _sharing ? null : () => _share(code),
          icon: const Icon(Icons.share_rounded),
          label: const Text('Invite friends', style: TextStyle(fontSize: 17)),
        ),
        const SizedBox(height: 10),
        _RewardLine(
          text: shares == null || shares.canEarn
              ? '+${Treats.shareReward} '
                    '${Treats.shareReward == 1 ? 'treat' : 'treats'} '
                    'for each share '
                    '(${shares?.left ?? Treats.maxPaidSharesPerDay} '
                    'left today)'
              : 'Share rewards are used up for today',
        ),
        const _RewardLine(
          text:
              '+${Treats.friendJoinedReward} treats when a new player joins '
              'with your code and stacks their first '
              '${Treats.referralMinLandings} cats',
        ),
      ],
    );
  }

  Widget _addCard() {
    return _Card(
      children: [
        const Text(
          "Have a friend's code?",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: _brown,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _codeField,
                textCapitalization: TextCapitalization.characters,
                maxLength: Invites.codeLength + 2, // allow a space or dash
                decoration: const InputDecoration(
                  hintText: 'e.g. CAT7QK',
                  counterText: '',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _addFriend(),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _brown),
              onPressed: _adding ? null : _addFriend,
              child: _adding
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Add'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _friendsList() {
    return FutureBuilder<List<Friend>>(
      future: _friends,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          debugPrint('Friends list failed: ${snap.error}');
          return Column(
            children: [
              const Text(
                "Couldn't load your friends.",
                style: TextStyle(color: _muted),
              ),
              TextButton(onPressed: _refresh, child: const Text('Retry')),
            ],
          );
        }
        final friends = snap.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                'Your friends (${friends.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _brown,
                ),
              ),
            ),
            if (friends.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Icon(Icons.group_outlined, size: 44, color: _muted),
                    SizedBox(height: 8),
                    Text(
                      'No friends yet.\nInvite some to stack with!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _muted),
                    ),
                  ],
                ),
              )
            else
              for (final f in friends) _FriendRow(friend: f),
          ],
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _RewardLine extends StatelessWidget {
  const _RewardLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          const TreatIcon(size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: _muted),
            ),
          ),
        ],
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
      radius: 18,
      backgroundColor: _cream,
      foregroundImage: url != null ? NetworkImage(url) : null,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: const TextStyle(color: _brown, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// A friend, their live status (online / playing / offline) and a
/// Challenge button while they're free to play.
class _FriendRow extends StatefulWidget {
  const _FriendRow({required this.friend});
  final Friend friend;

  @override
  State<_FriendRow> createState() => _FriendRowState();
}

class _FriendRowState extends State<_FriendRow> {
  late final Stream<Presence> _presence = ChallengeService.instance.presenceOf(
    widget.friend.uid,
  );
  bool _sending = false;

  Future<void> _challenge() async {
    setState(() => _sending = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final friend = widget.friend;
    try {
      final matchId = await ChallengeService.instance.sendChallenge(
        friendUid: friend.uid,
        friendName: friend.name,
        friendPhoto: friend.photoUrl,
      );
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => ChallengeScreen(
            matchId: matchId,
            friendUid: friend.uid,
            friendName: friend.name,
            isChallenger: true,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Sending challenge failed: $e');
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Couldn't send the challenge. Check your connection."),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final friend = widget.friend;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: StreamBuilder<Presence>(
        stream: _presence,
        initialData: Presence.offline,
        builder: (context, snap) {
          final presence = snap.data ?? Presence.offline;
          return Row(
            children: [
              Stack(
                children: [
                  _Avatar(name: friend.name, photoUrl: friend.photoUrl),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: _PresenceDot(presence),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      friend.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _brown,
                      ),
                    ),
                    Text(
                      [
                        switch (presence) {
                          Presence.online => 'Online',
                          Presence.playing => 'Playing',
                          Presence.offline => 'Offline',
                        },
                        if (friend.best > 0) 'Best ${friend.best}',
                      ].join('  ·  '),
                      style: const TextStyle(fontSize: 12, color: _muted),
                    ),
                  ],
                ),
              ),
              if (presence == Presence.online)
                _sending
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _accent,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _challenge,
                        icon: const Icon(
                          Icons.sports_esports_rounded,
                          size: 18,
                        ),
                        label: const Text('Challenge'),
                      ),
            ],
          );
        },
      ),
    );
  }
}

class _PresenceDot extends StatelessWidget {
  const _PresenceDot(this.presence);
  final Presence presence;

  @override
  Widget build(BuildContext context) {
    final color = switch (presence) {
      Presence.online => const Color(0xFF4CAF50),
      Presence.playing => const Color(0xFFF4A259),
      Presence.offline => const Color(0xFFBDBDBD),
    };
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
    );
  }
}
