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
  }) : _platform = platform ?? AirpodsMotionPlatform.instance,
       simulator = simulator ?? AirPodsMotionSimulator() {
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
    _simulatorSub = this.simulator.stream.listen((sample) {
      if (!_disposed) {
        _motionController.add(sample);
      }
    }, onError: (_) {});
  }

  /// Shared default singleton instance.
  static final AirPodsMotion instance = AirPodsMotion();

  final AirpodsMotionPlatform _platform;

  /// Built-in simulator and trace replay controller.
  final AirPodsMotionSimulator simulator;

  final StreamController<HeadphoneMotionSample> _motionController =
      StreamController<HeadphoneMotionSample>.broadcast();
  final StreamController<HeadphoneDevice> _deviceController =
      StreamController<HeadphoneDevice>.broadcast();

  StreamSubscription<HeadphoneMotionSample>? _platformMotionSub;
  StreamSubscription<HeadphoneDevice>? _platformDeviceSub;
  StreamSubscription<HeadphoneMotionSample>? _simulatorSub;

  AirPodsMotionConfig _currentConfig = const AirPodsMotionConfig();
  bool _isTracking = false;
  bool _isSimulating = false;
  bool _simulatedCalibrated = false;
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

  /// Queries the current headphone device status snapshot.
  Future<HeadphoneDevice> getDeviceInfo() async {
    if (_isSimulating) {
      return _buildSimulatedDevice();
    }
    return _platform.getDeviceInfo();
  }

  /// Starts head-motion tracking with [config].
  ///
  /// Returns `true` when native CoreMotion tracking starts. When native motion
  /// hardware is unavailable and [AirPodsMotionConfig.autoFallbackToSimulator]
  /// is `true`, simulator fallback mode activates automatically and this
  /// method returns `false` to indicate native hardware was not started.
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

    if (config.autoFallbackToSimulator) {
      _isSimulating = true;
      _isTracking = true;
      _deviceController.add(_buildSimulatedDevice());
      simulator.startSyntheticLoop(sampleRateHz: config.sampleRateHz);
    } else {
      _isSimulating = false;
      _isTracking = false;
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
      _simulatedCalibrated = true;
      if (!_disposed) {
        _deviceController.add(_buildSimulatedDevice());
      }
      return true;
    }
    return _platform.calibrate();
  }

  /// Clears any active zero-point calibration reference.
  Future<bool> resetCalibration() async {
    if (_isSimulating) {
      _simulatedCalibrated = false;
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
      isCalibrated: _simulatedCalibrated,
      sensorLocation: HeadphoneSensorLocation.defaultLocation,
      isSimulated: true,
    );
  }

  /// Stops tracking and releases all streams and simulator resources.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _isTracking = false;
    _isSimulating = false;
    await _platformMotionSub?.cancel();
    await _platformDeviceSub?.cancel();
    await _simulatorSub?.cancel();
    await simulator.dispose();
    await _motionController.close();
    await _deviceController.close();
  }
}
