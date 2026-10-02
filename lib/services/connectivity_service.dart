import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

/// Whether the phone can actually reach the internet right now.
///
/// Being on Wi-Fi isn't enough (the Wi-Fi itself may have no internet),
/// so every change is double-checked by looking up a Google server.
class ConnectivityService with WidgetsBindingObserver {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  /// True while online. Starts true so the app doesn't flash an offline
  /// notice before the first check finishes.
  final ValueNotifier<bool> online = ValueNotifier(true);

  bool get isOnline => online.value;

  static const _recheckEvery = Duration(seconds: 20);

  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _timer;
  bool _started = false;

  /// Call once at startup. Completes after the first check.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _sub = Connectivity().onConnectivityChanged.listen((_) => check());
    _timer = Timer.periodic(_recheckEvery, (_) => check());
    await check();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) check();
  }

  Future<void> check() async {
    online.value = await _canReachInternet();
  }

  Future<bool> _canReachInternet() async {
    try {
      final types = await Connectivity().checkConnectivity();
      if (types.every((t) => t == ConnectivityResult.none)) return false;
      final result = await InternetAddress.lookup('firestore.googleapis.com')
          .timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
