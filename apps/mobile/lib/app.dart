import 'package:flutter/material.dart';

import 'core/routing/app_router.dart';

class TerrangoApp extends StatelessWidget {
  const TerrangoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Terrango',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00BFA5),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0B0F16),
        useMaterial3: true,
      ),
      routerConfig: appRouter,
    );
  }
}
