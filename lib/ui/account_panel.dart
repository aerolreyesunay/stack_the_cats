import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../services/connectivity_service.dart';
import 'brand_logos.dart';

const _brown = Color(0xFF5B3A29);
const _muted = Color(0xFF8A6A55);

/// Signed out: Google, Apple and Facebook logo buttons.
/// Signed in: who is signed in, and a Sign out link.
///
/// Players only sign in once: Firebase remembers them, so the app signs
/// them back in on its own until they sign out.
class AccountPanel extends StatefulWidget {
  const AccountPanel({super.key});

  @override
  State<AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends State<AccountPanel> {
  final _auth = AuthService.instance;
  bool _busy = false;

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() action, String failMessage) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      debugPrint('Auth error: $e');
      if (mounted) _showMessage(failMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _signIn(String provider) {
    if (provider != 'Google') {
      _showMessage('$provider sign-in is coming soon!');
      return;
    }
    _run(() async {
      final user = await _auth.signInWithGoogle();
      if (user != null && mounted) {
        _showMessage('Welcome, ${user.displayName ?? 'cat stacker'}!');
      }
    }, "Couldn't sign in with Google. Check your connection and try again.");
  }

  Future<void> _confirmSignOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Sign out?',
          style: TextStyle(fontWeight: FontWeight.w900, color: _brown),
        ),
        content: const Text(
          "Your treats are saved to your account. You won't earn more "
          'until you sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE76F51),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok == true) {
      _run(_auth.signOut, "Couldn't sign out. Please try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    // Offline, nobody is signed in: show a notice instead.
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService.instance.online,
      builder: (context, online, _) =>
          online ? _account() : const _OfflineNotice(),
    );
  }

  Widget _account() {
    return StreamBuilder<User?>(
      stream: _auth.userChanges,
      initialData: _auth.currentUser,
      builder: (context, snapshot) {
        if (_busy) {
          return const SizedBox(
            height: 56,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        return user == null ? _signedOut() : _signedIn(user);
      },
    );
  }

  Widget _signedOut() {
    return Column(
      children: [
        const Text(
          'Sign in to earn treats and save your scores',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: _muted),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final provider in ['Google', 'Apple', 'Facebook'])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: _LogoButton(
                  provider: provider,
                  onPressed: () => _signIn(provider),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _signedIn(User user) {
    final photo = user.photoURL;
    final displayName = user.displayName;
    final name = (displayName == null || displayName.trim().isEmpty)
        ? 'Cat stacker'
        : displayName;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: Colors.white,
          foregroundImage: photo != null ? NetworkImage(photo) : null,
          child: Text(
            name.characters.first.toUpperCase(),
            style: const TextStyle(fontSize: 14, color: _brown),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _brown,
            ),
          ),
        ),
        const SizedBox(width: 6),
        // Which account this is linked with.
        const BrandLogo('Google', size: 16),
        const SizedBox(width: 4),
        TextButton(
          onPressed: _confirmSignOut,
          style: TextButton.styleFrom(foregroundColor: _muted),
          child: const Text('Sign out'),
        ),
      ],
    );
  }
}

class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _brown.withAlpha(40)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, color: Color(0xFFE76F51)),
          SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No Internet Connection',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _brown,
                  ),
                ),
                Text(
                  'You can still play as a guest',
                  style: TextStyle(fontSize: 13, color: _muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A round white button showing just a provider's logo.
class _LogoButton extends StatelessWidget {
  const _LogoButton({required this.provider, required this.onPressed});

  final String provider;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Sign in with $provider',
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          shape: const CircleBorder(),
          backgroundColor: Colors.white,
          side: BorderSide(color: _brown.withAlpha(50)),
          padding: const EdgeInsets.all(14),
          minimumSize: const Size(56, 56),
        ),
        onPressed: onPressed,
        child: BrandLogo(provider, size: 26),
      ),
    );
  }
}
