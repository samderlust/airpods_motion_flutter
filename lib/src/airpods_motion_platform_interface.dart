import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'method_channel_airpods_motion.dart';
import 'models/airpods_motion_config.dart';
import 'models/headphone_device.dart';
import 'models/headphone_motion_sample.dart';

/// Platform interface that platform-specific implementations of
/// `airpods_motion_flutter` must implement.
abstract class AirpodsMotionPlatform extends PlatformInterface {
  /// Constructs an [AirpodsMotionPlatform].
  AirpodsMotionPlatform() : super(token: _token);

  static final Object _token = Object();

  static AirpodsMotionPlatform _instance = MethodChannelAirpodsMotion();

  /// The default instance of [AirpodsMotionPlatform] to use.
  static AirpodsMotionPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [AirpodsMotionPlatform].
  static set instance(AirpodsMotionPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Fetches the current connected headphone device status snapshot.
  Future<HeadphoneDevice> getDeviceInfo() {
    throw UnimplementedError('getDeviceInfo() has not been implemented.');
  }

  /// Queries the current CoreMotion headphone motion authorization status.
  Future<HeadphoneAuthorizationStatus> getAuthorizationStatus() {
    throw UnimplementedError(
      'getAuthorizationStatus() has not been implemented.',
    );
  }

  /// Starts native headphone motion tracking with [config].
  ///
  /// Returns `true` if native motion updates started, or `false` when motion
  /// hardware is unavailable or unsupported.
  Future<bool> startTracking({
    AirPodsMotionConfig config = const AirPodsMotionConfig(),
  }) {
    throw UnimplementedError('startTracking() has not been implemented.');
  }

  /// Stops native headphone motion tracking.
  Future<void> stopTracking() {
    throw UnimplementedError('stopTracking() has not been implemented.');
  }

  /// Captures the current attitude as the zero-point reference quaternion.
  Future<bool> calibrate() {
    throw UnimplementedError('calibrate() has not been implemented.');
  }

  /// Clears any active zero-point calibration reference.
  Future<bool> resetCalibration() {
    throw UnimplementedError('resetCalibration() has not been implemented.');
  }

  /// Broadcast stream of 6-DoF telemetry frames.
  Stream<HeadphoneMotionSample> get motionStream {
    throw UnimplementedError('motionStream has not been implemented.');
  }

  /// Broadcast stream of device connection and audio route updates.
  Stream<HeadphoneDevice> get deviceStream {
    throw UnimplementedError('deviceStream has not been implemented.');
  }

  /// Broadcast stream of CoreMotion runtime errors.
  Stream<AirPodsMotionError> get errorStream =>
      const Stream<AirPodsMotionError>.empty();
}
