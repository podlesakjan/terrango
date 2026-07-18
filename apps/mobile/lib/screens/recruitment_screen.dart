import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/game_session_controller.dart';
import '../widgets/radar_visual.dart';
import '../widgets/section_card.dart';
import '../widgets/status_pill.dart';

class RecruitmentScreen extends StatefulWidget {
  const RecruitmentScreen({super.key});

  @override
  State<RecruitmentScreen> createState() => _RecruitmentScreenState();
}

class _RecruitmentScreenState extends State<RecruitmentScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (mounted) {
        context.read<GameSessionController>().pushMockRecruitment();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GameSessionController>(
      builder: (context, controller, _) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              StatusPill(
                label: 'BLE RADAR · ${controller.profile.scannedDevices} scanned devices',
                icon: Icons.bluetooth_searching_rounded,
              ),
              const SizedBox(height: 16),
              const Center(child: RadarVisual()),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Automatic recruitment feed',
                trailing: TextButton.icon(
                  onPressed: controller.pushMockRecruitment,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Simulate scan'),
                ),
                child: Column(
                  children: [
                    for (final item in controller.recruitmentFeed)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          item.success ? Icons.check_circle_rounded : Icons.do_not_disturb_on_rounded,
                          color: item.success ? const Color(0xFF8DF5C8) : Colors.redAccent,
                        ),
                        title: Text(item.message),
                        subtitle: Text('${_relativeTime(item.timestamp)} · ${item.bluetoothId}'),
                      ),
                    if (controller.recruitmentFeed.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Waiting for Bluetooth signal...'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Recruitment totals',
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _Metric(label: 'Reserve BS', value: '${controller.reserveBs}'),
                    _Metric(label: 'Reserve count', value: '${controller.reserveCount}'),
                    _Metric(label: 'Scanned', value: '${controller.profile.scannedDevices}'),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _relativeTime(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

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

