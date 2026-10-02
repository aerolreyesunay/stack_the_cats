import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'challenge/challenge_invite_listener.dart';
import 'game/stack_game.dart';
import 'screens/loading_screen.dart';
import 'services/player_service.dart';
import 'services/server_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // This game is designed for portrait mode only.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Firebase and the sounds are loaded by the loading screen.
  runApp(const StackTheCatsApp());
}

/// For messages from anywhere (e.g. the server refusing a purchase).
final appMessengerKey = GlobalKey<ScaffoldMessengerState>();

class StackTheCatsApp extends StatefulWidget {
  const StackTheCatsApp({super.key});

  @override
  State<StackTheCatsApp> createState() => _StackTheCatsAppState();
}

class _StackTheCatsAppState extends State<StackTheCatsApp> {
  final _problem = PlayerService.instance.problem;

  @override
  void initState() {
    super.initState();
    _problem.addListener(_showProblem);
  }

  @override
  void dispose() {
    _problem.removeListener(_showProblem);
    super.dispose();
  }

  /// The server refused something (it was undone on screen): say why.
  void _showProblem() {
    final ServerError? problem = _problem.value;
    if (problem == null) return;
    _problem.value = null;
    appMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(problem.message)));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stack the Cats',
      navigatorKey: appNavigatorKey,
      scaffoldMessengerKey: appMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE76F51)),
        scaffoldBackgroundColor: StackGame.wallColor,
        // Transparent app bars would otherwise switch to light status bar
        // icons, which vanish on the cream background.
        appBarTheme: const AppBarTheme(
          systemOverlayStyle: SystemUiOverlayStyle.dark,
        ),
      ),
      // Dark status bar icons for the light game screens. The loading screen
      // switches to light icons for its dark background.
      // Challenge pop-ups can appear on any screen.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: ChallengeInviteListener(child: child!),
      ),
      home: const LoadingScreen(),
    );
  }
}
