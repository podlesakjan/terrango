import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'barracks_screen.dart';
import 'battle_logs_screen.dart';
import 'profile_screen.dart';
import 'recruitment_screen.dart';
import 'tactical_map_screen.dart';
import 'territory_screen.dart';
import '../widgets/status_pill.dart';
import '../state/game_session_controller.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  late final PageController _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GameSessionController>(
      builder: (context, controller, _) {
        final pages = <Widget>[
          TacticalMapScreen(onNavigate: controller.selectTab),
          const RecruitmentScreen(),
          const BarracksScreen(),
          const TerritoryScreen(),
          const BattleLogsScreen(),
          const ProfileScreen(),
        ];

        return Scaffold(
          body: Stack(
            children: [
              PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: pages,
                onPageChanged: controller.selectTab,
              ),
              if (controller.selectedTab == 0)
                const Positioned(
                  top: 48,
                  right: 16,
                  child: StatusPill(
                    label: 'LIVE · SOCKET READY',
                    icon: Icons.wifi_tethering_rounded,
                    backgroundColor: Color(0x3310B981),
                    foregroundColor: Color(0xFF8DF5C8),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: controller.selectedTab,
            onDestinationSelected: controller.selectTab,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.map_rounded), label: 'Map'),
              NavigationDestination(icon: Icon(Icons.radar_rounded), label: 'Recruit'),
              NavigationDestination(icon: Icon(Icons.storefront_rounded), label: 'Barracks'),
              NavigationDestination(icon: Icon(Icons.fort_rounded), label: 'Bases'),
              NavigationDestination(icon: Icon(Icons.history_rounded), label: 'Logs'),
              NavigationDestination(icon: Icon(Icons.settings_rounded), label: 'Settings'),
            ],
          ),
        );
      },
    );
  }
}



