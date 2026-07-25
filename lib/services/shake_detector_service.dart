import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// iOS `deviceDidShake` 通知相当
///
/// iOS: UIKit の motionEnded（ネイティブ osmWashabe と同方式）
/// Android: 加速度センサー
class ShakeDetectorService {
  static const _eventChannel =
      EventChannel('com.osamushikubo.osm_washabe/device_shake');

  StreamSubscription<dynamic>? _subscription;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  int _shakeTimestamp = 0;
  int _shakeCount = 0;

  void start(VoidCallback onShake) {
    stop();
    if (Platform.isIOS) {
      _subscription =
          _eventChannel.receiveBroadcastStream().listen((_) => onShake());
      return;
    }
    _accelerometerSubscription = accelerometerEventStream().listen((event) {
      final gX = event.x / 9.80665;
      final gY = event.y / 9.80665;
      final gZ = event.z / 9.80665;
      final gForce = sqrt(gX * gX + gY * gY + gZ * gZ);
      if (gForce <= 1.8) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      if (_shakeTimestamp + 500 > now) return;
      if (_shakeTimestamp + 3000 < now) {
        _shakeCount = 0;
      }
      _shakeTimestamp = now;
      _shakeCount++;
      if (_shakeCount >= 1) {
        onShake();
      }
    });
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
    _shakeCount = 0;
  }

  void dispose() => stop();
}
