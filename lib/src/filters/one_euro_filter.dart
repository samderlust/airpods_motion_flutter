import 'dart:math' as math;

import '../models/headphone_motion_sample.dart';

/// Pure-Dart implementation of the adaptive 1-Euro low-pass filter
/// (Casiez, Roussel, & Vogel, CHI 2012).
///
/// Suppresses micro-jitter when the head is stationary while raising the cutoff
/// frequency during rapid movements to minimize perceptual lag.
class OneEuroFilter {
  /// Creates a [OneEuroFilter].
  ///
  /// - [minCutoff]: Minimum cutoff frequency in Hz (lower = smoother at rest).
  /// - [beta]: Speed coefficient (higher = less lag during fast motion).
  /// - [dCutoff]: Cutoff frequency in Hz for the derivative low-pass filter.
  OneEuroFilter({this.minCutoff = 1.0, this.beta = 0.007, this.dCutoff = 1.0})
    : assert(minCutoff > 0, 'minCutoff must be > 0'),
      assert(beta >= 0, 'beta must be >= 0'),
      assert(dCutoff > 0, 'dCutoff must be > 0');

  /// Minimum cutoff frequency in Hz.
  final double minCutoff;

  /// Derivative speed coefficient.
  final double beta;

  /// Derivative filter cutoff frequency in Hz.
  final double dCutoff;

  double? _lastTimestampSeconds;
  double? _xPrev;
  double _dxPrev = 0.0;

  /// Filters [value] sampled at [timestampSeconds] (monotonic or epoch seconds).
  double filter(double value, {required double timestampSeconds}) {
    if (_lastTimestampSeconds == null || _xPrev == null) {
      _lastTimestampSeconds = timestampSeconds;
      _xPrev = value;
      _dxPrev = 0.0;
      return value;
    }

    final dt = timestampSeconds - _lastTimestampSeconds!;
    if (dt <= 0) {
      return _xPrev!;
    }
    _lastTimestampSeconds = timestampSeconds;

    final dx = (value - _xPrev!) / dt;
    final alphaD = _smoothingFactor(dt, dCutoff);
    final dxHat = _exponentialSmoothing(alphaD, dx, _dxPrev);

    final cutoff = minCutoff + beta * dxHat.abs();
    final alpha = _smoothingFactor(dt, cutoff);
    final xHat = _exponentialSmoothing(alpha, value, _xPrev!);

    _xPrev = xHat;
    _dxPrev = dxHat;
    return xHat;
  }

  /// Convenience wrapper accepting millisecond timestamps.
  double filterAtMs(double value, int timestampMs) =>
      filter(value, timestampSeconds: timestampMs / 1000.0);

  /// Clears internal filter state so the next sample initializes fresh.
  void reset() {
    _lastTimestampSeconds = null;
    _xPrev = null;
    _dxPrev = 0.0;
  }

  static double _smoothingFactor(double dt, double cutoff) {
    final r = 2.0 * math.pi * cutoff * dt;
    return r / (r + 1.0);
  }

  static double _exponentialSmoothing(double alpha, double x, double xPrev) =>
      alpha * x + (1.0 - alpha) * xPrev;
}

/// Multi-channel 1-Euro filter for 3-axis head pose (`pitch`, `roll`, `yaw`)
/// and optional scalar acceleration magnitude.
class OneEuroPoseFilter {
  /// Creates a [OneEuroPoseFilter] with shared tuning parameters across axes.
  OneEuroPoseFilter({
    double minCutoff = 1.0,
    double beta = 0.007,
    double dCutoff = 1.0,
  }) : _pitch = OneEuroFilter(
         minCutoff: minCutoff,
         beta: beta,
         dCutoff: dCutoff,
       ),
       _roll = OneEuroFilter(
         minCutoff: minCutoff,
         beta: beta,
         dCutoff: dCutoff,
       ),
       _yaw = OneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: dCutoff),
       _accel = OneEuroFilter(
         minCutoff: minCutoff,
         beta: beta,
         dCutoff: dCutoff,
       );

  final OneEuroFilter _pitch;
  final OneEuroFilter _roll;
  final OneEuroFilter _yaw;
  final OneEuroFilter _accel;

  /// Filters raw Euler angles in degrees at [timestampMs] and returns
  /// `(pitchDeg, rollDeg, yawDeg)`.
  ({double pitchDeg, double rollDeg, double yawDeg}) filterEuler({
    required double pitchDeg,
    required double rollDeg,
    required double yawDeg,
    required int timestampMs,
  }) {
    return (
      pitchDeg: _pitch.filterAtMs(pitchDeg, timestampMs),
      rollDeg: _roll.filterAtMs(rollDeg, timestampMs),
      yawDeg: _yaw.filterAtMs(yawDeg, timestampMs),
    );
  }

  /// Applies 1-Euro filtering to [sample]'s Euler angles and acceleration
  /// magnitude, returning a new [HeadphoneMotionSample].
  HeadphoneMotionSample filterSample(HeadphoneMotionSample sample) {
    final ts = sample.timestampMs;
    return sample.copyWith(
      pitchDeg: _pitch.filterAtMs(sample.pitchDeg, ts),
      rollDeg: _roll.filterAtMs(sample.rollDeg, ts),
      yawDeg: _yaw.filterAtMs(sample.yawDeg, ts),
      accelerationMagnitude: _accel.filterAtMs(
        sample.accelerationMagnitude,
        ts,
      ),
    );
  }

  /// Resets all axis filter states.
  void reset() {
    _pitch.reset();
    _roll.reset();
    _yaw.reset();
    _accel.reset();
  }
}
