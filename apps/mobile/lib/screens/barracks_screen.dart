import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/game_models.dart';
import '../state/game_session_controller.dart';
import '../widgets/section_card.dart';

class BarracksScreen extends StatelessWidget {
  const BarracksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<GameSessionController>(
      builder: (context, controller, _) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SectionCard(
                title: 'Reserve summary',
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _Summary(label: 'Total BS', value: '${controller.reserveBs}'),
                    _Summary(label: 'Units ready', value: '${controller.reserveCount}'),
                    _Summary(label: 'Patrols', value: '${controller.patrolCount}'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Reserve',
                child: Column(
                  children: [
                    for (final bucket in controller.barracks.reserves)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(bucket.type.icon),
                        title: Text('${bucket.type.label} · ${bucket.rarity.label}'),
                        subtitle: Text(bucket.skill == null ? 'No skill' : bucket.skill!),
                        trailing: Text('${bucket.totalBs} BS'),
                      ),
                    if (controller.barracks.reserves.isEmpty) const Text('No reserve units'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Patrols',
                child: Column(
                  children: [
                    for (final patrol in controller.barracks.patrols)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.map_rounded),
                        title: Text(patrol.territoryName),
                        subtitle: Text(patrol.h3Index),
                        trailing: Text('${patrol.soldierCount} · ${patrol.totalBs} BS'),
                      ),
                    if (controller.barracks.patrols.isEmpty) const Text('No patrol assignments'),
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

class _Summary extends StatelessWidget {
  const _Summary({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.white70)),
        const SizedBox(height: 6),
        Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      ],
    );
  }
}


