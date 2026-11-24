import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'airpods_motion_platform_interface.dart';
import 'models/airpods_motion_config.dart';
import 'models/headphone_device.dart';
import 'models/headphone_motion_sample.dart';

/// MethodChannel / EventChannel implementation of [AirpodsMotionPlatform].
class MethodChannelAirpodsMotion extends AirpodsMotionPlatform {
  /// Creates a [MethodChannelAirpodsMotion].
  MethodChannelAirpodsMotion();

  /// Control MethodChannel name.
  static const String methodChannelName =
      'com.samderlust.airpods_motion_flutter/control';

  /// Telemetry & device update EventChannel name.
  static const String eventChannelName =
      'com.samderlust.airpods_motion_flutter/events';

  /// MethodChannel exposed for testing.
  @visibleForTesting
  final MethodChannel methodChannel = const MethodChannel(methodChannelName);

  /// EventChannel exposed for testing.
  @visibleForTesting
  final EventChannel eventChannel = const EventChannel(eventChannelName);

  final StreamController<HeadphoneMotionSample> _motionController =
      StreamController<HeadphoneMotionSample>.broadcast();
  final StreamController<HeadphoneDevice> _deviceController =
      StreamController<HeadphoneDevice>.broadcast();

  StreamSubscription<dynamic>? _eventSubscription;

  @override
  Future<HeadphoneDevice> getDeviceInfo() async {
    try {
      final raw = await methodChannel.invokeMapMethod<String, dynamic>(
        'getDeviceInfo',
      );
      if (raw != null) {
        return HeadphoneDevice.fromMap(raw);
      }
    } on MissingPluginException {
      // Expected on unsupported targets or unit tests without native plugin.
    } on PlatformException {
      // Fall back to unavailable/simulated device snapshot.
    }

    return const HeadphoneDevice(
      name: 'Simulated AirPods Pro',
      model: HeadphoneHardwareModel.airPodsPro,
      isConnected: false,
      isMotionAvailable: false,
      isActive: false,
      sampleRateHz: 0,
      isCalibrated: false,
      sensorLocation: HeadphoneSensorLocation.unknown,
      isSimulated: true,
    );
  }

  @override
  Future<bool> startTracking({
    AirPodsMotionConfig config = const AirPodsMotionConfig(),
  }) async {
    _ensureEventSubscription();
    try {
      final started = await methodChannel.invokeMethod<bool>(
        'startTracking',
        config.toMap(),
      );
      return started ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> stopTracking() async {
    try {
      await methodChannel.invokeMethod<bool>('stopTracking');
    } on MissingPluginException {
      // No-op on unsupported targets.
    } on PlatformException {
      // No-op if already stopped.
    }
  }

  @override
  Future<bool> calibrate() async {
    try {
      final ok = await methodChannel.invokeMethod<bool>('calibrate');
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> resetCalibration() async {
    try {
      final ok = await methodChannel.invokeMethod<bool>('resetCalibration');
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Stream<HeadphoneMotionSample> get motionStream {
    _ensureEventSubscription();
    return _motionController.stream;
  }

  @override
  Stream<HeadphoneDevice> get deviceStream {
    _ensureEventSubscription();
    return _deviceController.stream;
  }

  void _ensureEventSubscription() {
    if (_eventSubscription != null) {
      return;
    }
    try {
      _eventSubscription = eventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          if (event is! Map) {
            return;
          }
          final map = Map<String, dynamic>.from(event);
          final type = map['type'] as String?;
          if (type == 'device') {
            _deviceController.add(HeadphoneDevice.fromMap(map));
          } else {
            _motionController.add(HeadphoneMotionSample.fromMap(map));
          }
        },
        onError: (_) {
          // Swallow native stream errors to keep broadcast streams alive.
        },
        cancelOnError: false,
      );
    } on MissingPluginException {
      // Expected on unsupported targets or widget tests.
    }
  }

  /// Releases stream subscriptions and controllers.
  Future<void> dispose() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _motionController.close();
    await _deviceController.close();
  }
}
