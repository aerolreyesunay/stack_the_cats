import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

/// New versions from Google Play, offered inside the game: Google's
/// "Update available" sheet, a download in the background while the
/// player keeps playing, then a Restart button on the main menu installs
/// it.
///
/// Only works for copies installed from Google Play (not `flutter run`),
/// and only for versions released after this one.
class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  /// True once an update has downloaded and only needs a restart.
  final ValueNotifier<bool> readyToInstall = ValueNotifier(false);

  bool _checked = false;

  /// Looks for an update once per launch.
  Future<void> checkOnce() async {
    if (_checked || kIsWeb || !Platform.isAndroid) return;
    _checked = true;
    try {
      final info = await InAppUpdate.checkForUpdate();
      // Downloaded last time but not installed yet.
      if (info.installStatus == InstallStatus.downloaded) {
        readyToInstall.value = true;
        return;
      }
      if (info.updateAvailability != UpdateAvailability.updateAvailable ||
          !info.flexibleUpdateAllowed) {
        return;
      }
      // Completes once the download has finished (or the player said no).
      final result = await InAppUpdate.startFlexibleUpdate();
      if (result == AppUpdateResult.success) readyToInstall.value = true;
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
  }

  /// Restarts the app into the downloaded update.
  Future<void> install() async {
    try {
      await InAppUpdate.completeFlexibleUpdate();
    } catch (e) {
      debugPrint('Installing the update failed: $e');
    }
  }
}
