import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/army_overview.dart';
import '../../providers/app_providers.dart';

class BarracksScreen extends ConsumerWidget {
  const BarracksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final armyAsync = ref.watch(armyOverviewProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Barracks'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.read(armyOverviewProvider.notifier).refreshFromBarracks(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: armyAsync.when(
        data: (army) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SummaryCard(army: army),
              const SizedBox(height: 20),
              Text('Reserve', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (army.reserves.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No reserve units available yet. Open Recruitment to scan nearby devices.'),
                  ),
                )
              else
                ...army.reserves.map((bucket) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ReserveBucketCard(bucket: bucket),
                    )),
              const SizedBox(height: 20),
              Text('Patrols', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (army.patrols.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No patrols deployed on the map yet.'),
                  ),
                )
              else
                ...army.patrols.map((patrol) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PatrolCard(patrol: patrol),
                    )),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Failed to load barracks: $error')),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.army});

  final ArmyOverview army;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reserve combat strength', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '${army.reserveBs} BS',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _SummaryChip(label: 'Reserve units', value: '${army.reserveCount}'),
                _SummaryChip(label: 'Warriors', value: '${army.warriorCount}'),
                _SummaryChip(label: 'Support', value: '${army.supportCount}'),
                _SummaryChip(label: 'Patrols', value: '${army.patrolCount}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x3300BFA5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

class _ReserveBucketCard extends StatelessWidget {
  const _ReserveBucketCard({required this.bucket});

  final SoldierBucketSummary bucket;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(_iconForBucket(bucket)),
        title: Text('${_rarityLabel(bucket.rarity)} ${_typeLabel(bucket)}'),
        subtitle: Text('Count ${bucket.count} • Avg ${bucket.averageBs} BS'),
        trailing: Text(
          '${bucket.totalBs} BS',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }

  IconData _iconForBucket(SoldierBucketSummary bucket) {
    if (bucket.type == 'WARRIOR') {
      return Icons.military_tech_outlined;
    }
    return switch (bucket.skill) {
      'SCOUT' => Icons.remove_red_eye_outlined,
      'JAMMER' => Icons.flash_on_outlined,
      'DECOY' => Icons.track_changes,
      _ => Icons.settings_input_antenna,
    };
  }

  String _typeLabel(SoldierBucketSummary bucket) {
    if (bucket.type == 'SUPPORT' && bucket.skill != null) {
      return 'Support • ${_capitalized(bucket.skill!)}';
    }
    return bucket.type == 'WARRIOR' ? 'Warrior' : 'Support';
  }

  String _rarityLabel(String rarity) => _capitalized(rarity);

  String _capitalized(String value) {
    final normalized = value.toLowerCase();
    return normalized.isEmpty
        ? value
        : '${normalized[0].toUpperCase()}${normalized.substring(1)}';
  }
}

class _PatrolCard extends StatelessWidget {
  const _PatrolCard({required this.patrol});

  final PatrolSummary patrol;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(patrol.territoryName, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(patrol.h3Index, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: Text('${patrol.soldierCount} soldiers')),
                Text('${patrol.totalBs} BS'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

