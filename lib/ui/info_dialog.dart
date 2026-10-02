import 'dart:math';

import 'package:flutter/material.dart';

import 'treat_confetti.dart';
import 'treats_ui.dart';

const _brown = Color(0xFF5B3A29);
const _accent = Color(0xFFE76F51);

/// A cheerful title for earning treats: "meWow!", "Pawsome!"...
String catCheer() => _cheers[Random().nextInt(_cheers.length)];

const _cheers = [
  'meWow!',
  'Sweet!',
  'Purrfect!',
  'Pawsome!',
  'Fishtastic!',
  'Meow-velous!',
  'Clawsome!',
];

/// A small pop-up with a message and an OK button, e.g. "Friend request
/// sent!". [treats] shows a big treat amount (for rewards). With
/// [celebrate], treat confetti rains while it shows.
Future<void> showInfoDialog(
  BuildContext context, {
  required String title,
  required String message,
  IconData icon = Icons.group_rounded,
  int? treats,
  bool celebrate = false,
}) {
  if (celebrate) showTreatConfetti(context);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Colors.white,
      icon: Icon(icon, color: _accent, size: 40),
      title: Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w900, color: _brown),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (treats != null) ...[
            TreatAmount(treats, size: 34),
            const SizedBox(height: 12),
          ],
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: _brown),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 12),
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK', style: TextStyle(fontSize: 16)),
        ),
      ],
    ),
  );
}
