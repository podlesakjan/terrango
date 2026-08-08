import 'package:go_router/go_router.dart';

import '../../presentation/screens/map/map_screen.dart';
import '../../presentation/screens/onboarding/onboarding_screen.dart';

abstract final class AppRoute {
  static const onboarding = '/';
  static const map = '/map';
}

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoute.onboarding,
  routes: [
    GoRoute(
      path: AppRoute.onboarding,
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(path: AppRoute.map, builder: (context, state) => const MapScreen()),
  ],
);
