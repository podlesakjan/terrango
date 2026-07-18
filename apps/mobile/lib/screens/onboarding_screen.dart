import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/game_session_controller.dart';
import '../widgets/section_card.dart';
import '../widgets/status_pill.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _nicknameController = TextEditingController(text: 'Válečník99');
  final _idTokenController = TextEditingController(text: 'eyJhbGciOiJSUzI1NiIs...');

  @override
  void dispose() {
    _nicknameController.dispose();
    _idTokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<GameSessionController>();
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 16),
            const StatusPill(
              label: 'FIRST LAUNCH · GEO-MMO STRATEGY',
              icon: Icons.rocket_launch_rounded,
            ),
            const SizedBox(height: 24),
            Text(
              'Terrango',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Založ si účet, připoj GPS / BLE hra a okamžitě vstup na taktickou mapu.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.white70,
                  ),
            ),
            const SizedBox(height: 24),
            SectionCard(
              title: 'Quick registration',
              child: Column(
                children: [
                  TextField(
                    controller: _nicknameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nickname',
                      prefixIcon: Icon(Icons.person_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _idTokenController,
                    decoration: const InputDecoration(
                      labelText: 'ID token',
                      prefixIcon: Icon(Icons.key_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        await controller.register(
                          _nicknameController.text.trim().isEmpty
                              ? 'Warrior99'
                              : _nicknameController.text.trim(),
                          idToken: _idTokenController.text.trim(),
                        );
                      },
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('Start immediately'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'What is enabled',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _Bullet('Dark futuristic Mapbox-ready tactical map'),
                  SizedBox(height: 8),
                  _Bullet('Automated BLE recruitment + real-time radar feed'),
                  SizedBox(height: 8),
                  _Bullet('Barracks, territory management, battle logs and profile'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Current mock state',
              child: Consumer<GameSessionController>(
                builder: (context, state, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Connection: ${state.connectionStatus}'),
                      const SizedBox(height: 8),
                      Text('Reserve: ${state.reserveCount} soldiers / ${state.reserveBs} BS'),
                      const SizedBox(height: 8),
                      Text('Patrols: ${state.patrolCount} deployed soldiers'),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Icon(Icons.brightness_1, size: 8, color: Color(0xFF4FC3F7)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
      ],
    );
  }
}

