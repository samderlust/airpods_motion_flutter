import 'dart:async';
import 'dart:math' as math;

import '../models/headphone_device.dart';
import '../models/headphone_motion_sample.dart';
import '../models/headphone_quaternion.dart';
import '../models/headphone_vector3.dart';

double _wrapAngleDeg(double angle) {
  var wrapped = (angle + 180.0) % 360.0;
  if (wrapped <= 0.0) {
    wrapped += 360.0;
  }
  return wrapped - 180.0;
}

/// Deterministic simulator and trace replay harness for testing and development
/// without physical AirPods hardware (e.g., iOS Simulator, Linux, or unit tests).
class AirPodsMotionSimulator {
  /// Creates an [AirPodsMotionSimulator].
  AirPodsMotionSimulator();

  final StreamController<HeadphoneMotionSample> _controller =
      StreamController<HeadphoneMotionSample>.broadcast();

  Timer? _syntheticTimer;
  int _generation = 0;
  bool _disposed = false;

  ({double pitchDeg, double rollDeg, double yawDeg})? _lastRawEuler;
  ({double pitchDeg, double rollDeg, double yawDeg})? _zeroOffset;

  /// Broadcast stream of simulated or replayed [HeadphoneMotionSample] frames.
  Stream<HeadphoneMotionSample> get stream => _controller.stream;

  /// Whether a synthetic loop is currently running.
  bool get isRunning => _syntheticTimer != null;

  /// Whether a zero-point calibration offset is currently active.
  bool get isCalibrated => _zeroOffset != null;

  /// Captures the most recent raw Euler orientation (or origin if none yet)
  /// as the zero-point offset for subsequent [emitEuler] calls.
  bool calibrate() {
    _zeroOffset =
        _lastRawEuler ?? (pitchDeg: 0.0, rollDeg: 0.0, yawDeg: 0.0);
    return true;
  }

  /// Clears any active zero-point calibration offset.
  void resetCalibration() {
    _zeroOffset = null;
  }

  /// Emits a single pre-built [HeadphoneMotionSample] onto [stream].
  void emitSample(HeadphoneMotionSample sample) {
    if (_disposed) {
      return;
    }
    _controller.add(sample);
  }

  /// Constructs and emits a synthetic [HeadphoneMotionSample] from Euler angles
  /// in degrees.
  void emitEuler({
    required double pitchDeg,
    double rollDeg = 0,
    double yawDeg = 0,
    double acceleration = 0.02,
    bool? isCalibrated,
    int? timestampMs,
  }) {
    if (_disposed) {
      return;
    }

    _lastRawEuler = (pitchDeg: pitchDeg, rollDeg: rollDeg, yawDeg: yawDeg);

    final offset = _zeroOffset;
    final effectivePitch =
        offset == null ? pitchDeg : pitchDeg - offset.pitchDeg;
    final effectiveRoll =
        offset == null ? rollDeg : _wrapAngleDeg(rollDeg - offset.rollDeg);
    final effectiveYaw =
        offset == null ? yawDeg : _wrapAngleDeg(yawDeg - offset.yawDeg);

    const degToRad = math.pi / 180.0;
    final pitch = effectivePitch * degToRad;
    final roll = effectiveRoll * degToRad;
    // Match native convention: +yawDeg turns right, CoreMotion yaw is +CCW.
    final yaw = -effectiveYaw * degToRad;

    final cy = math.cos(yaw * 0.5);
    final sy = math.sin(yaw * 0.5);
    final cp = math.cos(pitch * 0.5);
    final sp = math.sin(pitch * 0.5);
    final cr = math.cos(roll * 0.5);
    final sr = math.sin(roll * 0.5);

    final quaternion = HeadphoneQuaternion(
      x: sr * cp * cy - cr * sp * sy,
      y: cr * sp * cy + sr * cp * sy,
      z: cr * cp * sy - sr * sp * cy,
      w: cr * cp * cy + sr * sp * sy,
    );

    final gravity = HeadphoneVector3(
      x: -math.sin(roll),
      y: math.sin(pitch) * math.cos(roll),
      z: -math.cos(pitch) * math.cos(roll),
    );

    final userAccel = HeadphoneVector3(x: acceleration, y: 0, z: 0);

    emitSample(
      HeadphoneMotionSample(
        pitchDeg: effectivePitch,
        rollDeg: effectiveRoll,
        yawDeg: effectiveYaw,
        quaternion: quaternion,
        rotationRate: HeadphoneVector3.zero,
        userAcceleration: userAccel,
        gravity: gravity,
        accelerationMagnitude: acceleration.abs(),
        sensorLocation: HeadphoneSensorLocation.defaultLocation,
        isCalibrated: isCalibrated ?? this.isCalibrated,
        isSimulated: true,
        timestampMs: timestampMs ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Starts a continuous procedural sinusoidal head-motion loop at [sampleRateHz].
  void startSyntheticLoop({
    int sampleRateHz = 15,
    double pitchAmplitudeDeg = 8.0,
    double yawAmplitudeDeg = 12.0,
  }) {
    if (_disposed) {
      return;
    }
    stop();

    final rate = sampleRateHz.clamp(1, 100);
    final intervalMs = math.max(10, (1000 / rate).round());
    var tick = 0;

    _syntheticTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (_disposed) {
        stop();
        return;
      }
      final t = (tick * intervalMs) / 1000.0;
      tick++;

      final pitchDeg = pitchAmplitudeDeg * math.sin(t * 0.9);
      final yawDeg = yawAmplitudeDeg * math.sin(t * 0.55);
      final rollDeg = 2.5 * math.sin(t * 0.4);
      final accel = 0.015 + 0.01 * math.cos(t * 1.4).abs();

      emitEuler(
        pitchDeg: pitchDeg,
        rollDeg: rollDeg,
        yawDeg: yawDeg,
        acceleration: accel,
      );
    });
  }

  /// Deterministically replays [trace] honoring inter-frame `timestampMs`
  /// deltas scaled by [speedMultiplier].
  Future<void> replayTrace(
    List<HeadphoneMotionSample> trace, {
    double speedMultiplier = 1.0,
  }) async {
    if (speedMultiplier <= 0) {
      throw ArgumentError.value(
        speedMultiplier,
        'speedMultiplier',
        'Must be greater than 0.',
      );
    }
    if (_disposed || trace.isEmpty) {
      return;
    }

    stop();
    final gen = _generation;

    for (var i = 0; i < trace.length; i++) {
      if (_disposed || gen != _generation) {
        return;
      }
      if (i > 0) {
        final deltaMs = trace[i].timestampMs - trace[i - 1].timestampMs;
        if (deltaMs > 0) {
          final waitMicros = ((deltaMs * 1000) / speedMultiplier).round();
          if (waitMicros > 0) {
            await Future<void>.delayed(Duration(microseconds: waitMicros));
          }
        }
      }
      if (_disposed || gen != _generation) {
        return;
      }
      emitSample(trace[i]);
    }
  }

  /// Stops any active synthetic motion loop or in-flight trace replay.
  void stop() {
    _generation++;
    _syntheticTimer?.cancel();
    _syntheticTimer = null;
  }

  /// Stops active generators and closes [stream].
  Future<void> dispose() async {
    stop();
    _disposed = true;
    await _controller.close();
  }
}
