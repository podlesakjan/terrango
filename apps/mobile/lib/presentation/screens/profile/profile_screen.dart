import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../providers/app_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    final nickname = ref.watch(nicknameProvider);
    final wakeLockEnabled = ref.watch(wakeLockEnabledProvider);
    final backgroundTrackingEnabled = ref.watch(backgroundTrackingEnabledProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Profile'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.read(profileProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(profileProvider.notifier).refresh(),
        child: profileAsync.when(
          data: (profile) {
            final stats = profile['stats'] as Map<String, dynamic>? ?? const <String, dynamic>{};
            final email = (profile['email'] as String?) ?? '-';
            final currentNickname = (profile['nickname'] as String?) ?? nickname;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Player Profile', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    title: const Text('Nickname'),
                    subtitle: Text(currentNickname),
                    trailing: FilledButton.tonal(
                      onPressed: () => _changeNickname(context, ref, currentNickname),
                      child: const Text('Change'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    title: const Text('Linked account'),
                    subtitle: Text(email),
                    trailing: const Icon(Icons.verified_user_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Statistics', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                _StatCard(label: 'Hexes conquered', value: stats['hexesClaimed']?.toString() ?? '0'),
                _StatCard(label: 'Biggest battle BS', value: stats['biggestBattleBs']?.toString() ?? '0'),
                _StatCard(label: 'Scanned Bluetooth devices', value: stats['scannedDevices']?.toString() ?? '0'),
                const SizedBox(height: 16),
                Text('Technical toggles', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Card(
                  child: SwitchListTile(
                    value: wakeLockEnabled,
                    onChanged: (value) async {
                      await _toggleWakeLock(context, ref, value);
                    },
                    title: const Text('Prevent screen sleep'),
                    subtitle: const Text(
                      'Keep the display awake while you are walking and actively scanning.',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: SwitchListTile(
                    value: backgroundTrackingEnabled,
                    onChanged: (value) async {
                      await _toggleBackgroundTracking(context, ref, value);
                    },
                    title: const Text('Run in background'),
                    subtitle: const Text(
                      'On Android, this starts a foreground service so GPS and Bluetooth collection can continue with the screen off.',
                    ),
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [Text('Failed to load profile: $error')],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleWakeLock(BuildContext context, WidgetRef ref, bool value) async {
    try {
      await WakelockPlus.toggle(enable: value);
      await ref.read(wakeLockEnabledProvider.notifier).setEnabled(value);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Failed to update wake lock: $error')),
        );
    }
  }

  Future<void> _toggleBackgroundTracking(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    try {
      await ref.read(backgroundTrackingServiceProvider).setEnabled(value);
      await ref.read(backgroundTrackingEnabledProvider.notifier).setEnabled(value);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? 'Background tracking preference enabled.'
                  : 'Background tracking preference disabled.',
            ),
          ),
        );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Failed to update background tracking: $error')),
        );
    }
  }

  Future<void> _changeNickname(BuildContext context, WidgetRef ref, String currentNickname) async {
    final controller = TextEditingController(text: currentNickname);

    final newNickname = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Change Nickname'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'New nickname'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                Navigator.of(dialogContext).pop(value.isEmpty ? null : value);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (newNickname == null) {
      return;
    }

    try {
      await ref.read(profileProvider.notifier).changeNickname(newNickname);
      ref.read(nicknameProvider.notifier).state = newNickname;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nickname has been updated.')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to change nickname: $error')),
      );
    }
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label),
        trailing: Text(value, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}

