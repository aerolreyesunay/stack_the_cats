import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/audio_manager.dart';
import '../auth/auth_service.dart';
import '../services/age_gate.dart';
import '../services/player_service.dart';
import '../store/wallpapers.dart';

/// The privacy policy and account deletion pages (Google Play requires
/// links to both in the app).
const _privacyUrl = 'https://jcanstudios.github.io/stack-the-cats/privacy.html';
const _deleteUrl =
    'https://jcanstudios.github.io/stack-the-cats/delete-data.html';
const _links = MethodChannel('stack_the_cats/links');

/// Sound, (once bought) which wallpaper to use, and privacy links. Choices
/// are saved.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final audio = AudioManager.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.music_note_rounded),
                  title: const Text('Music'),
                  value: audio.musicOn,
                  onChanged: (v) async {
                    await audio.setMusicOn(v);
                    setState(() {});
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.volume_up_rounded),
                  title: const Text('Sound effects'),
                  value: audio.sfxOn,
                  onChanged: (v) {
                    audio.setSfxOn(v);
                    if (v) audio.playSfx(Sfx.tap); // quick preview
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
          // Only once the player has bought at least one wallpaper.
          ValueListenableBuilder<PlayerData?>(
            valueListenable: PlayerService.instance.player,
            builder: (context, player, _) {
              if (player == null || player.wallpaperPool.length < 2) {
                return const SizedBox.shrink();
              }
              return _WallpaperSettings(player: player);
            },
          ),
          const SizedBox(height: 16),
          // Kids' mode: the made-up name and account ID, so a parent can ask
          // us to delete the account.
          if (AgeGate.instance.isKid &&
              AuthService.instance.currentUser != null) ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.pets_rounded),
                title: Text(
                  KidName.forUid(AuthService.instance.currentUser!.uid),
                ),
                subtitle: SelectableText(
                  'Player ID: ${AuthService.instance.currentUser!.uid}',
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy policy'),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: () => _open(_privacyUrl),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Delete account'),
                  subtitle: const Text(
                    'Ask us to delete your account and its data',
                  ),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: () => _open(_deleteUrl),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Opens [url] in the browser (MainActivity.kt does it on Android).
  Future<void> _open(String url) async {
    final opened = await _links
        .invokeMethod<bool>('open', url)
        .catchError((Object _) => false);
    if (opened != true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't open the browser. Visit $url")),
      );
    }
  }
}

/// Always use one wallpaper, or a random one from the collection each game.
class _WallpaperSettings extends StatelessWidget {
  const _WallpaperSettings({required this.player});
  final PlayerData player;

  @override
  Widget build(BuildContext context) {
    final service = PlayerService.instance;
    final random = player.wallpaperRandom;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(
                'Wallpaper',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.shuffle_rounded),
              title: const Text('Random each game'),
              subtitle: Text(
                'A different one of your ${player.wallpaperPool.length} '
                'wallpapers every game',
              ),
              value: random,
              onChanged: service.setWallpaperRandom,
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                random ? 'Turn off Random to choose one' : 'Always use',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            for (final w in player.wallpaperPool)
              ListTile(
                enabled: !random,
                leading: _Swatch(wallpaper: w),
                title: Text(w.name),
                trailing: !random && player.wallpaper.id == w.id
                    ? const Icon(Icons.check_circle_rounded)
                    : null,
                onTap: () => service.useWallpaper(w),
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

/// A small square of a wallpaper.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.wallpaper});
  final Wallpaper wallpaper;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 40,
        height: 40,
        child: CustomPaint(painter: _SwatchPainter(wallpaper)),
      ),
    );
  }
}

class _SwatchPainter extends CustomPainter {
  const _SwatchPainter(this.wallpaper);
  final Wallpaper wallpaper;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    // A zoomed-out look so the pattern shows in a small square.
    canvas.scale(0.5);
    paintWallpaper(canvas, size * 2, wallpaper);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SwatchPainter old) => old.wallpaper != wallpaper;
}
