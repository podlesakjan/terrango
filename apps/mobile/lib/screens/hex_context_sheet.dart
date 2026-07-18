import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/game_models.dart';
import '../state/game_session_controller.dart';
import '../widgets/section_card.dart';
import '../widgets/status_pill.dart';

class HexContextSheet extends StatefulWidget {
  const HexContextSheet({super.key, required this.hexDetail});

  final HexDetail hexDetail;

  @override
  State<HexContextSheet> createState() => _HexContextSheetState();
}

class _HexContextSheetState extends State<HexContextSheet> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.hexDetail.territory?.name ?? 'New Territory',
  );

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<GameSessionController>();
    final hex = widget.hexDetail;
    final isCurrent = controller.currentLocationH3Index == hex.h3Index;

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF08101E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                Center(
                  child: Container(
                    width: 56,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        hex.h3Index,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    StatusPill(
                      label: hex.state.name.toUpperCase(),
                      icon: switch (hex.state) {
                        HexOwnershipState.free => Icons.hexagon_outlined,
                        HexOwnershipState.owned => Icons.shield_rounded,
                        HexOwnershipState.enemy => Icons.warning_rounded,
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (hex.state == HexOwnershipState.free) _buildFree(context, controller, hex),
                if (hex.state == HexOwnershipState.owned) _buildOwned(context, controller, hex),
                if (hex.state == HexOwnershipState.enemy) _buildEnemy(context, controller, hex, isCurrent),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFree(BuildContext context, GameSessionController controller, HexDetail hex) {
    return SectionCard(
      title: 'Free hexagon',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Territory name',
              prefixIcon: Icon(Icons.badge_rounded),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Occupy territory at your physical location and create a new territorial unit if needed.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                await controller.occupyHex(
                  h3Index: hex.h3Index,
                  territoryName: _nameController.text.trim().isEmpty ? 'Cabin Outpost' : _nameController.text.trim(),
                  garrisonComposition: const [
                    ArmyBucket(
                      type: ArmyUnitType.warrior,
                      rarity: SoldierRarity.standard,
                      count: 3,
                      totalBs: 600,
                    ),
                  ],
                );
                if (mounted) Navigator.of(context).pop();
              },
              icon: const Icon(Icons.flag_rounded),
              label: const Text('Occupy territory'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOwned(BuildContext context, GameSessionController controller, HexDetail hex) {
    final garrison = hex.garrison;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCard(
          title: 'Territory',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hex.territory?.name ?? 'Territory',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text('Type: ${hex.territory?.type.apiName ?? 'HOME'}'),
              const SizedBox(height: 8),
              Text('Background bonus: +${hex.backgroundBonusPercent}%'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Garrison composition',
          child: Column(
            children: [
              if (garrison != null)
                for (final bucket in garrison.composition)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(bucket.type.icon),
                    title: Text('${bucket.type.label} · ${bucket.rarity.label}'),
                    subtitle: Text(bucket.skill == null ? 'No skill' : bucket.skill!),
                    trailing: Text('${bucket.count} / ${bucket.totalBs} BS'),
                  )
              else
                const Text('No garrison data'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Reserve snapshot',
          child: Column(
            children: [
              for (final bucket in hex.reserve)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(bucket.type.icon),
                  title: Text('${bucket.type.label} · ${bucket.rarity.label}'),
                  subtitle: Text(bucket.skill == null ? 'No skill' : bucket.skill!),
                  trailing: Text('${bucket.count} / ${bucket.totalBs} BS'),
                ),
              if (hex.reserve.isEmpty) const Text('Reserve snapshot empty'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await controller.changeCenter(territoryId: hex.territory?.id ?? 'home-id', h3Index: hex.h3Index);
                  if (mounted) Navigator.of(context).pop();
                },
                icon: const Icon(Icons.emoji_events_rounded),
                label: const Text('Set as Center'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await controller.garrisonModify(
                    h3Index: hex.h3Index,
                    action: 'DEPLOY',
                    composition: const [
                      ArmyBucket(type: ArmyUnitType.warrior, rarity: SoldierRarity.standard, count: 1, totalBs: 200),
                    ],
                  );
                  if (mounted) Navigator.of(context).pop();
                },
                icon: const Icon(Icons.upload_rounded),
                label: const Text('Deploy'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              await controller.garrisonModify(
                h3Index: hex.h3Index,
                action: 'WITHDRAW',
                composition: const [
                  ArmyBucket(type: ArmyUnitType.support, rarity: SoldierRarity.standard, skill: 'SCOUT', count: 1, totalBs: 50),
                ],
              );
              if (mounted) Navigator.of(context).pop();
            },
            icon: const Icon(Icons.download_rounded),
            label: const Text('Withdraw'),
          ),
        ),
      ],
    );
  }

  Widget _buildEnemy(BuildContext context, GameSessionController controller, HexDetail hex, bool isCurrent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCard(
          title: 'Enemy intelligence',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Owner: ${hex.ownerName ?? 'Unknown'}'),
              const SizedBox(height: 8),
              Text('Fog of war: ${hex.fogOfWarLabel ?? '??? BS'}'),
              const SizedBox(height: 8),
              Text('Attack available only when physically standing in the hexagon.'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await controller.scoutHex(targetH3Index: hex.h3Index);
                  if (mounted) Navigator.of(context).pop();
                },
                icon: const Icon(Icons.remove_red_eye_rounded),
                label: const Text('Scout'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: isCurrent
                    ? () async {
                        await controller.attackHex(
                          targetH3Index: hex.h3Index,
                          attackerComposition: const [
                            ArmyBucket(type: ArmyUnitType.warrior, rarity: SoldierRarity.standard, count: 4, totalBs: 800),
                          ],
                        );
                        if (mounted) Navigator.of(context).pop();
                      }
                    : null,
                icon: const Icon(Icons.bolt_rounded),
                label: const Text('ATTACK!'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}


