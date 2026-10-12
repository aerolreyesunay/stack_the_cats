import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../auth/auth_service.dart';
import '../game/cat.dart';
import '../services/game_session.dart';
import '../services/leaderboard_service.dart';
import '../services/public_name.dart';
import '../store/catalog.dart';
import 'treats_ui.dart';

const _siteUrl = 'https://jcanstudios.github.io/stack-the-cats/';

/// The look of a share card: gold, silver and bronze for the top three this
/// week, a ranked card for the rest of the top 20, and a plain one.
enum ShareTier { gold, silver, bronze, top20, none }

ShareTier shareTierFor(int? rank) => switch (rank) {
  1 => ShareTier.gold,
  2 => ShareTier.silver,
  3 => ShareTier.bronze,
  final r? when r > 0 && r <= 20 => ShareTier.top20,
  _ => ShareTier.none,
};

/// The words that go with the picture (Facebook drops them, the others
/// keep them).
String shareText({required int score, int? rank}) {
  final cats = score == 1 ? 'cat' : 'cats';
  final ranked = shareTierFor(rank) == ShareTier.none
      ? ''
      : "I'm #$rank on this week's leaderboard! ";
  return '${ranked}I stacked $score $cats in Stack the Cats 🐱 '
      'Can you stack higher? $_siteUrl';
}

/// After a game: a preview of the share card (name, cats stacked, and the
/// weekly rank if in the top 20), and the phone's share sheet (Facebook,
/// TikTok, Instagram and so on) for it.
Future<void> showShareResult(
  BuildContext context, {
  required int score,
  required List<CatBreed> pool,
}) => showDialog<void>(
  context: context,
  builder: (_) => _ShareDialog(score: score, pool: pool),
);

class _ShareDialog extends StatefulWidget {
  const _ShareDialog({required this.score, required this.pool});
  final int score;
  final List<CatBreed> pool;

  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  final _card = GlobalKey();
  late final Future<int?> _rank = _loadRank();
  bool _sharing = false;

  /// This week's rank, once the last cats have reached the server. Null
  /// if signed out, not on the board, or it can't be read.
  Future<int?> _loadRank() async {
    if (AuthService.instance.currentUser == null) return null;
    try {
      await GameSession.allSent.timeout(const Duration(seconds: 6));
      final standing = await LeaderboardService.instance
          .myStanding(Board.weekly)
          .timeout(const Duration(seconds: 6));
      return standing?.rank;
    } catch (e) {
      debugPrint('Weekly rank for sharing failed: $e');
      return null;
    }
  }

  Future<void> _share(int? rank) async {
    setState(() => _sharing = true);
    try {
      final boundary =
          _card.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      // 1080 × 1350: a full-size portrait post.
      final image = await boundary.toImage(
        pixelRatio: 1080 / ShareCard.size.width,
      );
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (png == null) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              png.buffer.asUint8List(),
              mimeType: 'image/png',
              name: 'stack-the-cats.png',
            ),
          ],
          text: shareText(score: widget.score, rank: rank),
        ),
      );
    } catch (e) {
      debugPrint('Sharing failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open sharing. Try again?")),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    final name = user == null ? null : publicName(user.displayName);
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(24),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<int?>(
          future: _rank,
          builder: (context, snap) {
            final loading = snap.connectionState != ConnectionState.done;
            final rank = snap.data;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: ShareCard.size.aspectRatio,
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : FittedBox(
                          child: RepaintBoundary(
                            key: _card,
                            child: ShareCard(
                              score: widget.score,
                              name: name,
                              rank: rank,
                              pool: widget.pool,
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: treatColor,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: loading || _sharing ? null : () => _share(rank),
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('Share', style: TextStyle(fontSize: 17)),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Close',
                    style: TextStyle(color: Color(0xFF8A6A55)),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Colours for each [ShareTier].
class _CardStyle {
  const _CardStyle({
    required this.background,
    required this.ink,
    required this.soft,
    required this.accent,
    this.medal,
    this.label,
  });

  final List<Color> background;
  final Color ink;
  final Color soft;
  final Color accent;

  /// The medal's face (top three only) and its name.
  final List<Color>? medal;
  final String? label;

  static _CardStyle of(ShareTier tier) => switch (tier) {
    ShareTier.gold => const _CardStyle(
      background: [Color(0xFFFFF6D6), Color(0xFFFBD872), Color(0xFFE7A92B)],
      ink: Color(0xFF5A3A00),
      soft: Color(0xFF8A6100),
      accent: Color(0xFFB7791F),
      medal: [Color(0xFFFFF1A8), Color(0xFFF2C230), Color(0xFFC98E12)],
      label: 'GOLD',
    ),
    ShareTier.silver => const _CardStyle(
      background: [Color(0xFFF7F9FB), Color(0xFFD9E0E7), Color(0xFFAAB5C0)],
      ink: Color(0xFF2F3A45),
      soft: Color(0xFF55616D),
      accent: Color(0xFF6E7B88),
      medal: [Color(0xFFFFFFFF), Color(0xFFCBD3DB), Color(0xFF8E9AA6)],
      label: 'SILVER',
    ),
    ShareTier.bronze => const _CardStyle(
      background: [Color(0xFFFCEBDD), Color(0xFFEAB58A), Color(0xFFC27C45)],
      ink: Color(0xFF4A2610),
      soft: Color(0xFF7A4520),
      accent: Color(0xFF9C5A2B),
      medal: [Color(0xFFF6D2B0), Color(0xFFD08A52), Color(0xFF9A5A2A)],
      label: 'BRONZE',
    ),
    _ => const _CardStyle(
      background: [Color(0xFFFFF8EE), Color(0xFFFBE7CF), Color(0xFFF6D3AE)],
      ink: Color(0xFF5B3A29),
      soft: Color(0xFF8A6A55),
      accent: treatColor,
    ),
  };
}

/// The picture that gets shared: the player's cats stacked up, how many,
/// their name, and their weekly rank in the top 20 (with a gold, silver or
/// bronze medal for the top three).
class ShareCard extends StatelessWidget {
  const ShareCard({
    super.key,
    required this.score,
    required this.name,
    required this.rank,
    required this.pool,
  });

  /// Drawn at this size and saved at 3×: 1080 × 1350.
  static const size = Size(360, 450);

  final int score;

  /// "First L." (null for guests).
  final String? name;
  final int? rank;
  final List<CatBreed> pool;

  @override
  Widget build(BuildContext context) {
    final tier = shareTierFor(rank);
    final style = _CardStyle.of(tier);
    final medal = style.medal;
    return SizedBox.fromSize(
      size: size,
      // Its own text style, so the saved picture looks the same wherever
      // the card is shown.
      child: Material(
        type: MaterialType.transparency,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: style.background,
            ),
          ),
          child: Stack(
            children: [
              if (medal != null)
                Positioned.fill(
                  child: CustomPaint(painter: _SparklePainter(Colors.white)),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                child: Column(
                  children: [
                    Text(
                      'STACK THE CATS',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                        color: style.ink,
                      ),
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _TowerPainter(
                                score: score,
                                pool: pool,
                                cushion: style.accent,
                              ),
                            ),
                          ),
                          if (medal != null)
                            Positioned(
                              right: 0,
                              top: 10,
                              child: _Medal(
                                rank: rank!,
                                colors: medal,
                                ink: style.ink,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      '$score',
                      style: TextStyle(
                        fontSize: 68,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        color: style.ink,
                      ),
                    ),
                    Text(
                      score == 1 ? 'cat stacked' : 'cats stacked',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: style.soft,
                      ),
                    ),
                    if (name case final name?) ...[
                      const SizedBox(height: 2),
                      Text(
                        'by $name',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, color: style.soft),
                      ),
                    ],
                    if (tier != ShareTier.none) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: style.ink,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          [
                            ?style.label,
                            "#$rank on this week's leaderboard",
                          ].join(' · '),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'Can you stack higher?',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: style.ink,
                      ),
                    ),
                    Text(
                      'Free on Google Play',
                      style: TextStyle(fontSize: 12, color: style.soft),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A few of the player's cats stacked on the cushion, slightly wobbly.
class _TowerPainter extends CustomPainter {
  const _TowerPainter({
    required this.score,
    required this.pool,
    required this.cushion,
  });

  final int score;
  final List<CatBreed> pool;
  final Color cushion;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(score);
    final count = score.clamp(1, 5);
    const cushionH = 14.0;
    // Room on top for the top cat's ears.
    final catH = min(42.0, (size.height - cushionH - 22) / count);
    final catW = catH / 0.58;
    final cx = size.width / 2;
    final floor = size.height - 4;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - catW * 0.7, floor - cushionH, catW * 1.4, cushionH),
        const Radius.circular(8),
      ),
      Paint()..color = cushion,
    );
    for (var i = 0; i < count; i++) {
      final x = cx + (rng.nextDouble() - 0.5) * catW * 0.25;
      final y = floor - cushionH - catH / 2 - i * catH;
      paintCat(canvas, CatLook.random(rng, pool), Offset(x, y), catW, catH);
    }
  }

  @override
  bool shouldRepaint(_TowerPainter old) =>
      old.score != score || old.pool != pool || old.cushion != cushion;
}

/// A round medal with ribbon tails and the rank on it.
class _Medal extends StatelessWidget {
  const _Medal({required this.rank, required this.colors, required this.ink});

  final int rank;
  final List<Color> colors;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      height: 100,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          // Ribbon tails.
          Positioned(
            top: 50,
            child: CustomPaint(
              size: const Size(56, 48),
              painter: _RibbonPainter(colors.last),
            ),
          ),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.3, -0.4),
                colors: colors,
              ),
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              '#$rank',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RibbonPainter extends CustomPainter {
  const _RibbonPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final w = size.width;
    final h = size.height;
    // Two tails with a notch at the bottom of each.
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.15, 0)
        ..lineTo(w * 0.45, 0)
        ..lineTo(w * 0.35, h)
        ..lineTo(w * 0.22, h * 0.82)
        ..lineTo(w * 0.05, h)
        ..close(),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.55, 0)
        ..lineTo(w * 0.85, 0)
        ..lineTo(w * 0.95, h)
        ..lineTo(w * 0.78, h * 0.82)
        ..lineTo(w * 0.65, h)
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(_RibbonPainter old) => old.color != color;
}

/// Little four-point sparkles scattered over a medal card.
class _SparklePainter extends CustomPainter {
  const _SparklePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(3);
    final paint = Paint()..color = color.withAlpha(150);
    for (var i = 0; i < 18; i++) {
      final at = Offset(
        rng.nextDouble() * size.width,
        rng.nextDouble() * size.height,
      );
      final r = 3 + rng.nextDouble() * 5;
      canvas.drawPath(
        Path()
          ..moveTo(at.dx, at.dy - r)
          ..quadraticBezierTo(at.dx, at.dy, at.dx + r, at.dy)
          ..quadraticBezierTo(at.dx, at.dy, at.dx, at.dy + r)
          ..quadraticBezierTo(at.dx, at.dy, at.dx - r, at.dy)
          ..quadraticBezierTo(at.dx, at.dy, at.dx, at.dy - r)
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.color != color;
}
