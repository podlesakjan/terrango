import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';

class BackgroundTrackingServiceController {
  BackgroundTrackingServiceController({FlutterBackgroundService? service})
    : _service = service ?? FlutterBackgroundService();

  final FlutterBackgroundService _service;
  bool _configured = false;

  Future<void> setEnabled(bool enabled) async {
    if (!Platform.isAndroid) {
      return;
    }

    await _configureIfNeeded();
    final isRunning = await _service.isRunning();

    if (enabled) {
      if (!isRunning) {
        await _service.startService();
      }
      _service.invoke('setAsForeground');
      return;
    }

    if (isRunning) {
      _service.invoke('stopService');
    }
  }

  Future<void> _configureIfNeeded() async {
    if (_configured || !Platform.isAndroid) {
      return;
    }

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: backgroundTrackingServiceEntryPoint,
        autoStart: false,
        autoStartOnBoot: false,
        isForegroundMode: true,
        initialNotificationTitle: 'Terrango',
        initialNotificationContent: 'Background tracking is active.',
        foregroundServiceNotificationId: 31042,
        foregroundServiceTypes: const [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: backgroundTrackingServiceEntryPoint,
        onBackground: backgroundTrackingServiceIosBackground,
      ),
    );

    _configured = true;
  }
}

@pragma('vm:entry-point')
Future<bool> backgroundTrackingServiceIosBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void backgroundTrackingServiceEntryPoint(ServiceInstance service) {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((_) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((_) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((_) {
    service.stopSelf();
  });

  Timer.periodic(const Duration(minutes: 1), (timer) async {
    if (service is! AndroidServiceInstance) {
      timer.cancel();
      return;
    }

    final isForeground = await service.isForegroundService();
    if (!isForeground) {
      timer.cancel();
      return;
    }

    await service.setForegroundNotificationInfo(
      title: 'Terrango background tracking',
      content: 'GPS and Bluetooth collection can continue with the screen off.',
    );
  });
}

