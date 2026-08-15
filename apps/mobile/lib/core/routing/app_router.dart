import 'package:go_router/go_router.dart';

import '../../presentation/screens/barracks/barracks_screen.dart';
import '../../presentation/screens/bases/bases_screen.dart';
import '../../presentation/screens/battle_logs/battle_logs_screen.dart';
import '../../presentation/screens/map/map_screen.dart';
import '../../presentation/screens/onboarding/onboarding_screen.dart';
import '../../presentation/screens/profile/profile_screen.dart';
import '../../presentation/screens/recruitment/recruitment_screen.dart';

abstract final class AppRoute {
  static const onboarding = '/';
  static const map = '/map';
  static const recruitment = '/recruitment';
  static const barracks = '/barracks';
  static const bases = '/bases';
  static const battleLogs = '/battle-logs';
  static const profile = '/profile';

  static String mapWithFocus(String h3Index) {
    return Uri(path: map, queryParameters: {'focusH3': h3Index}).toString();
  }
}

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoute.onboarding,
  routes: [
    GoRoute(
      path: AppRoute.onboarding,
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: AppRoute.map,
      builder: (context, state) =>
          MapScreen(focusH3Index: state.uri.queryParameters['focusH3']),
    ),
    GoRoute(
      path: AppRoute.recruitment,
      builder: (context, state) => const RecruitmentScreen(),
    ),
    GoRoute(
      path: AppRoute.barracks,
      builder: (context, state) => const BarracksScreen(),
    ),
    GoRoute(
      path: AppRoute.bases,
      builder: (context, state) => const BasesScreen(),
    ),
    GoRoute(
      path: AppRoute.battleLogs,
      builder: (context, state) => const BattleLogsScreen(),
    ),
    GoRoute(
      path: AppRoute.profile,
      builder: (context, state) => const ProfileScreen(),
    ),
  ],
);
