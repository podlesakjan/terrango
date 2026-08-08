import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/hex_tile.dart';
import '../../providers/app_providers.dart';

class MapScreen extends ConsumerWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hexesAsync = ref.watch(visibleHexesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tactical Map')),
      body: hexesAsync.when(
        data: (hexes) => ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: hexes.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final hex = hexes[index];
            return Card(
              child: ListTile(
                title: Text(hex.h3Index),
                subtitle: Text(_stateLabel(hex.state)),
                trailing: Icon(
                  hex.isCenter
                      ? Icons.workspace_premium
                      : Icons.hexagon_outlined,
                ),
              ),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Nepodarilo se nacist mapu: $error'),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: Row(
          children: const [
            Expanded(child: _QuickActionButton(label: 'RECRUITMENT')),
            SizedBox(width: 8),
            Expanded(child: _QuickActionButton(label: 'BARRACKS')),
            SizedBox(width: 8),
            Expanded(child: _QuickActionButton(label: 'BASES')),
          ],
        ),
      ),
    );
  }

  static String _stateLabel(HexState state) {
    return switch (state) {
      HexState.free => 'FREE',
      HexState.owned => 'OWNED',
      HexState.enemy => 'ENEMY',
    };
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(onPressed: () {}, child: Text(label));
  }
}
