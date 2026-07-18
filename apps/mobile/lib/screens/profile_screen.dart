import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/game_session_controller.dart';
import '../widgets/section_card.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<GameSessionController>(
      builder: (context, controller, _) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SectionCard(
                title: 'Player profile',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(controller.profile.nickname,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(controller.profile.email),
                    const SizedBox(height: 16),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Nickname',
                        prefixIcon: Icon(Icons.edit_rounded),
                      ),
                      onSubmitted: (value) => controller.updateNickname(value.trim().isEmpty ? controller.profile.nickname : value.trim()),
                    ),
                    const SizedBox(height: 12),
                    const Text('Google / Apple account linking is scaffolded through the auth contract.'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Statistics',
                child: Column(
                  children: [
                    _StatsRow(label: 'Hexes claimed', value: '${controller.profile.hexesClaimed}'),
                    _StatsRow(label: 'Biggest battle BS', value: '${controller.profile.biggestBattleBs}'),
                    _StatsRow(label: 'Scanned devices', value: '${controller.profile.scannedDevices}'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Technical toggles',
                child: Column(
                  children: [
                    SwitchListTile(
                      value: controller.wakeLockEnabled,
                      onChanged: controller.toggleWakeLock,
                      title: const Text('Prevent screen sleep (Wake Lock)'),
                      subtitle: const Text('Keeps the display awake while walking and scanning.'),
                    ),
                    SwitchListTile(
                      value: controller.backgroundServiceEnabled,
                      onChanged: controller.toggleBackgroundService,
                      title: const Text('Run in background (Foreground Service)'),
                      subtitle: const Text('Keeps GPS and BLE collection alive in the pocket.'),
                    ),
                    SwitchListTile(
                      value: controller.notificationsEnabled,
                      onChanged: controller.toggleNotifications,
                      title: const Text('Push notifications'),
                      subtitle: const Text('Incoming attacks and battle updates.'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

