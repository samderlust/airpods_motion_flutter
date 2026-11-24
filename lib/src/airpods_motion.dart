import 'dart:async';

import 'airpods_motion_platform_interface.dart';
import 'models/airpods_motion_config.dart';
import 'models/headphone_device.dart';
import 'models/headphone_motion_sample.dart';
import 'simulator/airpods_motion_simulator.dart';

/// High-level client API for calibrated 6-DoF AirPods & Beats head-motion
/// telemetry, live route detection, and deterministic simulation.
class AirPodsMotion {
  /// Creates an [AirPodsMotion] client.
  ///
  /// Optional [platform] and [simulator] overrides are useful for testing.
  AirPodsMotion({
    AirpodsMotionPlatform? platform,
    AirPodsMotionSimulator? simulator,
  }) : this._(platform: platform, simulator: simulator);

  AirPodsMotion._({
    AirpodsMotionPlatform? platform,
    AirPodsMotionSimulator? simulator,
    bool isSingleton = false,
  }) : _platform = platform ?? AirpodsMotionPlatform.instance,
       simulator = simulator ?? AirPodsMotionSimulator(),
       _isSingleton = isSingleton {
    _platformMotionSub = _platform.motionStream.listen((sample) {
      if (!_disposed) {
        _motionController.add(sample);
      }
    }, onError: (_) {});
    _platformDeviceSub = _platform.deviceStream.listen((device) {
      if (!_disposed) {
        _deviceController.add(device);
      }
    }, onError: (_) {});
    _platformErrorSub = _platform.errorStream.listen((error) {
      if (!_disposed) {
        _errorController.add(error);
      }
    }, onError: (_) {});
    _simulatorSub = this.simulator.stream.listen((sample) {
      if (!_disposed) {
        _motionController.add(sample);
      }
    }, onError: (_) {});
  }

  /// Shared default singleton instance.
  static final AirPodsMotion instance = AirPodsMotion._(isSingleton: true);

  final AirpodsMotionPlatform _platform;

  /// Built-in simulator and trace replay controller.
  final AirPodsMotionSimulator simulator;

  final bool _isSingleton;

  final StreamController<HeadphoneMotionSample> _motionController =
      StreamController<HeadphoneMotionSample>.broadcast();
  final StreamController<HeadphoneDevice> _deviceController =
      StreamController<HeadphoneDevice>.broadcast();
  final StreamController<AirPodsMotionError> _errorController =
      StreamController<AirPodsMotionError>.broadcast();

  StreamSubscription<HeadphoneMotionSample>? _platformMotionSub;
  StreamSubscription<HeadphoneDevice>? _platformDeviceSub;
  StreamSubscription<AirPodsMotionError>? _platformErrorSub;
  StreamSubscription<HeadphoneMotionSample>? _simulatorSub;

  AirPodsMotionConfig _currentConfig = const AirPodsMotionConfig();
  bool _isTracking = false;
  bool _isSimulating = false;
  bool _disposed = false;

  /// The active [AirPodsMotionConfig].
  AirPodsMotionConfig get currentConfig => _currentConfig;

  /// Whether tracking (native or simulated) is currently active.
  bool get isTracking => _isTracking;

  /// Whether [AirPodsMotion] is currently running in simulator fallback mode.
  bool get isSimulating => _isSimulating;

  /// Broadcast stream of 6-DoF telemetry frames from native CoreMotion or
  /// [simulator].
  Stream<HeadphoneMotionSample> get motionStream => _motionController.stream;

  /// Broadcast stream of headphone connection, route, and calibration updates.
  Stream<HeadphoneDevice> get deviceStream => _deviceController.stream;

  /// Broadcast stream of CoreMotion runtime errors.
  Stream<AirPodsMotionError> get errorStream => _errorController.stream;

  /// Queries the current headphone device status snapshot.
  Future<HeadphoneDevice> getDeviceInfo() async {
    if (_isSimulating) {
      return _buildSimulatedDevice();
    }
    return _platform.getDeviceInfo();
  }

  /// Queries the current CoreMotion headphone motion authorization status.
  Future<HeadphoneAuthorizationStatus> getAuthorizationStatus() async {
    if (_isSimulating) {
      return HeadphoneAuthorizationStatus.authorized;
    }
    return _platform.getAuthorizationStatus();
  }

  /// Starts head-motion tracking with [config].
  ///
  /// Returns `true` when native CoreMotion tracking starts. When native motion
  /// hardware is unavailable, [AirPodsMotionConfig.simulatorFallbackMode]
  /// determines whether simulator mode remains inactive (`none`), enters manual
  /// injection mode (`manual`), or starts the procedural loop (`syntheticLoop`),
  /// returning `false` to indicate native hardware was not started.
  Future<bool> startTracking({
    AirPodsMotionConfig config = const AirPodsMotionConfig(),
  }) async {
    _currentConfig = config;
    final started = await _platform.startTracking(config: config);
    if (started) {
      simulator.stop();
      _isSimulating = false;
      _isTracking = true;
      return true;
    }

    switch (config.simulatorFallbackMode) {
      case SimulatorFallbackMode.none:
        simulator.stop();
        _isSimulating = false;
        _isTracking = false;
      case SimulatorFallbackMode.manual:
        simulator.stop();
        _isSimulating = true;
        _isTracking = true;
        if (!_disposed) {
          _deviceController.add(_buildSimulatedDevice());
        }
      case SimulatorFallbackMode.syntheticLoop:
        _isSimulating = true;
        _isTracking = true;
        if (!_disposed) {
          _deviceController.add(_buildSimulatedDevice());
        }
        simulator.startSyntheticLoop(sampleRateHz: config.sampleRateHz);
    }
    return false;
  }

  /// Stops native and/or simulated head-motion tracking.
  Future<void> stopTracking() async {
    _isTracking = false;
    final wasSimulating = _isSimulating;
    _isSimulating = false;
    simulator.stop();
    await _platform.stopTracking();
    if (wasSimulating && !_disposed) {
      _deviceController.add(_buildSimulatedDevice());
    }
  }

  /// Captures the current head orientation as the zero-point reference.
  Future<bool> calibrate() async {
    if (_isSimulating) {
      final ok = simulator.calibrate();
      if (!_disposed) {
        _deviceController.add(_buildSimulatedDevice());
      }
      return ok;
    }
    return _platform.calibrate();
  }

  /// Clears any active zero-point calibration reference.
  Future<bool> resetCalibration() async {
    if (_isSimulating) {
      simulator.resetCalibration();
      if (!_disposed) {
        _deviceController.add(_buildSimulatedDevice());
      }
      return true;
    }
    return _platform.resetCalibration();
  }

  HeadphoneDevice _buildSimulatedDevice() {
    return HeadphoneDevice(
      name: 'Simulated AirPods Pro',
      model: HeadphoneHardwareModel.airPodsPro,
      isConnected: _isSimulating,
      isMotionAvailable: false,
      isActive: _isTracking && _isSimulating,
      sampleRateHz:
          _isTracking && _isSimulating ? _currentConfig.sampleRateHz : 0,
      isCalibrated: simulator.isCalibrated,
      sensorLocation: HeadphoneSensorLocation.defaultLocation,
      authorizationStatus:
          _isSimulating
              ? HeadphoneAuthorizationStatus.authorized
              : HeadphoneAuthorizationStatus.unknown,
      isSimulated: true,
    );
  }

  /// Stops tracking and releases all streams and simulator resources.
  ///
  /// When invoked on [AirPodsMotion.instance], stops active tracking without
  /// closing the shared singleton broadcast streams.
  Future<void> dispose() async {
    if (_isSingleton) {
      await stopTracking();
      return;
    }
    if (_disposed) {
      return;
    }
    _disposed = true;
    _isTracking = false;
    _isSimulating = false;
    simulator.stop();
    await _platform.stopTracking();
    await _platformMotionSub?.cancel();
    await _platformDeviceSub?.cancel();
    await _platformErrorSub?.cancel();
    await _simulatorSub?.cancel();
    await simulator.dispose();
    await _motionController.close();
    await _deviceController.close();
    await _errorController.close();
  }
}
