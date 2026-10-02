import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
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

  /// Facebook's login (its app, or a web page) and signs into Firebase
  /// with the result. Returns null if the player cancelled.
  ///
  /// If the player's email is already used by their Google sign-in, this
  /// throws [FirebaseAuthException] 'account-exists-with-different-credential'
  /// (one account per email): they should sign in with Google instead.
  Future<User?> signInWithFacebook() async {
    final login = await FacebookAuth.instance.login(
      permissions: const ['public_profile', 'email'],
    );
    switch (login.status) {
      case LoginStatus.success:
        final token = login.accessToken!.tokenString;
        final result = await _auth.signInWithCredential(
          FacebookAuthProvider.credential(token),
        );
        return result.user;
      case LoginStatus.cancelled:
        return null;
      default:
        throw StateError('Facebook login failed: ${login.message}');
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    try {
      await FacebookAuth.instance.logOut();
    } catch (e) {
      debugPrint('Facebook sign-out failed: $e');
    }
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
