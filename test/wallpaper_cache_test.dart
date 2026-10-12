import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stack_the_cats/store/wallpapers.dart';

void main() {
  test('each repeat is a whole number of rows, so the wall wraps', () {
    const rows = {
      WallPattern.dots: 48.0,
      WallPattern.hearts: 48.0,
      WallPattern.plaid: 64.0,
      WallPattern.checks: 32.0,
      WallPattern.fish: 64.0,
      WallPattern.crowns: 64.0,
      WallPattern.blossoms: 64.0,
      WallPattern.leaves: 72.0,
      WallPattern.paws: 80.0,
      WallPattern.stars: 96.0,
    };
    for (final MapEntry(key: pattern, value: row) in rows.entries) {
      expect(wallpaperPeriod(pattern) % row, 0, reason: pattern.name);
    }
  });

  test('every wallpaper draws from the cache, at any scroll', () {
    final cache = WallpaperCache();
    for (final wallpaper in Wallpapers.all) {
      for (final scroll in [0.0, 137.0, 5000.5]) {
        final recorder = ui.PictureRecorder();
        cache.paint(
          Canvas(recorder),
          const Size(360, 640),
          wallpaper,
          scroll: scroll,
          pixelRatio: 2,
        );
        recorder.endRecording().dispose();
      }
    }
    cache.dispose();
  });
}
