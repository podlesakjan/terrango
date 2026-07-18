import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/game_models.dart';
import '../state/game_session_controller.dart';
import '../widgets/mapbox_hex_map.dart';
import '../widgets/section_card.dart';
import '../widgets/status_pill.dart';
import 'hex_context_sheet.dart';

class TacticalMapScreen extends StatelessWidget {
  const TacticalMapScreen({super.key, required this.onNavigate});

  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    return Consumer<GameSessionController>(
      builder: (context, controller, _) {
        return SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _TopStatusBar(controller: controller),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _ActionChip(
                        label: 'RECRUITMENT',
                        icon: Icons.radar_rounded,
                        onTap: () => onNavigate(1),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ActionChip(
                        label: 'BARRACKS',
                        icon: Icons.storefront_rounded,
                        onTap: () => onNavigate(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ActionChip(
                        label: 'BASES',
                        icon: Icons.fort_rounded,
                        onTap: () => onNavigate(3),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: MediaQuery.sizeOf(context).height * 0.48,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF121A2B),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          MapboxHexMap(
                            controller: controller,
                            onNavigateToRecruitment: () => onNavigate(1),
                          ),
                          Positioned(
                            left: 16,
                            bottom: 16,
                            child: StatusPill(
                              label: 'GPS · ${controller.currentLocationH3Index}',
                              icon: Icons.my_location_rounded,
                              backgroundColor: const Color(0x332563EB),
                              foregroundColor: const Color(0xFF8FB7FF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: SectionCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: const [
                      Expanded(
                        child: Text(
                          'Ad banner placeholder · SafeArea preserved for Google Mobile Ads integration',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                      SizedBox(width: 12),
                      Icon(Icons.campaign_rounded, color: Color(0xFF4FC3F7)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TopStatusBar extends StatelessWidget {
  const _TopStatusBar({required this.controller});

  final GameSessionController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF4FC3F7).withValues(alpha: 0.18),
            child: const Icon(Icons.person_rounded, color: Color(0xFF8FD3FF)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.profile.nickname,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Hexes: ${controller.profile.hexesClaimed} · Reserve: ⚔️ ${controller.reserveBs} / 📡 ${controller.patrolCount}',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusPill(
            label: controller.notificationsEnabled ? 'ONLINE' : 'OFFLINE',
            icon: Icons.wifi_rounded,
            backgroundColor: controller.notificationsEnabled
                ? const Color(0x3310B981)
                : Colors.white.withValues(alpha: 0.08),
            foregroundColor: controller.notificationsEnabled ? const Color(0xFF8DF5C8) : Colors.white,
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}









