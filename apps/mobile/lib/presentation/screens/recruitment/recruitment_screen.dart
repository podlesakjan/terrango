import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';

class RecruitmentScreen extends ConsumerStatefulWidget {
  const RecruitmentScreen({super.key});

  @override
  ConsumerState<RecruitmentScreen> createState() => _RecruitmentScreenState();
}

class _RecruitmentScreenState extends ConsumerState<RecruitmentScreen>
    with SingleTickerProviderStateMixin {
  final List<_RecruitFeedEntry> _feed = <_RecruitFeedEntry>[];
  final Set<String> _seenBluetoothIds = <String>{};
  final Map<String, Map<String, dynamic>> _pendingRecruitments =
      <String, Map<String, dynamic>>{};

  StreamSubscription<List<ScanResult>>? _scanResultsSub;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSub;
  StreamSubscription<Map<String, dynamic>>? _socketEventsSub;
  late final AnimationController _radarController;

  bool _isScanning = false;
  int _sessionRecruitedCount = 0;
  int _sessionRecruitedBs = 0;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _bindSocket();
    _setupBluetoothAndScan();
  }

  @override
  void dispose() {
    _scanResultsSub?.cancel();
    _socketEventsSub?.cancel();
    _adapterStateSub?.cancel();
    _radarController.dispose();
    unawaited(FlutterBluePlus.stopScan());
    super.dispose();
  }

  void _bindSocket() {
    final controller = ref.read(gameSocketEventControllerProvider);
    controller.connect();

    _socketEventsSub = controller.events.listen((envelope) {
      final event = envelope['event'] as String?;
      final payload = envelope['data'];
      if (event == 'recruit_result' && payload is Map<String, dynamic>) {
        final message = (payload['message'] as String?)?.trim();
        final status = (payload['status'] as String?)?.toUpperCase();
        final bluetoothId = (payload['bluetoothId'] as String?)?.trim() ?? 'UNKNOWN';
        final recruitedSoldier = _pendingRecruitments.remove(bluetoothId);

        if (mounted) {
          setState(() {
            if (status == 'SUCCESS' && recruitedSoldier != null) {
              _sessionRecruitedCount += 1;
              _sessionRecruitedBs += (recruitedSoldier['bs'] as num?)?.toInt() ?? 0;
            }
            _addFeedEntryWithoutSetState(
              message: message?.isNotEmpty == true
                  ? message!
                  : _fallbackRecruitMessage(
                      status: status,
                      bluetoothId: bluetoothId,
                      recruitedSoldier: recruitedSoldier,
                    ),
              isError: status == 'SKIPPED',
            );
          });
        }
        return;
      }

      if (event == 'army_update' && payload is Map<String, dynamic>) {
        if (mounted) {
          ref.invalidate(armyOverviewProvider);
        }
      }
    });
  }

  Future<void> _setupBluetoothAndScan() async {
    if (await FlutterBluePlus.isSupported == false) {
      setState(() =>
          _addFeedEntryWithoutSetState(message: 'Recruitment hardware not available.', isError: true));
      return;
    }

    _adapterStateSub = FlutterBluePlus.adapterState.listen((state) {
      if (mounted) {
        if (state == BluetoothAdapterState.on) {
          _startScan();
        } else {
          _stopScan(showMessage: false);
          if (state == BluetoothAdapterState.off) {
            setState(() => _addFeedEntryWithoutSetState(
                  message: 'Recruitment hardware is disabled. Please enable Bluetooth.',
                  isError: true,
                ));
          }
        }
      }
    });

    // This will request the user to turn on bluetooth if it's off
    await FlutterBluePlus.turnOn();
  }



  Future<void> _startScan() async {
    if (_isScanning) {
      return;
    }

    try {
      await FlutterBluePlus.stopScan();
      _scanResultsSub?.cancel();
      _scanResultsSub = FlutterBluePlus.scanResults.listen(_onScanResults);
      await FlutterBluePlus.startScan(timeout: const Duration(minutes: 30));
      if (!mounted) {
        return;
      }
      setState(() {
        _isScanning = true;
        _addFeedEntryWithoutSetState(
            message: 'Recruitment scanner is online. Searching for signals.', isError: false);
      });
    } catch (error) {
      setState(
          () => _addFeedEntryWithoutSetState(message: 'Recruitment scanner failed to start.', isError: true));
    }
  }

  Future<void> _stopScan({bool showMessage = true}) async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {
      // Ignore stop-scan errors.
    }
    if (!mounted) {
      return;
    }
    final wasScanning = _isScanning;
    setState(() {
      _isScanning = false;
    });
    if (wasScanning && showMessage) {
      setState(() => _addFeedEntryWithoutSetState(message: 'Recruitment scanner is offline.', isError: false));
    }
  }

  void _onScanResults(List<ScanResult> results) {
    if (results.isEmpty || !mounted) {
      return;
    }

    final controller = ref.read(gameSocketEventControllerProvider);
    var changed = false;
    final newEntries = <_RecruitFeedEntry>[];

    for (final result in results) {
      final bluetoothId = result.device.remoteId.str.trim();
      if (bluetoothId.isEmpty || _seenBluetoothIds.contains(bluetoothId)) {
        continue;
      }
      changed = true;

      _seenBluetoothIds.add(bluetoothId);
      final calculatedSoldier = _calculateSoldier(
        bluetoothId: bluetoothId,
        rssi: result.rssi,
      );
      _pendingRecruitments[bluetoothId] = calculatedSoldier;

      controller.sendRecruitDevice(
        bluetoothId: bluetoothId,
        calculatedSoldier: calculatedSoldier,
      );

      newEntries.add(_RecruitFeedEntry(
        createdAt: DateTime.now().toUtc(),
        message: _detectedRecruitMessage(
          bluetoothId: bluetoothId,
          calculatedSoldier: calculatedSoldier,
        ),
        isError: false,
      ));
    }

    if (changed) {
      setState(() {
        _feed.insertAll(0, newEntries);
        if (_feed.length > 150) {
          _feed.removeRange(150, _feed.length);
        }
      });
    }
  }

  Map<String, dynamic> _calculateSoldier({
    required String bluetoothId,
    required int rssi,
  }) {
    final hash = bluetoothId.codeUnits.fold<int>(0, (a, b) => ((a * 31) + b) & 0x7fffffff);
    final type = hash.isEven ? 'WARRIOR' : 'SUPPORT';

    final absRssi = rssi.abs();
    final rarity = switch (absRssi) {
      <= 55 => 'PROTOTYPE',
      <= 75 => 'ADVANCED',
      _ => 'STANDARD',
    };

    final baseBs = switch (rarity) {
      'PROTOTYPE' => 220,
      'ADVANCED' => 140,
      _ => 60,
    };

    final signalBoost = math.max(0, 100 - absRssi);
    final bs = baseBs + signalBoost;
    final signal = switch (absRssi) {
      <= 55 => 'Strong signal',
      <= 75 => 'Medium signal',
      _ => 'Weak signal',
    };

    final skill = type == 'SUPPORT'
        ? switch (hash % 3) {
            0 => 'SCOUT',
            1 => 'JAMMER',
            _ => 'DECOY',
          }
        : null;

    return {
      'type': type,
      'rarity': rarity,
      'bs': bs,
      'skill': skill,
      'signal': signal,
    };
  }

  String _fallbackRecruitMessage({
    required String? status,
    required String bluetoothId,
    required Map<String, dynamic>? recruitedSoldier,
  }) {
    if (status == 'SUCCESS') {
      return _successRecruitMessage(recruitedSoldier);
    }
    if (status == 'SKIPPED') {
      return 'Signal already processed. Skipping analysis. 🚫';
    }
    return 'Recruitment signal processed.';
  }

  String _detectedRecruitMessage({
    required String bluetoothId,
    required Map<String, dynamic> calculatedSoldier,
  }) {
    final bs = (calculatedSoldier['bs'] as num?)?.toInt() ?? 0;
    final signal = (calculatedSoldier['signal'] as String?) ?? 'Signal';
    final unitLabel = _unitLabel(calculatedSoldier);
    return '$signal detected -> New potential recruit found: $unitLabel ($bs BS).';
  }

  String _successRecruitMessage(
    Map<String, dynamic>? recruitedSoldier,
  ) {
    if (recruitedSoldier == null) {
      return 'Recruitment completed.';
    }

    final bs = (recruitedSoldier['bs'] as num?)?.toInt() ?? 0;
    return '${(recruitedSoldier['signal'] as String?) ?? 'Signal'} detected -> Recruited ${_unitLabel(recruitedSoldier)} ($bs BS).';
  }

  String _unitLabel(Map<String, dynamic> soldier) {
    final type = (soldier['type'] as String? ?? 'UNIT').toUpperCase();
    final rarity = (soldier['rarity'] as String? ?? 'STANDARD').toLowerCase();
    final rarityLabel = rarity.isEmpty
        ? 'Standard'
        : '${rarity[0].toUpperCase()}${rarity.substring(1)}';
    if (type == 'SUPPORT') {
      final skill = (soldier['skill'] as String? ?? 'Support').toLowerCase();
      final skillLabel = skill.isEmpty
          ? 'Support'
          : '${skill[0].toUpperCase()}${skill.substring(1)}';
      return '$skillLabel Support, $rarityLabel';
    }
    return 'Warrior, $rarityLabel';
  }

  void _addFeedEntryWithoutSetState({required String message, required bool isError}) {
    if (!mounted) {
      return;
    }
    _feed.insert(
      0,
      _RecruitFeedEntry(
        createdAt: DateTime.now().toUtc(),
        message: message,
        isError: isError,
      ),
    );
    if (_feed.length > 150) {
      _feed.removeRange(150, _feed.length);
    }
  }

  String _timeAgo(DateTime createdAt) {
    final seconds = DateTime.now().toUtc().difference(createdAt).inSeconds;
    if (seconds < 60) {
      return '${seconds}s ago';
    }
    final minutes = seconds ~/ 60;
    if (minutes < 60) {
      return '${minutes}m ago';
    }
    final hours = minutes ~/ 60;
    return '${hours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    final armyOverview = ref.watch(armyOverviewProvider).valueOrNull;
    final reserveCount = armyOverview?.reserveCount ?? 0;
    final reserveBs = armyOverview?.reserveBs ?? 0;
    final radarSize = MediaQuery.of(context).size.width / 3;

    return Scaffold(
      appBar: AppBar(title: const Text('Recruitment Radar')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: SizedBox(
                  width: radarSize,
                  height: radarSize,
                  child: AnimatedBuilder(
                    animation: _radarController,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _RadarPainter(
                          sweepAngle: _radarController.value * math.pi * 2,
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xAA0B0F16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_isScanning ? 'Automatic recruitment is active' : 'Automatic recruitment is paused'),
                      const SizedBox(height: 6),
                      Text('Scanned devices this session: ${_seenBluetoothIds.length}'),
                      Text('Recruited this session: $_sessionRecruitedCount units / $_sessionRecruitedBs BS'),
                      Text('Reserve overview: $reserveCount units / $reserveBs BS'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const SizedBox(height: 12),
              Text(
                'Recruitment feed',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _feed.isEmpty
                    ? const Center(
                        child: Text('No recruitment events yet. Keep scanning nearby devices.'),
                      )
                    : ListView.separated(
                        itemCount: _feed.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = _feed[index];
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              item.isError ? Icons.error_outline : Icons.radar,
                              color: item.isError
                                  ? Theme.of(context).colorScheme.error
                                  : Theme.of(context).colorScheme.primary,
                            ),
                            title: Text(item.message),
                            subtitle: Text(_timeAgo(item.createdAt)),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecruitFeedEntry {
  const _RecruitFeedEntry({
    required this.createdAt,
    required this.message,
    required this.isError,
  });

  final DateTime createdAt;
  final String message;
  final bool isError;
}

class _RadarPainter extends CustomPainter {
  const _RadarPainter({required this.sweepAngle});

  final double sweepAngle;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;

    final backgroundPaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFF071018), Color(0xFF0B0F16)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, backgroundPaint);

    final gridPaint = Paint()
      ..color = const Color(0x5500BFA5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var i = 1; i <= 4; i++) {
      canvas.drawCircle(center, radius * i / 4, gridPaint);
    }
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      gridPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      gridPaint,
    );

    final sweepRect = Rect.fromCircle(center: center, radius: radius);
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: sweepAngle - 0.35,
        endAngle: sweepAngle,
        colors: const [Color(0x0000BFA5), Color(0x9900E5C1)],
      ).createShader(sweepRect);
    canvas.drawCircle(center, radius, sweepPaint);

    final beamPaint = Paint()
      ..color = const Color(0xFF49F5D0)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final beamEnd = Offset(
      center.dx + math.cos(sweepAngle) * radius,
      center.dy + math.sin(sweepAngle) * radius,
    );
    canvas.drawLine(center, beamEnd, beamPaint);
    canvas.drawCircle(center, 4, Paint()..color = const Color(0xFF49F5D0));
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    return oldDelegate.sweepAngle != sweepAngle;
  }
}
