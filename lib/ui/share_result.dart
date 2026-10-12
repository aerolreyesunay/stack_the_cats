import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../auth/auth_service.dart';
import '../game/cat.dart';
import '../services/leaderboard_service.dart';
import '../services/public_name.dart';
import '../store/catalog.dart';
import 'treats_ui.dart';

/// One link for every phone: Android goes to Google Play, iPhone to the
/// App Store (once it's there), anything else to a page with both.
const _siteUrl = 'https://jcanstudios.github.io/stack-the-cats/get/';

/// The words that go with a game's picture (Facebook drops them, the
/// others keep them).
String shareText({required int score}) {
  final cats = score == 1 ? 'cat' : 'cats';
  return 'I stacked $score $cats in Stack the Cats 🐱 '
      'Can you stack higher? $_siteUrl';
}

/// The words that go with a leaderboard poster.
String rankShareText({
  required Board board,
  required int rank,
  required int best,
}) {
  final where = board == Board.weekly
      ? "on this week's Stack the Cats leaderboard"
      : 'of all time in Stack the Cats';
  final cats = best == 1 ? 'cat' : 'cats';
  return "I'm #$rank $where with $best $cats! 🐱 Can you beat me? $_siteUrl";
}

/// After a game: a preview of the game's share card (the cats, how many
/// and the player's name; ranks are shared from the leaderboard), and the
/// phone's share sheet (Facebook, TikTok, Instagram and so on) for it.
Future<void> showShareResult(
  BuildContext context, {
  required int score,
  required List<CatBreed> pool,
}) => _showShareDialog(
  context,
  () async => (
    card: ShareCard(score: score, name: _myName(), pool: pool),
    text: shareText(score: score),
  ),
);

/// From the leaderboard: a poster of the player's weekly or all-time rank.
Future<void> showShareRank(
  BuildContext context, {
  required Board board,
  required MyStanding standing,
  required List<CatBreed> pool,
}) => _showShareDialog(
  context,
  () async => (
    card: RankPoster(
      board: board,
      rank: standing.rank,
      best: standing.score,
      name: _myName(),
      pool: pool,
      now: DateTime.now(),
    ),
    text: rankShareText(
      board: board,
      rank: standing.rank,
      best: standing.score,
    ),
  ),
);

/// The player's first name for the pictures (null for guests).
String? _myName() {
  final user = AuthService.instance.currentUser;
  return user == null ? null : firstName(user.displayName);
}

/// A picture to share (drawn at [ShareCard.size]) and its words.
typedef _Shareable = ({Widget card, String text});

Future<void> _showShareDialog(
  BuildContext context,
  Future<_Shareable> Function() prepare,
) => showDialog<void>(
  context: context,
  builder: (_) => _ShareDialog(prepare: prepare),
);

/// The preview, with Share (the phone's share sheet) and Close.
class _ShareDialog extends StatefulWidget {
  const _ShareDialog({required this.prepare});
  final Future<_Shareable> Function() prepare;

  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  final _card = GlobalKey();
  late final Future<_Shareable> _item = widget.prepare();
  bool _sharing = false;

  Future<void> _share(String text) async {
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
          text: text,
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
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(24),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<_Shareable>(
          future: _item,
          builder: (context, snap) {
            final item = snap.data;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: ShareCard.size.aspectRatio,
                  child: item == null
                      ? const Center(child: CircularProgressIndicator())
                      : FittedBox(
                          child: RepaintBoundary(key: _card, child: item.card),
                        ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: treatColor,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: item == null || _sharing
                      ? null
                      : () => _share(item.text),
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

/// Cartoon outlines: one dark ink for every card.
const _ink = Color(0xFF3B2416);
const _font = 'LilitaOne';

/// The picture shared after a game, in a cartoon style: the Stack the Cats
/// logo, the player's cats stacked on a sunburst (the top one bragging in a
/// speech bubble), the score in a comic starburst, and their name.
class ShareCard extends StatelessWidget {
  const ShareCard({
    super.key,
    required this.score,
    required this.name,
    required this.pool,
  });

  /// Drawn at this size and saved at 3×: 1080 × 1350.
  static const size = Size(360, 450);

  final int score;

  /// The player's first name (null for guests).
  final String? name;
  final List<CatBreed> pool;

  @override
  Widget build(BuildContext context) {
    final digits = '$score'.length;
    return SizedBox.fromSize(
      size: size,
      // Its own text style, so the saved picture looks the same wherever
      // the card is shown.
      child: Material(
        type: MaterialType.transparency,
        child: ClipRect(
          child: Stack(
            children: [
              const Positioned.fill(
                child: CustomPaint(
                  painter: _SunburstPainter([
                    Color(0xFFFFE9D2),
                    Color(0xFFFFD6AE),
                  ]),
                ),
              ),
              const Positioned.fill(
                child: CustomPaint(painter: _ConfettiPainter()),
              ),
              // The logo, tilted a little.
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: Transform.rotate(
                  angle: -0.04,
                  child: const Center(
                    child: _Lockup(iconSize: 46, textSize: 28),
                  ),
                ),
              ),
              // The cats, on their cushion.
              Positioned(
                left: 95,
                right: 95,
                top: 62,
                height: 160,
                child: CustomPaint(
                  painter: _TowerPainter(score: score, pool: pool),
                ),
              ),
              const Positioned(
                left: 12,
                top: 78,
                child: _SpeechBubble('Beat that!'),
              ),
              // The score in a comic starburst.
              Positioned(
                left: 0,
                right: 0,
                top: 214,
                height: 118,
                child: CustomPaint(
                  painter: const _StarburstPainter(Color(0xFFFFE066)),
                  child: Center(
                    child: _InkText(
                      '$score',
                      size: digits >= 4 ? 50 : 60,
                      fill: _ink,
                      stroke: 0,
                    ),
                  ),
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                top: 318,
                child: Center(child: _Ribbon(color: treatColor)),
              ),
              if (name case final name?)
                Positioned(
                  left: 20,
                  right: 20,
                  top: 361,
                  child: _InkText(
                    'by $name',
                    size: 17,
                    fill: Colors.white,
                    stroke: 4,
                  ),
                ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: Center(child: _CallToAction()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chunky cartoon lettering: [fill] with a thick ink outline ([stroke]
/// wide; 0 for none) and a little drop shadow.
class _InkText extends StatelessWidget {
  const _InkText(
    this.text, {
    required this.size,
    required this.fill,
    required this.stroke,
    this.letterSpacing = 0,
  });

  final String text;
  final double size;
  final Color fill;
  final double stroke;
  final double letterSpacing;

  @override
  Widget build(BuildContext context) {
    TextStyle style({Paint? foreground, Color? color}) => TextStyle(
      fontFamily: _font,
      fontSize: size,
      height: 1.1,
      letterSpacing: letterSpacing,
      color: color,
      foreground: foreground,
    );
    Text line(TextStyle s) => Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: s,
    );
    Paint outline(Color color) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    return Stack(
      alignment: Alignment.center,
      children: [
        if (stroke > 0) ...[
          // Shadow, then outline, then the letters.
          Transform.translate(
            offset: Offset(0, size * 0.08),
            child: line(style(foreground: outline(_ink.withAlpha(90)))),
          ),
          line(style(foreground: outline(_ink))),
        ],
        line(style(color: fill)),
      ],
    );
  }
}

/// A white comic speech bubble with its tail pointing at the cats.
class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble(this.text, {this.tailLeft = false});
  final String text;

  /// Point the tail down-left (for a cat on the bubble's left).
  final bool tailLeft;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: tailLeft ? 0.08 : -0.08,
      child: CustomPaint(
        painter: _BubblePainter(tailLeft: tailLeft),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 104),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: _font,
              fontSize: 17,
              height: 1.05,
              color: _ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  const _BubblePainter({this.tailLeft = false});
  final bool tailLeft;

  @override
  void paint(Canvas canvas, Size size) {
    if (tailLeft) {
      // Mirrored (the text on top isn't).
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height - 10),
      const Radius.circular(16),
    );
    // Tail down and to the right, towards the top cat.
    final tail = Path()
      ..moveTo(size.width * 0.62, size.height - 12)
      ..lineTo(size.width * 0.95, size.height + 6)
      ..lineTo(size.width * 0.80, size.height - 12)
      ..close();
    final shape = Path.combine(
      PathOperation.union,
      Path()..addRRect(body),
      tail,
    );
    canvas.drawPath(
      shape.shift(const Offset(0, 3)),
      Paint()..color = _ink.withAlpha(70),
    );
    canvas.drawPath(shape, Paint()..color = Colors.white);
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..color = _ink,
    );
  }

  @override
  bool shouldRepaint(_BubblePainter old) => old.tailLeft != tailLeft;
}

/// "CATS STACKED!" (or [text]) on a ribbon banner with folded ends.
class _Ribbon extends StatelessWidget {
  const _Ribbon({required this.color, this.text = 'CATS STACKED!'});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RibbonBannerPainter(color),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 46, vertical: 7),
        child: _InkText(text, size: 22, fill: Colors.white, stroke: 5),
      ),
    );
  }
}

class _RibbonBannerPainter extends CustomPainter {
  const _RibbonBannerPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round
      ..color = _ink;
    final darker = Color.lerp(color, _ink, 0.35)!;
    // The folded tails, behind the band.
    for (final left in [true, false]) {
      final x0 = left ? 0.0 : w;
      final dir = left ? 1.0 : -1.0;
      final tail = Path()
        ..moveTo(x0 + dir * 30, 6)
        ..lineTo(x0, 6)
        ..lineTo(x0 + dir * 12, h / 2 + 6)
        ..lineTo(x0, h + 6)
        ..lineTo(x0 + dir * 30, h + 6)
        ..close();
      canvas.drawPath(tail, Paint()..color = darker);
      canvas.drawPath(tail, outline);
    }
    final band = RRect.fromRectAndRadius(
      Rect.fromLTWH(18, 0, w - 36, h),
      const Radius.circular(6),
    );
    canvas.drawRRect(band, Paint()..color = color);
    canvas.drawRRect(band, outline);
  }

  @override
  bool shouldRepaint(_RibbonBannerPainter old) => old.color != color;
}

/// "CAN YOU STACK HIGHER?" as a big button-like pill, with the store
/// underneath.
class _CallToAction extends StatelessWidget {
  const _CallToAction({this.text = 'CAN YOU STACK HIGHER?'});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _ink, width: 3),
        boxShadow: const [
          BoxShadow(color: Color(0x553B2416), offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: const TextStyle(
              fontFamily: _font,
              fontSize: 17,
              height: 1.1,
              color: treatColor,
            ),
          ),
          const Text(
            'Free on Google Play',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// The player's cats stacked on an outlined cushion, slightly wobbly.
class _TowerPainter extends CustomPainter {
  const _TowerPainter({required this.score, required this.pool});

  final int score;
  final List<CatBreed> pool;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(score);
    final count = score.clamp(1, 5);
    const cushionH = 16.0;
    // Room on top for the top cat's ears.
    final catH = min(40.0, (size.height - cushionH - 22) / count);
    final catW = catH / 0.58;
    final cx = size.width / 2;
    final floor = size.height - 4;
    final cushion = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - catW * 0.72, floor - cushionH, catW * 1.44, cushionH),
      const Radius.circular(9),
    );
    canvas.drawRRect(cushion, Paint()..color = treatColor);
    canvas.drawRRect(
      cushion,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = _ink,
    );
    for (var i = 0; i < count; i++) {
      final x = cx + (rng.nextDouble() - 0.5) * catW * 0.25;
      final y = floor - cushionH - catH / 2 - i * catH;
      paintCat(canvas, CatLook.random(rng, pool), Offset(x, y), catW, catH);
    }
  }

  @override
  bool shouldRepaint(_TowerPainter old) =>
      old.score != score || old.pool != pool;
}

/// Alternating rays from behind the cats, with a soft glow in the middle.
class _SunburstPainter extends CustomPainter {
  const _SunburstPainter(this.colors);
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = colors[0]);
    final center = Offset(size.width / 2, size.height * 0.42);
    final radius = size.longestSide;
    const rays = 18;
    final paint = Paint()..color = colors[1];
    for (var i = 0; i < rays; i++) {
      final a = i * 2 * pi / rays;
      final b = a + pi / rays;
      canvas.drawPath(
        Path()
          ..moveTo(center.dx, center.dy)
          ..lineTo(center.dx + cos(a) * radius, center.dy + sin(a) * radius)
          ..lineTo(center.dx + cos(b) * radius, center.dy + sin(b) * radius)
          ..close(),
        paint,
      );
    }
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.16),
          radius: 0.7,
          colors: [Colors.white.withAlpha(150), Colors.white.withAlpha(0)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_SunburstPainter old) => old.colors != colors;
}

/// A spiky comic "POW" burst, outlined in ink.
class _StarburstPainter extends CustomPainter {
  const _StarburstPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final outer = size.shortestSide / 2;
    const spikes = 14;
    final path = Path();
    for (var i = 0; i < spikes * 2; i++) {
      final r = i.isEven ? outer : outer * 0.78;
      final a = -pi / 2 + i * pi / spikes + 0.1;
      // Wider than tall, so long numbers fit.
      final p = c + Offset(cos(a) * r * 1.35, sin(a) * r);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(
      path.shift(const Offset(0, 4)),
      Paint()..color = _ink.withAlpha(70),
    );
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeJoin = StrokeJoin.round
        ..color = _ink,
    );
  }

  @override
  bool shouldRepaint(_StarburstPainter old) => old.color != color;
}

/// Colourful confetti scattered down both sides, clear of the middle.
class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter();

  static const _colors = [
    Color(0xFFE76F51),
    Color(0xFF2A9D8F),
    Color(0xFFE9C46A),
    Color(0xFF9B5DE5),
    Color(0xFFF15BB5),
    Color(0xFF00BBF9),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(11);
    for (var i = 0; i < 34; i++) {
      final left = rng.nextBool();
      final x = left
          ? rng.nextDouble() * size.width * 0.24
          : size.width * (0.76 + rng.nextDouble() * 0.24);
      final y = rng.nextDouble() * size.height;
      final paint = Paint()..color = _colors[i % _colors.length];
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rng.nextDouble() * pi);
      if (i % 3 == 0) {
        canvas.drawCircle(Offset.zero, 3.5, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: 11, height: 5),
            const Radius.circular(2),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}

// ---------- Leaderboard poster ----------

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "Oct 12 – Oct 18": the leaderboard week [now] is in (Monday to Sunday,
/// UTC).
String weekRangeLabel(DateTime now) {
  final start = LeaderboardWeek.endsAt(now).subtract(const Duration(days: 7));
  final end = start.add(const Duration(days: 6));
  String day(DateTime d) => '${_months[d.month - 1]} ${d.day}';
  return '${day(start)} – ${day(end)}';
}

/// A poster of the player's place on a leaderboard: their cat on a podium
/// (or a pedestal with their rank, below the top three), their best, and
/// their name. Purple for this week's board, red and gold for the all-time
/// Hall of Fame.
class RankPoster extends StatelessWidget {
  const RankPoster({
    super.key,
    required this.board,
    required this.rank,
    required this.best,
    required this.name,
    required this.pool,
    required this.now,
  });

  final Board board;
  final int rank;

  /// The player's best on [board].
  final int best;

  /// The player's first name (null for guests).
  final String? name;
  final List<CatBreed> pool;

  /// For the week's dates.
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final weekly = board == Board.weekly;
    final rays = weekly
        ? const [Color(0xFF7C5CE8), Color(0xFF6A49D6)]
        : const [Color(0xFFD94A4A), Color(0xFFBF3535)];
    final ribbon = weekly ? const Color(0xFF2EC4B6) : const Color(0xFFF2A516);
    final cats = best == 1 ? 'CAT' : 'CATS';
    return SizedBox.fromSize(
      size: ShareCard.size,
      child: Material(
        type: MaterialType.transparency,
        child: ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _SunburstPainter(rays)),
              ),
              const Positioned.fill(
                child: CustomPaint(painter: _ConfettiPainter()),
              ),
              Positioned(
                top: 10,
                left: 0,
                right: 0,
                child: Column(
                  children: [
                    const _Lockup(iconSize: 30, textSize: 19),
                    Transform.rotate(
                      angle: -0.03,
                      child: _InkText(
                        weekly ? 'LEADERBOARD' : 'HALL OF FAME',
                        size: 38,
                        fill: Colors.white,
                        stroke: 7,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _ink,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        weekly
                            ? 'THIS WEEK · ${weekRangeLabel(now)}'
                            : 'ALL-TIME',
                        style: const TextStyle(
                          fontFamily: _font,
                          fontSize: 13,
                          letterSpacing: 0.5,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 118,
                height: 192,
                child: CustomPaint(
                  painter: _PodiumPainter(rank: rank, pool: pool),
                ),
              ),
              // On the other side from the cat (#2 stands on the left).
              Positioned(
                left: rank == 2 ? null : 14,
                right: rank == 2 ? 14 : null,
                top: 132,
                child: _SpeechBubble(switch (rank) {
                  1 => 'Bow down!',
                  2 => 'So close to #1!',
                  3 => 'Podium cat!',
                  _ => 'Catch me if you can!',
                }, tailLeft: rank == 2),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 318,
                child: Center(
                  child: _Ribbon(color: ribbon, text: 'BEST: $best $cats'),
                ),
              ),
              if (name case final name?)
                Positioned(
                  left: 20,
                  right: 20,
                  top: 361,
                  child: _InkText(
                    name,
                    size: 19,
                    fill: Colors.white,
                    stroke: 4,
                  ),
                ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: Center(child: _CallToAction(text: 'CAN YOU BEAT ME?')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The top three on a podium (gold in the middle, silver left, bronze
/// right) with the player's cat on their step, and a crown at #1. Below the
/// top three, a single pedestal with their rank.
class _PodiumPainter extends CustomPainter {
  const _PodiumPainter({required this.rank, required this.pool});

  final int rank;
  final List<CatBreed> pool;

  static const _gold = Color(0xFFF6C531);
  static const _silver = Color(0xFFCBD3DC);
  static const _bronze = Color(0xFFD48C52);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final floor = size.height - 4;
    // Narrower than a step, so the cat stays on its own.
    final catW = rank <= 3 ? 68.0 : 80.0;
    final catH = catW * 0.58;
    final look = CatLook.random(Random(rank), pool);

    if (rank <= 3) {
      const w = 88.0;
      final steps = {
        2: (
          Rect.fromLTRB(cx - w * 1.5, floor - 64, cx - w / 2, floor),
          _silver,
        ),
        1: (Rect.fromLTRB(cx - w / 2, floor - 94, cx + w / 2, floor), _gold),
        3: (
          Rect.fromLTRB(cx + w / 2, floor - 46, cx + w * 1.5, floor),
          _bronze,
        ),
      };
      for (final MapEntry(key: place, value: (rect, color)) in steps.entries) {
        _step(canvas, rect, color, '$place', mine: place == rank);
      }
      final top = steps[rank]!.$1;
      final catAt = Offset(top.center.dx, top.top - catH / 2 + 2);
      paintCat(canvas, look, catAt, catW, catH);
      if (rank == 1) _crown(canvas, catAt - Offset(0, catH / 2 + 14));
    } else {
      final rect = Rect.fromLTRB(cx - 64, floor - 92, cx + 64, floor);
      _step(canvas, rect, Colors.white, '#$rank', mine: true);
      paintCat(canvas, look, Offset(cx, rect.top - catH / 2 + 2), catW, catH);
    }
  }

  /// A podium block, outlined, with its number on the front. The player's
  /// own step is full colour, the others a little faded.
  void _step(
    Canvas canvas,
    Rect rect,
    Color color,
    String label, {
    required bool mine,
  }) {
    final block = RRect.fromRectAndCorners(
      rect,
      topLeft: const Radius.circular(8),
      topRight: const Radius.circular(8),
    );
    canvas.drawRRect(
      block.shift(const Offset(0, 4)),
      Paint()..color = _ink.withAlpha(70),
    );
    canvas.drawRRect(
      block,
      Paint()..color = mine ? color : Color.lerp(color, Colors.white, 0.45)!,
    );
    // A lighter band along the top edge.
    canvas.drawRect(
      Rect.fromLTWH(rect.left + 6, rect.top + 6, rect.width - 12, 6),
      Paint()..color = Colors.white.withAlpha(110),
    );
    canvas.drawRRect(
      block,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeJoin = StrokeJoin.round
        ..color = _ink,
    );
    final fontSize = label.length > 2 ? 34.0 : 40.0;
    _inkLabel(
      canvas,
      label,
      Offset(rect.center.dx, rect.top + min(rect.height / 2, 34) + 4),
      fontSize,
    );
  }

  void _inkLabel(Canvas canvas, String text, Offset center, double size) {
    for (final stroke in [true, false]) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: _font,
            fontSize: size,
            color: stroke ? null : Colors.white,
            foreground: stroke
                ? (Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 6
                    ..strokeJoin = StrokeJoin.round
                    ..color = _ink)
                : null,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        center - Offset(painter.width / 2, painter.height / 2),
      );
      painter.dispose();
    }
  }

  /// A little gold crown, outlined.
  void _crown(Canvas canvas, Offset at) {
    final path = Path()
      ..moveTo(at.dx - 20, at.dy + 10)
      ..lineTo(at.dx - 23, at.dy - 10)
      ..lineTo(at.dx - 10, at.dy)
      ..lineTo(at.dx, at.dy - 16)
      ..lineTo(at.dx + 10, at.dy)
      ..lineTo(at.dx + 23, at.dy - 10)
      ..lineTo(at.dx + 20, at.dy + 10)
      ..close();
    canvas.drawPath(path, Paint()..color = _gold);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..color = _ink,
    );
    for (final x in [-23.0, 0.0, 23.0]) {
      final tip = Offset(at.dx + x, at.dy + (x == 0 ? -17 : -11));
      canvas.drawCircle(tip, 3.5, Paint()..color = const Color(0xFFE76F51));
      canvas.drawCircle(
        tip,
        3.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _ink,
      );
    }
  }

  @override
  bool shouldRepaint(_PodiumPainter old) =>
      old.rank != rank || old.pool != pool;
}

// ---------- Branding ----------

/// The app icon (three stacked cats on coral).
const appIconImage = AssetImage('assets/branding/app_icon.png');

/// The app icon as a sticker: rounded, with a white border and an ink
/// outline.
class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.size, this.angle = 0});
  final double size;
  final double angle;

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.24;
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          color: _ink,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: const [
            BoxShadow(color: Color(0x553B2416), offset: Offset(0, 3)),
          ],
        ),
        child: Container(
          padding: EdgeInsets.all(size * 0.05),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(radius - 2.5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius * 0.7),
            child: const Image(image: appIconImage, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }
}

/// The logo: the app icon and STACK THE CATS side by side.
class _Lockup extends StatelessWidget {
  const _Lockup({required this.iconSize, required this.textSize});
  final double iconSize;
  final double textSize;

  @override
  Widget build(BuildContext context) {
    // Shrinks rather than overflowing if the letters come out wider.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AppIcon(size: iconSize, angle: -0.08),
          SizedBox(width: textSize * 0.3),
          _InkText(
            'STACK THE CATS',
            size: textSize,
            fill: Colors.white,
            stroke: textSize * 0.2,
            letterSpacing: 1,
          ),
        ],
      ),
    );
  }
}
