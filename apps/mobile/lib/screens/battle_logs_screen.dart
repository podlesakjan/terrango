import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/game_models.dart';
import '../state/game_session_controller.dart';
import '../widgets/section_card.dart';

class BattleLogsScreen extends StatelessWidget {
  const BattleLogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<GameSessionController>(
      builder: (context, controller, _) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SectionCard(
                title: 'Timeline',
                child: Column(
                  children: [
                    for (final log in controller.battleLogs)
                      _LogCard(log: log),
                    if (controller.battleLogs.isEmpty) const Text('No battle history yet'),
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

class _LogCard extends StatelessWidget {
  const _LogCard({required this.log});

  final BattleLogEntry log;

  @override
  Widget build(BuildContext context) {
    final isVictory = log.result == BattleResult.victory || log.result == BattleResult.success;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isVictory ? const Color(0x3310B981) : Colors.redAccent.withValues(alpha: 0.18),
            ),
            child: Icon(
              log.type == BattleLogType.attack ? Icons.flash_on_rounded : Icons.travel_explore_rounded,
              color: isVictory ? const Color(0xFF8DF5C8) : Colors.redAccent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${log.type.name.toUpperCase()} · ${log.result.name.toUpperCase()}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(log.h3Index, style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 6),
                Text(_details(log), style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 6),
                Text(_formatDate(log.timestamp), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white54)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _details(BattleLogEntry log) {
    if (log.type == BattleLogType.attack) {
      return 'My dead: ${log.myDead ?? 0} · Survivors: ${log.mySurvivors ?? 0}';
    }
    return 'Revealed BS: ${log.revealedBs ?? 0}';
  }

  String _formatDate(DateTime timestamp) {
    final local = timestamp.toLocal();
    return '${local.year}-${_two(local.month)}-${_two(local.day)} ${_two(local.hour)}:${_two(local.minute)}';
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}


