import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../providers/app_providers.dart';

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nickname = ref.watch(nicknameProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Terrango - Onboarding')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Nickname',
                  hintText: 'Zadej prezdivku',
                ),
                onChanged: (value) =>
                    ref.read(nicknameProvider.notifier).state = value.trim(),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: nickname.isEmpty
                    ? null
                    : () {
                        context.go(AppRoute.map);
                      },
                icon: const Icon(Icons.rocket_launch),
                label: const Text('Rychla registrace a start'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
