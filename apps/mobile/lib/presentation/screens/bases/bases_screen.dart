import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../providers/app_providers.dart';

class BasesScreen extends ConsumerWidget {
  const BasesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final territoryAsync = ref.watch(territoryListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Territory Management'),
        actions: [
          IconButton(
            tooltip: 'Combat Reports',
            onPressed: () => context.push(AppRoute.battleLogs),
            icon: const Icon(Icons.receipt_long),
          ),
          IconButton(
            tooltip: 'Settings & Profile',
            onPressed: () => context.push(AppRoute.profile),
            icon: const Icon(Icons.person),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(territoryListProvider.notifier).refresh(),
        child: territoryAsync.when(
          data: (data) {
            final home = data['home'] as Map<String, dynamic>?;
            final outposts = (data['outposts'] as List<dynamic>? ?? const <dynamic>[])
                .whereType<Map<String, dynamic>>()
                .toList(growable: false);

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _TerritorySection(
                  title: 'Home Territory',
                  emptyLabel: 'No home territory found.',
                  children: [
                    if (home != null)
                      _TerritoryCard(
                        name: (home['name'] as String?) ?? 'Home Territory',
                        subtitle:
                            '${(home['hexCount'] as num?)?.toInt() ?? 0} hexes • Center ${(home['centerH3Index'] as String?) ?? '-'}',
                        actionLabel: 'Center on map',
                        onActionPressed: () {
                          final centerH3Index = (home['centerH3Index'] as String?)?.trim();
                          if (centerH3Index == null || centerH3Index.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Center hex is not available yet.')),
                            );
                            return;
                          }
                          context.push(AppRoute.mapWithFocus(centerH3Index));
                        },
                        onRenamePressed: () => _renameTerritory(context, ref, home),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _TerritorySection(
                  title: 'Outpost Territories',
                  emptyLabel: 'No outposts found.',
                  children: [
                    for (final outpost in outposts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _TerritoryCard(
                          name: (outpost['name'] as String?) ?? 'Outpost',
                          subtitle:
                              '${(outpost['hexCount'] as num?)?.toInt() ?? 0} hexes • Representative ${(outpost['representativeH3Index'] as String?) ?? '-'}',
                          onRenamePressed: () => _renameTerritory(context, ref, outpost),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                            onPressed: () => context.push(AppRoute.battleLogs),
                        icon: const Icon(Icons.receipt_long),
                        label: const Text('Combat Reports'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                            onPressed: () => context.push(AppRoute.profile),
                        icon: const Icon(Icons.person),
                        label: const Text('Settings & Profile'),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Failed to load territories: $error'),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _renameTerritory(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> territory,
  ) async {
    final territoryId = (territory['id'] as String?)?.trim();
    if (territoryId == null || territoryId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to identify territory ID.')),
      );
      return;
    }

    final currentName = (territory['name'] as String?) ?? '';
    final controller = TextEditingController(text: currentName);

    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Rename Territory'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'New territory name'),
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
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (newName == null) {
      return;
    }

    try {
      await ref.read(territoryListProvider.notifier).renameTerritory(
            territoryId: territoryId,
            name: newName,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Territory name was updated.')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to rename territory: $error')),
      );
    }
  }
}

class _TerritorySection extends StatelessWidget {
  const _TerritorySection({
    required this.title,
    required this.emptyLabel,
    required this.children,
  });

  final String title;
  final String emptyLabel;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final isEmpty = children.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (isEmpty)
          Text(emptyLabel)
        else
          ...children,
      ],
    );
  }
}

class _TerritoryCard extends StatelessWidget {
  const _TerritoryCard({
    required this.name,
    required this.subtitle,
    required this.onRenamePressed,
    this.actionLabel,
    this.onActionPressed,
  });

  final String name;
  final String subtitle;
  final VoidCallback onRenamePressed;
  final String? actionLabel;
  final VoidCallback? onActionPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(name, style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: 'Rename',
                  onPressed: onRenamePressed,
                  icon: const Icon(Icons.edit),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(subtitle),
            if (actionLabel != null && onActionPressed != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: onActionPressed,
                icon: const Icon(Icons.center_focus_strong),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


