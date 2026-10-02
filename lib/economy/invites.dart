import 'dart:math';

import 'treats.dart';

/// Rules for invite codes and invite rewards.
class Invites {
  Invites._();

  static const codeLength = 6;

  /// No 0/O, 1/I/L: codes are read aloud and typed in by hand.
  static const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  /// A friend joining only rewards the inviter if the joiner's account is
  /// this new, so existing players can't trade codes for treats.
  static const newPlayerWindow = Duration(days: 7);

  static String randomCode([Random? rng]) {
    final r = rng ?? Random.secure();
    return List.generate(
      codeLength,
      (_) => _alphabet[r.nextInt(_alphabet.length)],
    ).join();
  }

  /// Tidies what a player typed (any case, spaces or dashes are fine).
  /// Returns null if it can't be a valid code.
  static String? normalize(String input) {
    final code = input.toUpperCase().replaceAll(RegExp(r'[\s\-_.]'), '');
    if (code.length != codeLength) return null;
    for (final ch in code.split('')) {
      if (!_alphabet.contains(ch)) return null;
    }
    return code;
  }

  /// The share message sent to friends.
  static String shareMessage(String code) =>
      "Let's stack cats! 🐱 Play Stack the Cats with me and enter my invite "
      'code $code when you sign in.\n'
      'https://play.google.com/store/apps/details?id=com.jcanstudios.stackthecats';
}

/// How many paid shares are left today.
class ShareAllowance {
  const ShareAllowance({required this.usedToday});

  final int usedToday;

  int get left => max(0, Treats.maxPaidSharesPerDay - usedToday);
  bool get canEarn => left > 0;

  /// [day] and [count] are what's saved on the player: the date of their
  /// last paid share ('yyyy-mm-dd') and how many paid shares that day.
  static ShareAllowance compute({
    required String? day,
    required int count,
    required String today,
  }) => ShareAllowance(usedToday: day == today ? count : 0);
}
