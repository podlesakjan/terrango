import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/onboarding_screen.dart';
import 'screens/shell_screen.dart';
import 'state/game_session_controller.dart';
import 'theme/app_theme.dart';

class TerrangoApp extends StatelessWidget {
  const TerrangoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Terrango',
      theme: TerrangoTheme.dark(),
      home: Consumer<GameSessionController>(
        builder: (context, controller, _) {
          return controller.onboardingComplete ? const ShellScreen() : const OnboardingScreen();
        },
      ),
    );
  }
}

