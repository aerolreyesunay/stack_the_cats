import 'package:flutter/material.dart';

import '../ads/ad_service.dart';
import '../audio/audio_manager.dart';
import '../economy/treats.dart';
import '../ui/treat_confetti.dart';
import '../game/cat.dart';
import '../services/player_service.dart';
import '../ui/treats_ui.dart';
import 'catalog.dart';
import 'wallpapers.dart';

const _brown = Color(0xFF5B3A29);
const _muted = Color(0xFF8A6A55);
const _accent = Color(0xFFE76F51);
const _special = Color(0xFF3A8FB7);
const _exotic = Color(0xFF9B59B6);

/// Buy new cats and wallpapers with treats.
class StoreScreen extends StatelessWidget {
  const StoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Store'),
          backgroundColor: Colors.transparent,
          actions: const [
            Padding(padding: EdgeInsets.only(right: 12), child: TreatBalance()),
          ],
          bottom: const TabBar(
            labelColor: _brown,
            unselectedLabelColor: _muted,
            indicatorColor: _accent,
            labelStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            tabs: [
              Tab(text: 'Cats'),
              Tab(text: 'Wallpapers'),
            ],
          ),
        ),
        body: ValueListenableBuilder<PlayerData?>(
          valueListenable: PlayerService.instance.player,
          builder: (context, player, _) {
            if (player == null) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Sign in (and connect to the internet) to shop.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: _muted),
                  ),
                ),
              );
            }
            return TabBarView(
              children: [
                _CatsTab(player: player),
                _WallpapersTab(player: player),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Asks before spending treats.
Future<bool> _confirmBuy(
  BuildContext context, {
  required String name,
  required int price,
  required Widget preview,
  String? note,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Colors.white,
      title: Text(
        'Buy $name?',
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w900, color: _brown),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 110, child: Center(child: preview)),
          if (note != null) ...[
            const SizedBox(height: 12),
            Text(
              note,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted),
            ),
          ],
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel', style: TextStyle(color: _muted)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _accent),
          onPressed: () => Navigator.of(context).pop(true),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Buy for '),
              TreatAmount(price, color: Colors.white, size: 15),
            ],
          ),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Not enough treats: offers a rewarded video for [Treats.storeAdReward]
/// treats.
Future<void> _notEnoughTreats(BuildContext context, int short) async {
  final videosLeft =
      (PlayerService.instance.player.value?.storeAdsLeft ?? 0) > 0;
  final watch = await showDialog<bool>(
    context: context,
    builder: (context) => ValueListenableBuilder<bool>(
      valueListenable: AdService.instance.rewardedReady,
      builder: (context, adReady, _) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Not enough treats',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w900, color: _brown),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'You need $short more treats.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 16),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: adReady && videosLeft
                    ? () => Navigator.of(context).pop(true)
                    : null,
                icon: const Icon(Icons.smart_display_rounded),
                label: !videosLeft
                    ? const Text('No more video treats today')
                    : adReady
                    ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Watch a video for ',
                            style: TextStyle(fontSize: 16),
                          ),
                          TreatAmount(
                            Treats.storeAdReward,
                            color: Colors.white,
                            size: 16,
                          ),
                        ],
                      )
                    : const Text('No video available right now'),
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now', style: TextStyle(color: _muted)),
          ),
        ],
      ),
    ),
  );
  if (watch != true || !context.mounted) return;
  final earned = await AdService.instance.showRewarded();
  if (!context.mounted) return;
  if (earned) {
    if (!PlayerService.instance.rewardStoreAd()) {
      _say(context, "That's all the video treats for today.");
      return;
    }
    showTreatConfetti(context);
    _say(context, '+${Treats.storeAdReward} treats! Thanks for watching.');
  } else {
    _say(context, 'Watch the whole video to get the treats.');
  }
}

/// Two cards a row on a phone, more on a tablet, so cards stay a
/// comfortable size.
int _columns(BuildContext context) =>
    (MediaQuery.sizeOf(context).width / 200).floor().clamp(2, 5);

void _say(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

// ---------- Cats ----------

class _CatsTab extends StatelessWidget {
  const _CatsTab({required this.player});
  final PlayerData player;

  Future<void> _buy(BuildContext context, CatBreed cat) async {
    if (player.treats < cat.price) {
      await _notEnoughTreats(context, cat.price - player.treats);
      return;
    }
    final ok = await _confirmBuy(
      context,
      name: cat.name,
      price: cat.price,
      preview: _CatPreview(cat: cat, size: 110),
    );
    if (!ok || !context.mounted) return;
    if (PlayerService.instance.buyCat(cat)) {
      AudioManager.instance.playSfx(Sfx.purrfect);
      _say(context, '${cat.name} joined your cats! It can now drop in games.');
    }
  }

  /// Some cats can be unlocked with a few videos instead of treats.
  Future<void> _watchAdFor(BuildContext context, CatBreed cat) async {
    final earned = await AdService.instance.showRewarded();
    if (!context.mounted) return;
    if (!earned) {
      _say(context, 'Watch the whole video for it to count.');
      return;
    }
    final watched = await PlayerService.instance.watchedCatAd(cat);
    if (watched == null || !context.mounted) return;
    final needed = cat.tier.adVideos;
    if (watched >= needed) {
      AudioManager.instance.playSfx(Sfx.purrfect);
      showTreatConfetti(context);
      _say(context, '${cat.name} joined your cats! It can now drop in games.');
    } else {
      final left = needed - watched;
      _say(
        context,
        '$watched of $needed videos watched. '
        '$left more to unlock ${cat.name}!',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sections = [CatTier.basic, CatTier.special, CatTier.exotic];
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            'You own ${player.catPool.length} of ${Cats.all.length} cats. '
            'Every cat you own can drop in your games.',
            style: const TextStyle(color: _muted),
          ),
        ),
        for (final tier in sections) ...[
          _TierHeader(tier: tier),
          GridView.count(
            crossAxisCount: _columns(context),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.82,
            children: [
              for (final cat in Cats.all.where((c) => c.tier == tier))
                _CatCard(
                  cat: cat,
                  owned: player.ownsCat(cat),
                  videosWatched: player.catAdsWatched(cat),
                  onBuy: () => _buy(context, cat),
                  onWatchAd: () => _watchAdFor(context, cat),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _TierHeader extends StatelessWidget {
  const _TierHeader({required this.tier});
  final CatTier tier;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(
        children: [
          _TierBadge(tier: tier),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tier == CatTier.basic ? 'Free for everyone' : tier.perk,
              style: const TextStyle(fontSize: 13, color: _muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _TierBadge extends StatelessWidget {
  const _TierBadge({required this.tier});
  final CatTier tier;

  @override
  Widget build(BuildContext context) {
    final color = switch (tier) {
      CatTier.basic => _muted,
      CatTier.special => _special,
      CatTier.exotic => _exotic,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        tier.label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CatCard extends StatelessWidget {
  const _CatCard({
    required this.cat,
    required this.owned,
    required this.videosWatched,
    required this.onBuy,
    required this.onWatchAd,
  });

  final CatBreed cat;
  final bool owned;
  final int videosWatched;
  final VoidCallback onBuy;
  final VoidCallback onWatchAd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Expanded(child: _CatPreview(cat: cat, size: 120)),
          Text(
            cat.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: _brown,
            ),
          ),
          const SizedBox(height: 6),
          if (owned)
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_rounded, size: 18, color: _muted),
                SizedBox(width: 4),
                Text('Owned', style: TextStyle(color: _muted)),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: onBuy,
                    child: TreatAmount(
                      cat.price,
                      color: Colors.white,
                      size: 15,
                    ),
                  ),
                ),
                // Or unlock it with a few videos.
                if (cat.adUnlockable) ...[
                  const SizedBox(width: 6),
                  Expanded(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: AdService.instance.rewardedReady,
                      builder: (context, adReady, _) => OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _brown,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          side: const BorderSide(color: _accent),
                        ),
                        onPressed: adReady ? onWatchAd : null,
                        icon: const Icon(
                          Icons.smart_display_rounded,
                          color: _accent,
                          size: 18,
                        ),
                        label: Text('$videosWatched/${cat.tier.adVideos}'),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          if (!owned && cat.adUnlockable)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'or watch ${cat.tier.adVideos} videos',
                style: const TextStyle(fontSize: 11, color: _muted),
              ),
            ),
        ],
      ),
    );
  }
}

/// A breed drawn as it looks in the game.
class _CatPreview extends StatelessWidget {
  const _CatPreview({required this.cat, required this.size});
  final CatBreed cat;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 0.7,
      child: CustomPaint(painter: _CatPainter(cat)),
    );
  }
}

class _CatPainter extends CustomPainter {
  const _CatPainter(this.cat);
  final CatBreed cat;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * 0.66;
    final h = w * 0.58;
    paintCat(
      canvas,
      CatLook(
        breed: cat,
        striped: cat.stripes != Stripes.never,
        tailRight: true,
        sleepy: false,
      ),
      Offset(size.width / 2, size.height * 0.62),
      w,
      h,
    );
  }

  @override
  bool shouldRepaint(_CatPainter old) => old.cat != cat;
}

// ---------- Wallpapers ----------

class _WallpapersTab extends StatelessWidget {
  const _WallpapersTab({required this.player});
  final PlayerData player;

  Future<void> _tap(BuildContext context, Wallpaper w) async {
    final service = PlayerService.instance;
    if (player.ownsWallpaper(w)) {
      service.useWallpaper(w);
      return;
    }
    if (player.treats < w.price) {
      await _notEnoughTreats(context, w.price - player.treats);
      return;
    }
    final ok = await _confirmBuy(
      context,
      name: w.name,
      price: w.price,
      preview: SizedBox(width: 90, height: 110, child: _WallPreview(w)),
      note: w.payoutBonus ? _bonusNote : null,
    );
    if (!ok || !context.mounted) return;
    if (service.buyWallpaper(w)) {
      AudioManager.instance.playSfx(Sfx.purrfect);
      _say(
        context,
        w.payoutBonus
            ? '${w.name} is up! Double treats start from your next game.'
            : '${w.name} is up on your wall!',
      );
    }
  }

  /// Some wallpapers can be unlocked with one video instead of treats.
  Future<void> _watchAdFor(BuildContext context, Wallpaper w) async {
    final earned = await AdService.instance.showRewarded();
    if (!context.mounted) return;
    if (!earned) {
      _say(context, 'Watch the whole video to unlock it.');
      return;
    }
    if (PlayerService.instance.unlockWallpaperWithAd(w)) {
      AudioManager.instance.playSfx(Sfx.purrfect);
      _say(context, '${w.name} is up on your wall!');
    }
  }

  static const _bonusNote =
      'Premium: in games started with it, every ${PayoutBonus.every} cats '
      'you stack pays double treats for ${PayoutBonus.seconds} seconds.';

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      padding: const EdgeInsets.all(12),
      crossAxisCount: _columns(context),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.72,
      children: [
        for (final w in Wallpapers.all)
          _WallCard(
            wallpaper: w,
            owned: player.ownsWallpaper(w),
            inUse: player.wallpaper.id == w.id,
            onTap: () => _tap(context, w),
            onWatchAd: () => _watchAdFor(context, w),
          ),
      ],
    );
  }
}

class _WallCard extends StatelessWidget {
  const _WallCard({
    required this.wallpaper,
    required this.owned,
    required this.inUse,
    required this.onTap,
    required this.onWatchAd,
  });

  final Wallpaper wallpaper;
  final bool owned;
  final bool inUse;
  final VoidCallback onTap;
  final VoidCallback onWatchAd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: inUse ? _accent : Colors.transparent,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: _WallPreview(wallpaper),
                ),
                if (wallpaper.payoutBonus)
                  const Positioned(top: 6, left: 6, child: _BonusBadge()),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            wallpaper.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: _brown,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: inUse
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'In use',
                        style: TextStyle(
                          color: _accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  )
                : owned
                ? OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _brown,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: onTap,
                    child: const Text('Use'),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _accent,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                          onPressed: onTap,
                          child: TreatAmount(
                            wallpaper.price,
                            color: Colors.white,
                            size: 15,
                          ),
                        ),
                      ),
                      // Or unlock it with one video.
                      if (wallpaper.adUnlockable) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: ValueListenableBuilder<bool>(
                            valueListenable: AdService.instance.rewardedReady,
                            builder: (context, adReady, _) =>
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _brown,
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    side: const BorderSide(color: _accent),
                                  ),
                                  onPressed: adReady ? onWatchAd : null,
                                  icon: const Icon(
                                    Icons.smart_display_rounded,
                                    color: _accent,
                                    size: 18,
                                  ),
                                  label: const Text('Ad'),
                                ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          if (!owned && wallpaper.adUnlockable)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'or watch one video',
                style: TextStyle(fontSize: 11, color: _muted),
              ),
            ),
        ],
      ),
    );
  }
}

/// "2× treats" on a premium wallpaper.
class _BonusBadge extends StatelessWidget {
  const _BonusBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFC08A1E),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        '2× treats',
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _WallPreview extends StatelessWidget {
  const _WallPreview(this.wallpaper);
  final Wallpaper wallpaper;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.infinite, painter: _WallPainter(wallpaper));
  }
}

class _WallPainter extends CustomPainter {
  const _WallPainter(this.wallpaper);
  final Wallpaper wallpaper;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    paintWallpaper(canvas, size, wallpaper);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WallPainter old) => old.wallpaper != wallpaper;
}
