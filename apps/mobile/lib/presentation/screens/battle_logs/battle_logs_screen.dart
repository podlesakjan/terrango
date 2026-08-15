import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';

class BattleLogsScreen extends ConsumerWidget {
  const BattleLogsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(battleLogsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Combat Reports'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.read(battleLogsProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(battleLogsProvider.notifier).refresh(),
        child: logsAsync.when(
          data: (logs) {
            if (logs.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 160),
                  Center(child: Text('No combat reports yet.')),
                ],
              );
            }

            final clashes = logs
                .where((log) => (log['type'] as String? ?? '').toUpperCase() == 'ATTACK')
                .toList(growable: false);
            final spyReports = logs
                .where((log) => (log['type'] as String? ?? '').toUpperCase() == 'SCOUT')
                .toList(growable: false);

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SectionHeader(
                  title: 'Clash History',
                  subtitle: 'Victories are shown in green, defeats in red. Opponent losses stay hidden.',
                ),
                const SizedBox(height: 8),
                if (clashes.isEmpty)
                  const _EmptySectionCard(message: 'No battles recorded yet.')
                else
                  ...clashes.map((log) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _CombatLogCard(log: log),
                      )),
                const SizedBox(height: 12),
                const _SectionHeader(
                  title: 'Spy Reports',
                  subtitle: 'Scouting results from your Support units.',
                ),
                const SizedBox(height: 8),
                if (spyReports.isEmpty)
                  const _EmptySectionCard(message: 'No scouting reports recorded yet.')
                else
                  ...spyReports.map((log) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _CombatLogCard(log: log),
                      )),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [Text('Failed to load combat reports: $error')],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _EmptySectionCard extends StatelessWidget {
  const _EmptySectionCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(message),
      ),
    );
  }
}

class _CombatLogCard extends StatelessWidget {
  const _CombatLogCard({required this.log});

  final Map<String, dynamic> log;

  @override
  Widget build(BuildContext context) {
    final type = (log['type'] as String? ?? 'UNKNOWN').toUpperCase();
    final result = (log['result'] as String? ?? 'UNKNOWN').toUpperCase();
    final timestamp = (log['timestamp'] as String?) ?? '';
    final h3Index = (log['h3Index'] as String?) ?? '-';

    final isVictory = result == 'VICTORY' || result == 'SUCCESS';
    final resultColor = isVictory
        ? Colors.greenAccent
        : result == 'DEFEAT' || result == 'JAMMED'
            ? Colors.redAccent
            : Theme.of(context).colorScheme.primary;

    final details = type == 'ATTACK'
        ? 'Dead: ${(log['myDead'] as num?)?.toInt() ?? 0} • Survivors: ${_survivorCount(log['mySurvivors'])}'
        : 'Revealed BS: ${(log['revealedBs'] as num?)?.toInt() ?? 0}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 6,
              height: 84,
              decoration: BoxDecoration(
                color: resultColor,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          type == 'ATTACK' ? 'Battle report' : 'Scout report',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        result,
                        style: TextStyle(color: resultColor, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(h3Index),
                  const SizedBox(height: 6),
                  Text(timestamp),
                  const SizedBox(height: 8),
                  Text(details),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _survivorCount(dynamic survivors) {
    if (survivors is List) {
      return survivors.length;
    }
    if (survivors is num) {
      return survivors.toInt();
    }
    return 0;
  }
}


