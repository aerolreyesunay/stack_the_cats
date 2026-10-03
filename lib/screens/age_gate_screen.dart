import 'package:flutter/material.dart';

import '../services/age_gate.dart';

const _brown = Color(0xFF5B3A29);
const _muted = Color(0xFF8A6A55);
const _accent = Color(0xFFE76F51);

/// Asked once, on the first launch: the player's birth year. Neutral on
/// purpose (no year picked in advance, no hint of the "right" answer), as
/// Google Play's Families policy asks. Pops with the year chosen.
class AgeGateScreen extends StatefulWidget {
  const AgeGateScreen({super.key});

  @override
  State<AgeGateScreen> createState() => _AgeGateScreenState();
}

class _AgeGateScreenState extends State<AgeGateScreen> {
  int? _year;

  @override
  Widget build(BuildContext context) {
    final years = AgeGate.yearsToPick(DateTime.now().year);
    return PopScope(
      canPop: false, // it has to be answered
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cake_rounded, size: 56, color: _accent),
                    const SizedBox(height: 16),
                    const Text(
                      'What year were you born?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: _brown,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'So we can set up the game for you.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: _muted),
                    ),
                    const SizedBox(height: 24),
                    DropdownButtonFormField<int>(
                      initialValue: _year,
                      hint: const Text('Year'),
                      menuMaxHeight: 320,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      items: [
                        for (final y in years)
                          DropdownMenuItem(value: y, child: Text('$y')),
                      ],
                      onChanged: (y) => setState(() => _year = y),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _accent,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: _year == null
                            ? null
                            : () => Navigator.of(context).pop(_year),
                        child: const Text(
                          'Continue',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
