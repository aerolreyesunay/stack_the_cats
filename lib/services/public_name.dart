import 'package:flutter/widgets.dart';

/// How a player shows to people who aren't their friends: first name and
/// the initial of the last name ("Aerol U."). Friends see the full name.
/// The same as the server's boardName (functions/src/economy.ts).
String publicName(String? fullName) {
  final words = (fullName ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return 'Cat stacker';
  final first = words.first.characters.take(30).toString();
  if (words.length == 1) return first;
  return '$first ${words.last.characters.first.toUpperCase()}.';
}
