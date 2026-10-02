import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../challenge/challenge_service.dart';

/// Build with `--dart-define=USE_EMULATORS=true` to use the Firebase
/// emulators on this computer (run `firebase emulators:start`) instead of
/// the real project. From the Android emulator, the computer is 10.0.2.2.
const useEmulators = bool.fromEnvironment('USE_EMULATORS');
const _emulatorHost = String.fromEnvironment(
  'EMULATOR_HOST',
  defaultValue: '10.0.2.2',
);

/// App Check: every call to the server carries proof that it comes from
/// this app, untouched, on a real phone (Google Play Integrity), so scripts
/// and modified copies of the app can be refused. Debug builds use a debug
/// token instead (printed in the log; add it in the Firebase console under
/// App Check to let a test phone through once checks are enforced).
Future<void> startAppCheck() async {
  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kReleaseMode
          ? const AndroidPlayIntegrityProvider()
          : const AndroidDebugProvider(),
    );
  } catch (e) {
    debugPrint('App Check failed to start: $e');
  }
}

/// Points every Firebase service at the local emulators, when built for
/// them. Call right after Firebase.initializeApp.
Future<void> connectEmulatorsIfAsked() async {
  if (!useEmulators) return;
  debugPrint('Using the Firebase emulators at $_emulatorHost');
  await FirebaseAuth.instance.useAuthEmulator(_emulatorHost, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(_emulatorHost, 8080);
  FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: rtdbUrl,
  ).useDatabaseEmulator(_emulatorHost, 9000);
  ServerApi.instance._functions.useFunctionsEmulator(_emulatorHost, 5001);
}

/// Why the server refused something, e.g. 'not-enough-treats'.
class ServerError implements Exception {
  const ServerError(this.reason);

  final String reason;

  /// A message for the player.
  String get message => switch (reason) {
    'not-enough-treats' => 'Not enough treats.',
    'not-enough-tuna' => 'You have no Tuna left.',
    'not-enough-salmon' => 'You have no Salmon left.',
    'daily-limit' => "That's the limit for today. Come back tomorrow!",
    'already-claimed' => 'Already claimed today.',
    'already-owned' => 'You already have that.',
    'limit-reached' => 'Used up for this game.',
    'wagers-locked' => 'Treat wagers unlock after you stack 200 cats.',
    'offline' => "Couldn't reach the server. Check your connection.",
    _ => 'Something went wrong, so nothing was changed.',
  };

  @override
  String toString() => 'ServerError($reason)';
}

/// The game's server (Cloud Functions). Every change to treats, Tuna,
/// Salmon and Store items goes through here.
class ServerApi {
  ServerApi._();
  static final ServerApi instance = ServerApi._();

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );

  static final _rng = Random.secure();
  static const _chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

  /// A fresh id for one wallet operation. The server applies each id once
  /// and lists it on the player when done.
  static String newOpId() =>
      List.generate(20, (_) => _chars[_rng.nextInt(_chars.length)]).join();

  /// Runs [action] on the server. Throws [ServerError] if it's refused or
  /// the server can't be reached.
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, Object?> params = const {},
  ]) async {
    try {
      final result = await _functions
          .httpsCallable(
            'api',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
          )
          .call<Object?>({'action': action, ...params});
      final data = result.data;
      return data is Map ? Map<String, dynamic>.from(data) : const {};
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      final reason = details is Map && details['reason'] is String
          ? details['reason'] as String
          : switch (e.code) {
              'unavailable' || 'deadline-exceeded' || 'internal' => 'offline',
              _ => e.code,
            };
      debugPrint('Server refused $action: $reason (${e.message})');
      throw ServerError(reason);
    } catch (e) {
      debugPrint('Server call $action failed: $e');
      throw const ServerError('offline');
    }
  }
}
