import 'dart:async';
import 'dart:math';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sound effect file names (inside assets/audio/).
class Sfx {
  static const thump = 'thump.mp3';
  static const meows = ['cat_meow_2.mp3', 'cat_meow_3.mp3'];
  static const purrfect = 'cat_purrfect.mp3';
  static const chimes = [
    'chime_1.mp3',
    'chime_2.mp3',
    'chime_3.mp3',
    'chime_4.mp3',
  ];
  static const miss = 'cat_misses.mp3';
  static const collapse = 'tower_tumbles.mp3';
  static const gameOver = 'game_over.mp3';
  static const tap = 'screen_tap.mp3';
  static const applause = 'applause.mp3';

  static const all = [
    thump,
    ...meows,
    purrfect,
    ...chimes,
    miss,
    collapse,
    gameOver,
    tap,
    applause,
  ];
}

/// Background music file names (inside assets/audio/).
class Music {
  static const menu = 'main_menu_music.mp3';
  static const game = 'in_game_music.mp3';
}

/// One place that plays every sound and remembers the on/off settings.
class AudioManager {
  AudioManager._();
  static final AudioManager instance = AudioManager._();

  static const double musicVolume = 0.4;
  static const double sfxVolume = 1.0;

  /// How long the thump plays before the meow (or "purrfect") starts.
  static const Duration thumpToMeow = Duration(milliseconds: 120);

  /// How many copies of a sound can play at once. Sounds that can overlap
  /// (quick taps, back-to-back landings) get more.
  static const Map<String, int> _poolSizes = {
    Sfx.tap: 4,
    Sfx.thump: 3,
    Sfx.purrfect: 2,
  };

  final Random _rng = Random();
  SharedPreferences? _prefs;

  bool musicOn = true;
  bool sfxOn = true;
  String? _currentTrack;

  /// Loads settings and preloads every sound. [onProgress] is called with
  /// 0.0-1.0 as each file finishes, for the loading screen's progress bar.
  Future<void> init({void Function(double progress)? onProgress}) async {
    try {
      _prefs = await SharedPreferences.getInstance();
      musicOn = _prefs?.getBool('musicOn') ?? true;
      sfxOn = _prefs?.getBool('sfxOn') ?? true;
    } catch (_) {}
    FlameAudio.bgm.initialize(); // pauses music when the app is in background
    final total = Sfx.all.length + 2;
    var loaded = 0;
    void done() => onProgress?.call(++loaded / total);
    await Future.wait([
      // Sound effects get ready-to-play pools, so they start instantly.
      for (final file in Sfx.all) _createPool(file).whenComplete(done),
      for (final file in [Music.menu, Music.game])
        FlameAudio.audioCache
            .load(file)
            .then<void>(
              (_) {},
              onError: (Object e) => debugPrint('Music preload failed: $e'),
            )
            .whenComplete(done),
    ]);
  }

  Future<void> _createPool(String file) async {
    try {
      final size = _poolSizes[file] ?? 1;
      _pools[file] = await FlameAudio.createPool(
        file,
        minPlayers: size,
        maxPlayers: size,
      );
    } catch (e) {
      // Falls back to playing it the slow way.
      debugPrint('Sound pool failed for $file: $e');
    }
  }

  // ---------- Settings ----------
  Future<void> setMusicOn(bool value) async {
    musicOn = value;
    _prefs?.setBool('musicOn', value);
    if (value) {
      final track = _currentTrack;
      if (track != null) _startTrack(track);
    } else {
      await _safe(() => FlameAudio.bgm.stop());
    }
  }

  void setSfxOn(bool value) {
    sfxOn = value;
    _prefs?.setBool('sfxOn', value);
  }

  // ---------- Music ----------
  void playMusic(String track) {
    if (_currentTrack == track && FlameAudio.bgm.isPlaying) return;
    _currentTrack = track;
    if (musicOn) _startTrack(track);
  }

  void pauseMusic() => _safe(() => FlameAudio.bgm.pause());

  void resumeMusic() {
    if (musicOn) _safe(() => FlameAudio.bgm.resume());
  }

  void _startTrack(String track) =>
      _safe(() => FlameAudio.bgm.play(track, volume: musicVolume));

  // ---------- Sound effects ----------

  /// A ready-to-play pool per sound effect, made at startup. Starting a
  /// pooled sound is instant; making a new player each time is not.
  final Map<String, AudioPool> _pools = {};

  /// How to stop each sound started since the last [stopAllSfx]. Calling one
  /// for a sound that already finished does nothing.
  final List<StopFunction> _sfxStops = [];

  /// Sound effects that aren't pooled (only if a pool failed to load).
  final Set<AudioPlayer> _sfxUnpooled = {};

  /// Sound effects waiting to start (e.g. the meow after a thump).
  final Set<Timer> _sfxScheduled = {};

  /// Goes up on every [stopAllSfx], so a sound that was still starting up
  /// when everything was stopped knows to stay quiet.
  int _sfxGeneration = 0;

  void playSfx(String file, {double volume = sfxVolume}) {
    if (!sfxOn) return;
    final generation = _sfxGeneration;
    final pool = _pools[file];
    _safe(() async {
      if (pool != null) {
        final stop = await pool.start(volume: volume);
        if (generation != _sfxGeneration) {
          await stop(); // stopped while it was starting
        } else {
          _sfxStops.add(stop);
          // Finished sounds' stops are harmless; just keep the list short.
          if (_sfxStops.length > 24) _sfxStops.removeAt(0);
        }
        return;
      }
      final player = await FlameAudio.play(file, volume: volume);
      if (generation != _sfxGeneration) {
        await player.dispose();
        return;
      }
      _sfxUnpooled.add(player);
      // flame_audio never disposes its players; do it when the sound ends.
      // (A sound stopped early never "completes": that's fine, ignore it.)
      player.onPlayerComplete.first.then((_) {
        if (_sfxUnpooled.remove(player)) _safe(player.dispose);
      }, onError: (Object _) {});
    });
  }

  /// Plays a sound after [delay], unless [stopAllSfx] is called first.
  void _playLater(Duration delay, String file) {
    late final Timer timer;
    timer = Timer(delay, () {
      _sfxScheduled.remove(timer);
      playSfx(file);
    });
    _sfxScheduled.add(timer);
  }

  /// Silences every sound effect, including ones about to start. Used when
  /// a run restarts, a prompt opens, or the player leaves the game.
  void stopAllSfx() {
    _sfxGeneration++;
    for (final timer in _sfxScheduled) {
      timer.cancel();
    }
    _sfxScheduled.clear();
    for (final stop in _sfxStops) {
      _safe(stop);
    }
    _sfxStops.clear();
    for (final player in _sfxUnpooled.toList()) {
      _sfxUnpooled.remove(player);
      _safe(() async {
        await player.stop();
        await player.dispose();
      });
    }
  }

  /// Thump, then a random meow right after.
  void playLanding() {
    playSfx(Sfx.thump);
    _playLater(thumpToMeow, Sfx.meows[_rng.nextInt(Sfx.meows.length)]);
  }

  /// Thump, then the "purrfect" sound instead of a meow.
  void playPerfectLanding() {
    playSfx(Sfx.thump);
    _playLater(thumpToMeow, Sfx.purrfect);
  }

  /// Plays chime 1-4 (index 0-3) shortly after the purrfect sound.
  void playChime(int index) {
    _playLater(
      const Duration(milliseconds: 350),
      Sfx.chimes[index.clamp(0, Sfx.chimes.length - 1)],
    );
  }

  Future<void> _safe(Future<dynamic> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('Audio error: $e');
    }
  }
}
