import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/game_session_controller.dart';
import '../widgets/section_card.dart';

class TerritoryScreen extends StatelessWidget {
  const TerritoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<GameSessionController>(
      builder: (context, controller, _) {
        final home = controller.territories.home;
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SectionCard(
                title: 'Home territory',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(home.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text('${home.hexCount} connected hexagons · Center: ${home.centerH3Index ?? 'none'}'),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: home.centerH3Index == null
                            ? null
                            : () {
                                controller.selectHex(home.centerH3Index!);
                                controller.selectTab(0);
                              },
                        icon: const Icon(Icons.center_focus_strong_rounded),
                        label: const Text('Center map on Center'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Outpost territories',
                child: Column(
                  children: [
                    for (final territory in controller.territories.outposts)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.fort_rounded),
                        title: Text(territory.name),
                        subtitle: Text('${territory.hexCount} hexagons · ${territory.representativeH3Index ?? 'n/a'}'),
                        trailing: IconButton(
                          onPressed: () async {
                            await controller.renameTerritory(
                              territoryId: territory.id,
                              name: '${territory.name} ✎',
                            );
                          },
                          icon: const Icon(Icons.edit_rounded),
                        ),
                      ),
                    if (controller.territories.outposts.isEmpty) const Text('No outposts yet'),
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


