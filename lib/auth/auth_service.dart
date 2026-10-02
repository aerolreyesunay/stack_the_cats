import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// One place that signs players in and out and knows who is signed in.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  bool _googleReady = false;

  FirebaseAuth get _auth => FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  /// Fires with the user on sign-in and with null on sign-out.
  Stream<User?> get userChanges => _auth.authStateChanges();

  /// Google's plugin must be initialized exactly once before use.
  Future<void> _initGoogle() async {
    if (_googleReady) return;
    // On Android the client ID is read from google-services.json.
    await GoogleSignIn.instance.initialize();
    _googleReady = true;
  }

  /// Shows Google's account picker and signs into Firebase with the result.
  /// Returns null if the player closed the picker.
  Future<User?> signInWithGoogle() async {
    await _initGoogle();
    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
    final credential = GoogleAuthProvider.credential(
      idToken: account.authentication.idToken,
    );
    final result = await _auth.signInWithCredential(credential);
    return result.user;
  }

  Future<void> signOut() async {
    await _auth.signOut();
    try {
      await _initGoogle();
      // Without this, the next sign-in would reuse the same Google account
      // instead of letting the player pick one.
      await GoogleSignIn.instance.signOut();
    } catch (e) {
      debugPrint('Google sign-out failed: $e');
    }
  }
}
