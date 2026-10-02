import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/text.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../audio/audio_manager.dart';
import '../data/game_over_lines.dart';
import '../economy/treats.dart';
import '../store/catalog.dart';
import '../store/wallpapers.dart';
import 'cat.dart';

/// What the game is doing right now.
enum Phase { waiting, swinging, falling, over }

/// Little floating text like "Purrfect!".
class Popup {
  Popup(this.text, this.x, this.y);
  final String text;
  double x, y;
  double life = 1.0;
}

/// What a run allows, decided when it starts.
class RunRules {
  const RunRules({
    required this.earnsTreats,
    required this.maxScore,
    this.allowRevive = true,
    this.allowRealign = true,
    this.catSeed,
    this.isGuest = false,
    this.isSelfChallenge = false,
  });

  /// Signed in and online: treats and no limit.
  static const full = RunRules(earnsTreats: true, maxScore: null);

  /// Guests and offline players stop at 50 cats.
  static const guest = RunRules(
    earnsTreats: false,
    maxScore: 50,
    isGuest: true,
  );

  /// The Self Challenge: reach 100 cats with one tower, at fixed speeds.
  /// Pays Tuna and Salmon at the end instead of treats along the way.
  static const selfChallenge = RunRules(
    earnsTreats: false,
    maxScore: SelfChallenge.goal,
    allowRevive: false,
    allowRealign: false,
    isSelfChallenge: true,
  );

  /// Signed out or offline: capped, and no best score shown or saved.
  final bool isGuest;
  final bool isSelfChallenge;

  /// A live challenge: both players get the same cats (from [seed]), one
  /// life each, no treats until the result.
  const RunRules.challenge(int seed)
    : earnsTreats = false,
      maxScore = null,
      allowRevive = false,
      allowRealign = false,
      catSeed = seed,
      isGuest = false,
      isSelfChallenge = false;

  final bool earnsTreats;

  /// The run ends with a congratulations card at this score. Null = no limit.
  final int? maxScore;

  final bool allowRevive;
  final bool allowRealign;

  /// When set, the cats (look and starting side) come from this seed, so
  /// two players with the same seed get exactly the same cats in order.
  final int? catSeed;

  bool get isChallenge => catSeed != null;
}

/// How close a tower is to toppling, and which way it would go.
class TowerBalance {
  const TowerBalance({required this.stability, required this.tilt});

  static const level = TowerBalance(stability: 1, tilt: 0);

  /// 1 = perfectly balanced, 0 = about to topple.
  final double stability;

  /// How far the worst level leans, from -1 (about to fall left) to 1
  /// (about to fall right).
  final double tilt;

  /// -1 if it would tumble left, 1 right, 0 if it's (nearly) straight.
  int get side => tilt.abs() < 0.08 ? 0 : tilt.sign.toInt();

  int get percent => (stability * 100).round().clamp(0, 100);

  /// Uses the same rule as the game: for every cat, the combined centre of
  /// all the cats above it (itself included) must sit over the one below
  /// (or over the cushion, for the bottom cat). The level nearest to
  /// failing decides. [xs] are the cats' centres, bottom first.
  static TowerBalance of(
    List<double> xs, {
    required double baseX,
    required double baseHalf,
    required double catHalf,
  }) {
    if (xs.isEmpty) return level;
    double sum = 0;
    int count = 0;
    double worst = 0;
    for (int i = xs.length - 1; i >= 0; i--) {
      sum += xs[i];
      count++;
      final centre = sum / count;
      final support = i == 0 ? baseX : xs[i - 1];
      final half = i == 0 ? baseHalf : catHalf;
      final lean = (centre - support) / half;
      if (lean.abs() > worst.abs()) worst = lean;
    }
    final tilt = worst.clamp(-1.0, 1.0);
    return TowerBalance(stability: 1 - tilt.abs(), tilt: tilt);
  }
}

class StackGame extends FlameGame {
  StackGame({
    this.onExitToMenu,
    required this.rulesForNewRun,
    this.onLanded,
    this.earnAllowance,
    this.onEarnLimitReached,
    this.onRunEnded,
    this.onCelebrate,
    this.catPool,
    this.wallpaper,
  }) : rules = rulesForNewRun();

  /// The cats this player owns (basic + bought). Asked for every new cat,
  /// so a cat bought mid-run starts dropping straight away. Challenges
  /// always use the basic cats, so both players see the same ones.
  final List<CatBreed> Function()? catPool;

  /// The wallpaper in use. Asked every frame, so a new one shows at once.
  final Wallpaper Function()? wallpaper;

  Wallpaper get _wallpaper => wallpaper?.call() ?? Wallpapers.classic;

  /// Called with the score whenever a run ends: on game over, on reaching
  /// the limit, or when the player restarts or leaves mid-run.
  final void Function(int score)? onRunEnded;

  /// Called when the player taps "Menu" on the game over card.
  final VoidCallback? onExitToMenu;

  /// Asked at the start of every run, so signing in (or losing the
  /// connection) takes effect on the next run.
  final RunRules Function() rulesForNewRun;

  /// The rules for the current run.
  RunRules rules;

  bool get earnsTreats => rules.earnsTreats;

  /// True when this run ended by reaching [RunRules.maxScore].
  bool reachedLimit = false;

  static const String limitOverlay = 'limitReached';

  /// In challenges: the card showing the match result (replaces the game
  /// over card).
  static const String challengeOverlay = 'challenge';

  /// Called with the new score after every landing (live challenges).
  void Function(int score)? onScore;

  /// Called whenever the tower falls, whatever the score (live challenges).
  void Function(int score)? onTowerFell;

  /// While true, no cat is dropped in: a challenge waits for its countdown.
  bool holdStart = false;

  /// Ends a challenge run right away (the match was decided), keeping the
  /// tower on screen and showing the challenge card.
  void haltForResult() {
    if (phase == Phase.over && _overlayShown) return;
    active = null;
    phase = Phase.over;
    overTimer = 0;
    _overlayShown = true;
    audio.pauseMusic();
    audio.stopAllSfx();
    overlays.add(challengeOverlay);
  }

  /// Called for every cat that lands without toppling the tower, with the
  /// perfect streak after it, its tier, when it landed (ms of play), and
  /// the treats and fish it earned (the server checks and pays them).
  final void Function({
    required int combo,
    required CatTier tier,
    required int atMs,
    required int treats,
    Fish? fish,
  })?
  onLanded;

  /// What games may still pay today (the daily limit). Null = no limit.
  final ({int treats, int tuna, int salmon}) Function()? earnAllowance;

  /// Called when a landing would have paid but today's limit is reached.
  final VoidCallback? onEarnLimitReached;

  /// Called for big moments that deserve treat confetti: the 50-treat
  /// bonus every 50 cats, or a guest finishing their 50 cats.
  final VoidCallback? onCelebrate;

  /// Perfect landings needed for each chime. Chime 1 at 5 perfects,
  /// chime 2 at 15 (5 + 10), chime 3 at 30 (15 + 15), then chime 4
  /// on every perfect after that until game over.
  static const List<int> chimeMilestones = [5, 15, 30];

  static const String gameOverOverlay = 'gameOver';
  static const Color wallColor = Color(0xFFFDEBD3);
  static const double gravity = 2400;

  /// For looks only (how cats tumble, game over lines).
  final Random _rng = Random();

  /// Picks each new cat. Seeded in challenges so both players get the same
  /// cats in the same order.
  late Random _catRng = _newCatRng();
  Random _newCatRng() {
    final seed = rules.catSeed;
    return seed == null ? Random() : Random(seed);
  }

  /// Cats that have landed, from bottom (index 0) to top.
  final List<Cat> tower = [];

  /// Cats that are falling off after a miss or collapse.
  final List<Cat> tumbling = [];

  final List<Popup> popups = [];

  /// The cat currently swinging or dropping. Uses SCREEN coordinates.
  /// (Tower and tumbling cats use TOWER coordinates: screenY = y + scroll.)
  Cat? active;

  Phase phase = Phase.waiting;
  int score = 0;
  int best = 0;
  int combo = 0;
  int perfectCount = 0; // total perfect landings this run
  bool newBest = false;
  String gameOverLine = '';

  /// Treats earned this run.
  int runTreats = 0;

  /// Tuna and Salmon earned this run.
  int runTuna = 0;
  int runSalmon = 0;

  /// Revives and realigns used this run, per way of paying (each has its
  /// own limit, see [PayWith]).
  final revives = UseCounter();
  final realigns = UseCounter();

  /// The tower as it was before the cat that toppled it, for Revive.
  List<Cat> _beforeCollapse = const [];

  /// Realign animation: where each cat started, and progress 0-1.
  List<double>? _realignFrom;
  double _realignT = 0;
  static const double _realignDuration = 0.45;

  /// Whether Realign can be used right now. The HUD listens to this.
  final ValueNotifier<bool> canRealign = ValueNotifier(false);

  /// Whether the game over card is up. The HUD hides its buttons then.
  final ValueNotifier<bool> isOver = ValueNotifier(false);

  double scroll = 0; // how far the view has moved up
  double scrollTarget = 0;
  double time = 0;
  double waitTimer = 0.4;
  double overTimer = 0;
  double dir = 1; // swing direction: 1 = right, -1 = left
  bool _overlayShown = false;

  SharedPreferences? _prefs;

  // ---------- Layout (based on screen size) ----------
  double get catW => min(size.x * 0.3, 150.0);
  double get catH => catW * 0.58;
  double get groundY => size.y - 110; // top of the cushion, in tower coords
  double get baseX => size.x / 2;
  double get baseW => catW * 1.4;
  double get hangY => 120 + catH; // where new cats swing (screen coords)

  /// Cats swing faster in steps: the speed holds for every
  /// [swingStepCats] cats, then goes up, reaching [maxSwingSpeed] at
  /// [maxSpeedAtCats] cats, in equal steps (200, 224, 248 ... 776, then 800
  /// from 500 cats).
  static double swingSpeedFor(int score) {
    const steps = maxSpeedAtCats ~/ swingStepCats;
    final step = min(score ~/ swingStepCats, steps);
    return minSwingSpeed + (maxSwingSpeed - minSwingSpeed) * step / steps;
  }

  static const double minSwingSpeed = 200;
  static const double maxSwingSpeed = 800;
  static const int swingStepCats = 20;
  static const int maxSpeedAtCats = 500;

  double get swingSpeed => rules.isSelfChallenge
      ? SelfChallenge.swingSpeedFor(score)
      : swingSpeedFor(score);

  // ---------- Text styles ----------
  final _scorePaint = TextPaint(
    style: const TextStyle(
      fontSize: 48,
      fontWeight: FontWeight.w900,
      color: Color(0xFF5B3A29),
    ),
  );
  final _smallPaint = TextPaint(
    style: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: Color(0xFF8A6A55),
    ),
  );

  /// "Speed increased!" shows for this long under the score, then fades.
  static const double _speedMessageTime = 1.4;
  double _speedMessageLeft = 0;

  final _hintPaint = TextPaint(
    style: const TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: Color(0xFF8A6A55),
    ),
  );

  @override
  Color backgroundColor() => _wallpaper.background;

  @override
  Future<void> onLoad() async {
    add(TapArea(_handleTap));
    try {
      _prefs = await SharedPreferences.getInstance();
      best = _prefs?.getInt('best') ?? 0;
    } catch (_) {
      // If saving isn't available, the game still works.
    }
  }

  // ---------- Input ----------
  AudioManager get audio => AudioManager.instance;

  void _handleTap() {
    if (phase != Phase.over) audio.playSfx(Sfx.tap);
    if (phase == Phase.swinging && active != null && _realignFrom == null) {
      phase = Phase.falling;
      active!.vy = 0;
    }
  }

  // ---------- Game flow ----------
  void _spawnCat() {
    dir = _catRng.nextBool() ? 1 : -1;
    final startX = dir > 0 ? catW / 2 + 12 : size.x - catW / 2 - 12;
    final pool = rules.isChallenge
        ? Cats.basic
        : (catPool?.call() ?? Cats.basic);
    active = Cat(x: startX, y: hangY, look: CatLook.random(_catRng, pool));
    phase = Phase.swinging;
  }

  void restart() {
    // A run abandoned with Restart still counts towards the best score.
    // (After game over it was already reported.)
    if (phase != Phase.over) _reportRunEnded();
    audio.stopAllSfx(); // e.g. the game over sound
    overlays.remove(gameOverOverlay);
    overlays.remove(limitOverlay);
    _overlayShown = false;
    rules = rulesForNewRun();
    _catRng = _newCatRng();
    reachedLimit = false;
    tower.clear();
    tumbling.clear();
    popups.clear();
    active = null;
    score = 0;
    combo = 0;
    perfectCount = 0;
    newBest = false;
    runTreats = 0;
    runTuna = 0;
    runSalmon = 0;
    revives.reset();
    realigns.reset();
    _beforeCollapse = const [];
    _realignFrom = null;
    _speedMessageLeft = 0;
    scroll = 0;
    scrollTarget = 0;
    phase = Phase.waiting;
    waitTimer = 0.3;
    audio.resumeMusic();
  }

  /// Whether this is a guest run (signed out or offline): capped, and no
  /// best score shown or saved.
  bool get isGuestRun => rules.isGuest;

  /// Cats left before a guest run (or a Self Challenge) reaches its limit.
  int get catsToGo => max(0, (rules.maxScore ?? 0) - score);

  /// Saves the score as the best if it beats it. Safe to call repeatedly.
  void _saveBest() {
    // Only normal games count towards the saved best.
    if (isGuestRun || rules.isChallenge || rules.isSelfChallenge) return;
    if (score > best) {
      best = score;
      newBest = true;
      _prefs?.setInt('best', best);
    }
  }

  void _reportRunEnded() {
    _saveBest();
    if (score > 0) onRunEnded?.call(score);
  }

  /// Ends the run without the game over card, e.g. when leaving for the
  /// menu mid-run.
  void quitRun() {
    if (phase != Phase.over) _reportRunEnded();
  }

  bool get canRevive =>
      rules.allowRevive && phase == Phase.over && revives.anyLeft;

  /// Second chance: after a miss the tower stays; after a collapse the
  /// tower comes back without the cat that toppled it. [paidWith] counts
  /// towards that way of paying's limit.
  void revive(PayWith paidWith) {
    if (!canRevive || !revives.canUse(paidWith)) return;
    revives.use(paidWith);
    audio.stopAllSfx();
    overlays.remove(gameOverOverlay);
    _overlayShown = false;
    if (_beforeCollapse.isNotEmpty) {
      tumbling.clear();
      tower
        ..clear()
        ..addAll(_beforeCollapse);
      for (int i = 0; i < tower.length; i++) {
        tower[i]
          ..y = groundY - i * catH - catH / 2
          ..vx = 0
          ..vy = 0
          ..angle = 0
          ..spin = 0
          ..squash = 0;
      }
      _beforeCollapse = const [];
    }
    final stackTop = groundY - tower.length * catH;
    scrollTarget = max(0.0, size.y * 0.52 - stackTop);
    _popup('Second chance!', size.x / 2, hangY + 60 - scroll);
    phase = Phase.waiting;
    waitTimer = 0.6;
    audio.resumeMusic();
  }

  /// Slides every cat in the tower into a straight column.
  void realign(PayWith paidWith) {
    if (!canRealign.value || !realigns.canUse(paidWith)) return;
    realigns.use(paidWith);
    _realignFrom = [for (final c in tower) c.x];
    _realignT = 0;
    _popup('Realigned!', baseX, groundY - tower.length * catH - catH);
  }

  void _updateRealign(double step) {
    final from = _realignFrom;
    if (from == null) return;
    _realignT = min(1.0, _realignT + step / _realignDuration);
    final t = Curves.easeOutBack.transform(_realignT);
    for (int i = 0; i < tower.length && i < from.length; i++) {
      tower[i].x = from[i] + (baseX - from[i]) * t;
    }
    if (_realignT >= 1) {
      for (final c in tower) {
        c.x = baseX;
      }
      _realignFrom = null;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    final step = min(dt, 1 / 30); // avoid big jumps if the phone lags
    time += step;
    scroll += (scrollTarget - scroll) * min(1.0, step * 5);

    final cat = active;
    switch (phase) {
      case Phase.waiting:
        if (!holdStart) {
          waitTimer -= step;
          if (waitTimer <= 0) _spawnCat();
        }
      case Phase.swinging:
        if (cat != null) {
          cat.x += dir * swingSpeed * step;
          final minX = catW / 2 + 12;
          final maxX = size.x - catW / 2 - 12;
          if (cat.x < minX) {
            cat.x = minX;
            dir = 1;
          } else if (cat.x > maxX) {
            cat.x = maxX;
            dir = -1;
          }
        }
      case Phase.falling:
        if (cat != null) {
          cat.vy += gravity * step;
          cat.y += cat.vy * step;
          _checkLanding(cat);
        }
      case Phase.over:
        overTimer -= step;
        if (overTimer <= 0 && !_overlayShown) {
          _overlayShown = true;
          audio.pauseMusic();
          // Nothing from the last landing plays over the card.
          audio.stopAllSfx();
          if (reachedLimit) {
            audio.playSfx(Sfx.chimes.last); // a happy ending, not a fall
            onCelebrate?.call(); // confetti and applause with the card
            overlays.add(limitOverlay);
          } else {
            audio.playSfx(Sfx.gameOver);
            // Challenges show the match card (waiting for, or the result).
            overlays.add(
              rules.isChallenge ? challengeOverlay : gameOverOverlay,
            );
          }
        }
    }

    _updateRealign(step);
    isOver.value = phase == Phase.over;
    // Realign needs at least two cats and nothing mid-air.
    canRealign.value =
        rules.allowRealign &&
        realigns.anyLeft &&
        tower.length >= 2 &&
        _realignFrom == null &&
        (phase == Phase.waiting || phase == Phase.swinging);

    for (final c in tumbling) {
      c.vy += gravity * step;
      c.x += c.vx * step;
      c.y += c.vy * step;
      c.angle += c.spin * step;
    }
    tumbling.removeWhere((c) => c.y + scroll > size.y + 300);

    for (final c in tower) {
      c.squash = max(0.0, c.squash - step * 4);
    }

    for (final p in popups) {
      p.y -= 45 * step;
      p.life -= step;
    }
    popups.removeWhere((p) => p.life <= 0);
    _speedMessageLeft = max(0.0, _speedMessageLeft - step);

    balance = TowerBalance.of(
      [for (final c in tower) c.x],
      baseX: baseX,
      baseHalf: baseW / 2,
      catHalf: catW / 2,
    );
    // The needle glides rather than jumps.
    _shownTilt += (balance.tilt - _shownTilt) * min(1.0, step * 8);
  }

  void _checkLanding(Cat cat) {
    final topSurface = groundY - tower.length * catH; // tower coords
    final topSurfaceOnScreen = topSurface + scroll;
    if (cat.y + catH / 2 < topSurfaceOnScreen) return; // still in the air

    final supportX = tower.isEmpty ? baseX : tower.last.x;
    final supportHalf = tower.isEmpty ? baseW / 2 : catW / 2;
    final offset = cat.x - supportX;

    // Missed completely: the cat slides off the edge.
    if (offset.abs() > supportHalf) {
      cat.y -= scroll; // switch to tower coords
      final side = offset.sign;
      cat.vx = side * 220;
      cat.vy = -250;
      cat.spin = side * 6;
      tumbling.add(cat);
      active = null;
      audio.playSfx(Sfx.miss);
      _endGame(missed: true);
      return;
    }

    // Landed!
    cat.y = topSurface - catH / 2;
    cat.vy = 0;
    cat.squash = 1;
    active = null;

    final perfect = offset.abs() < catW * 0.06;
    if (perfect) {
      cat.x = supportX; // snap it perfectly into place
      combo++;
      perfectCount++;
      _popup(
        combo >= 2 ? 'Purrfect! x$combo' : 'Purrfect!',
        cat.x,
        cat.y - catH,
      );
    } else {
      combo = 0;
    }

    tower.add(cat);

    if (perfect) {
      audio.playPerfectLanding();
      _playChimeIfEarned();
    } else {
      audio.playLanding();
    }

    if (!_isStable()) {
      _collapse();
      return;
    }

    score++;
    onScore?.call(score);
    if (swingSpeedFor(score) > swingSpeedFor(score - 1)) {
      _speedMessageLeft = _speedMessageTime;
    }
    var earned = 0;
    Fish? fish;
    if (earnsTreats) {
      // Store cats add a bonus to their own Purrfect landings.
      earned = Treats.forLanding(
        combo: combo,
        score: score,
        tier: cat.look.breed.tier,
      );
      // Every 100 cats a Tuna, every 200 a Salmon (instead of treats).
      fish = Fish.forMilestone(score);
      // Within today's limit.
      final allowance = earnAllowance?.call();
      if (allowance != null) {
        final wanted = earned > 0 || fish != null;
        earned = min(earned, max(0, allowance.treats));
        if (fish == Fish.tuna && allowance.tuna <= 0) fish = null;
        if (fish == Fish.salmon && allowance.salmon <= 0) fish = null;
        if (wanted && earned == 0 && fish == null) onEarnLimitReached?.call();
      }
      if (earned > 0) {
        runTreats += earned;
        _popup('+$earned treats', cat.x, cat.y - catH * 1.7);
      }
      if (fish != null) {
        fish == Fish.tuna ? runTuna++ : runSalmon++;
        _popup('+1 ${fish.label}!', cat.x, cat.y - catH * 1.7);
      }
      if (score % Treats.stackMilestone == 0) onCelebrate?.call();
    }
    onLanded?.call(
      combo: combo,
      tier: cat.look.breed.tier,
      atMs: (time * 1000).round(),
      treats: earned,
      fish: fish,
    );
    final stackTop = groundY - tower.length * catH;
    scrollTarget = max(0.0, size.y * 0.52 - stackTop);

    final limit = rules.maxScore;
    if (limit != null && score >= limit) {
      _reachLimit();
      return;
    }
    phase = Phase.waiting;
    waitTimer = 0.35;
  }

  /// Guest and offline runs end here with a congratulations card.
  void _reachLimit() {
    reachedLimit = true;
    phase = Phase.over;
    overTimer = 0.9; // a moment to admire the tower first
    combo = 0;
    _popup('$score cats!', baseX, groundY - tower.length * catH - catH);
    _reportRunEnded();
  }

  /// Real stacking physics: for every cat, the combined center of all the
  /// cats above it (including itself) must sit over the cat underneath.
  bool _isStable() {
    double sum = 0;
    int count = 0;
    for (int i = tower.length - 1; i >= 0; i--) {
      sum += tower[i].x;
      count++;
      final centerOfMass = sum / count;
      final supportX = i == 0 ? baseX : tower[i - 1].x;
      final half = i == 0 ? baseW / 2 : catW / 2;
      if ((centerOfMass - supportX).abs() > half) return false;
    }
    return true;
  }

  /// The tower's balance right now, for the stability meter.
  TowerBalance balance = TowerBalance.level;
  double _shownTilt = 0;

  double _towerCenter() {
    if (tower.isEmpty) return baseX;
    return tower.map((c) => c.x).reduce((a, b) => a + b) / tower.length;
  }

  void _collapse() {
    // Copies, because the falling cats move and spin.
    _beforeCollapse = [
      for (final c in tower.take(tower.length - 1))
        Cat(x: c.x, y: c.y, look: c.look),
    ];
    var lean = (_towerCenter() - baseX).sign;
    if (lean == 0) lean = 1;
    for (int i = 0; i < tower.length; i++) {
      final c = tower[i];
      c.vx = lean * (60 + i * 45 + _rng.nextDouble() * 80);
      c.vy = -120 - _rng.nextDouble() * 260;
      c.spin = lean * (2 + _rng.nextDouble() * 5);
      tumbling.add(c);
    }
    tower.clear();
    audio.playSfx(Sfx.collapse);
    _endGame(missed: false);
  }

  void _playChimeIfEarned() {
    final index = chimeMilestones.indexOf(perfectCount);
    if (index >= 0) {
      audio.playChime(index); // chime 1, 2 or 3
    } else if (perfectCount > chimeMilestones.last) {
      audio.playChime(3); // chime 4 every time after the last milestone
    }
  }

  void _endGame({required bool missed}) {
    phase = Phase.over;
    overTimer = 1.3; // let the cats fall before showing the menu
    combo = 0;
    final lines = missed ? missLines : toppleLines;
    gameOverLine = lines[_rng.nextInt(lines.length)];
    _reportRunEnded();
    onTowerFell?.call(score);
  }

  void _popup(String text, double x, double y) {
    popups.add(Popup(text, x, y));
  }

  // ---------- Drawing ----------
  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Wallpaper (moves gently with the tower so it feels like a wall).
    paintWallpaper(
      canvas,
      Size(size.x, size.y),
      _wallpaper,
      scroll: scroll * 0.5,
    );

    // Floor and cushion (these move with the scroll)
    final floorTop = groundY + scroll;
    canvas.drawRect(
      Rect.fromLTWH(0, floorTop + 26, size.x, size.y),
      Paint()..color = const Color(0xFFC9A27E),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(baseX - baseW / 2, floorTop, baseW, 32),
        const Radius.circular(14),
      ),
      Paint()..color = const Color(0xFFE76F51),
    );

    // The tower sways more the more off-balance it is.
    final lean = (_towerCenter() - baseX).abs() / catW;
    final sway = sin(time * 2.4) * min(5.0, lean * 8);
    for (int i = 0; i < tower.length; i++) {
      final c = tower[i];
      final t = tower.length <= 1 ? 0.0 : i / (tower.length - 1);
      paintCat(
        canvas,
        c.look,
        Offset(c.x + sway * t, c.y + scroll),
        catW,
        catH,
        squash: c.squash,
      );
    }

    for (final c in tumbling) {
      paintCat(
        canvas,
        c.look,
        Offset(c.x, c.y + scroll),
        catW,
        catH,
        angle: c.angle,
      );
    }

    final a = active;
    if (a != null) {
      if (phase == Phase.swinging) {
        // A little string the cat dangles from
        canvas.drawLine(
          Offset(a.x, 0),
          Offset(a.x, a.y - catH / 2),
          Paint()
            ..color = const Color(0x668A6A55)
            ..strokeWidth = 2,
        );
      }
      paintCat(canvas, a.look, Offset(a.x, a.y), catW, catH);
    }

    for (final p in popups) {
      final alpha = (p.life.clamp(0.0, 1.0) * 255).round();
      TextPaint(
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: const Color(0xFFE76F51).withAlpha(alpha),
        ),
      ).render(
        canvas,
        p.text,
        Vector2(p.x, p.y + scroll),
        anchor: Anchor.center,
      );
    }

    // Score display
    _scorePaint.render(
      canvas,
      '$score',
      Vector2(size.x / 2, 30),
      anchor: Anchor.topCenter,
    );
    // Guests (and the Self Challenge) see how many cats are left instead
    // of their best.
    _smallPaint.render(
      canvas,
      rules.maxScore != null
          ? '$catsToGo ${catsToGo == 1 ? 'cat' : 'cats'} to go'
          : 'Best $best',
      Vector2(size.x / 2, 88),
      anchor: Anchor.topCenter,
    );

    // "Speed increased!" pops in under the score, drifts up a little and
    // fades out.
    if (_speedMessageLeft > 0) {
      final age = _speedMessageTime - _speedMessageLeft;
      final fadeIn = (age / 0.15).clamp(0.0, 1.0);
      final fadeOut = (_speedMessageLeft / 0.5).clamp(0.0, 1.0);
      final alpha = (min(fadeIn, fadeOut) * 255).round();
      TextPaint(
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: const Color(0xFFE76F51).withAlpha(alpha),
        ),
      ).render(
        canvas,
        'Speed increased!',
        Vector2(size.x / 2, 114 - age * 8),
        anchor: Anchor.topCenter,
      );
    }

    if (score == 0 && tower.isEmpty && phase == Phase.swinging) {
      _hintPaint.render(
        canvas,
        'Tap to drop the cat!',
        Vector2(size.x / 2, size.y * 0.5),
        anchor: Anchor.center,
      );
    }

    if (tower.length >= 2 && phase != Phase.over) _renderStabilityMeter(canvas);
  }

  /// "Stability 72%" at the bottom of the screen, with a needle that leans
  /// the way the tower would tumble, and a tip once it gets wobbly.
  void _renderStabilityMeter(Canvas canvas) {
    final b = balance;
    final color = b.percent >= 70
        ? const Color(0xFF3E9B5B)
        : b.percent >= 40
        ? const Color(0xFFE09B2D)
        : const Color(0xFFD64933);
    final wobbly = b.percent < 50 && b.side != 0;
    const width = 260.0;
    final height = wobbly ? 72.0 : 54.0;
    final rect = Rect.fromCenter(
      center: Offset(size.x / 2, size.y - 16 - height / 2),
      width: width,
      height: height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(16)),
      Paint()..color = const Color(0xE6FFFFFF),
    );

    // "Stability 72%  ·  leaning right"
    final lean = switch (b.side) {
      -1 => '  ·  leaning left',
      1 => '  ·  leaning right',
      _ => '',
    };
    TextPaint(
      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color),
    ).render(
      canvas,
      'Stability ${b.percent}%$lean',
      Vector2(rect.center.dx, rect.top + 8),
      anchor: Anchor.topCenter,
    );

    // The gauge: a track with the middle marked and the needle at the lean.
    final trackY = rect.top + 34;
    const trackHalf = 100.0;
    final cx = rect.center.dx;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(cx - trackHalf, trackY - 3, cx + trackHalf, trackY + 3),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0x338A6A55),
    );
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, trackY), width: 2, height: 12),
      Paint()..color = const Color(0x998A6A55),
    );
    canvas.drawCircle(
      Offset(cx + _shownTilt.clamp(-1.0, 1.0) * trackHalf, trackY),
      7,
      Paint()..color = color,
    );

    // The fix: land the next cat on the other side.
    if (wobbly) {
      TextPaint(
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Color(0xFF5B3A29),
        ),
      ).render(
        canvas,
        b.side > 0
            ? '◀  Land the next cat on the left'
            : 'Land the next cat on the right  ▶',
        Vector2(cx, trackY + 12),
        anchor: Anchor.topCenter,
      );
    }
  }
}

/// An invisible full-screen layer that catches taps.
class TapArea extends PositionComponent with TapCallbacks {
  TapArea(this.onTap);
  final VoidCallback onTap;

  @override
  bool containsLocalPoint(Vector2 point) => true;

  @override
  void onTapDown(TapDownEvent event) => onTap();
}
