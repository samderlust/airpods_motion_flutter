import 'dart:math' as math;

import 'package:airpods_motion_flutter/airpods_motion_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OneEuroFilter', () {
    test('returns exact first sample and handles non-positive dt', () {
      final filter = OneEuroFilter(minCutoff: 1.0, beta: 0.007, dCutoff: 1.0);
      expect(filter.filter(12.5, timestampSeconds: 1.0), 12.5);
      // Same or older timestamp returns previous filtered value.
      expect(filter.filter(99.0, timestampSeconds: 1.0), 12.5);
      expect(filter.filter(99.0, timestampSeconds: 0.5), 12.5);
    });

    test(
      'attenuates high-frequency jitter while staying near steady baseline',
      () {
        final filter = OneEuroFilter(minCutoff: 0.5, beta: 0.005, dCutoff: 1.0);
        final inputs = <double>[];
        final outputs = <double>[];

        for (var i = 0; i < 60; i++) {
          final t = i / 30.0; // 30 Hz
          final noisy = 10.0 + (i.isEven ? 1.5 : -1.5);
          inputs.add(noisy);
          outputs.add(filter.filter(noisy, timestampSeconds: t));
        }

        double stdDev(List<double> values) {
          final mean = values.reduce((a, b) => a + b) / values.length;
          final variance =
              values.map((v) => math.pow(v - mean, 2)).reduce((a, b) => a + b) /
              values.length;
          return math.sqrt(variance);
        }

        // After initial transient, jitter amplitude should be substantially reduced.
        expect(
          stdDev(outputs.sublist(10)),
          lessThan(stdDev(inputs.sublist(10)) * 0.4),
        );
      },
    );

    test('higher beta tracks rapid step changes with lower lag', () {
      final lowBeta = OneEuroFilter(minCutoff: 0.5, beta: 0.0, dCutoff: 1.0);
      final highBeta = OneEuroFilter(minCutoff: 0.5, beta: 0.5, dCutoff: 1.0);

      for (var i = 0; i < 10; i++) {
        final t = i * 0.04;
        lowBeta.filter(0.0, timestampSeconds: t);
        highBeta.filter(0.0, timestampSeconds: t);
      }

      // Sudden rapid movement to 45 degrees.
      final lowOut = lowBeta.filter(45.0, timestampSeconds: 0.40);
      final highOut = highBeta.filter(45.0, timestampSeconds: 0.40);
      expect(highOut, greaterThan(lowOut));
    });

    test('reset clears prior filter memory', () {
      final filter = OneEuroFilter();
      filter.filter(20.0, timestampSeconds: 1.0);
      filter.filter(22.0, timestampSeconds: 1.1);
      filter.reset();

      // Next sample after reset should pass through unmodified.
      expect(filter.filter(-15.0, timestampSeconds: 2.0), -15.0);
    });

    test('unwraps Euler angles across ±180° boundary without sweeping through 0°', () {
      final angleFilter = OneEuroFilter(
        minCutoff: 1.0,
        beta: 0.007,
        dCutoff: 1.0,
        isAngleDegrees: true,
      );

      final first = angleFilter.filter(179.0, timestampSeconds: 0.0);
      expect(first, closeTo(179.0, 1e-9));

      final second = angleFilter.filter(-179.0, timestampSeconds: 0.05);
      // Shortest path from +179° to -179° is +2°, so filtered output stays near ±180°.
      expect(second.abs(), greaterThan(178.5));
      expect(second.abs(), lessThanOrEqualTo(180.0));

      final third = angleFilter.filter(-178.0, timestampSeconds: 0.10);
      expect(third.abs(), greaterThan(177.5));
      expect(third.abs(), lessThanOrEqualTo(180.0));
    });
  });

  group('OneEuroPoseFilter', () {
    test('filters Euler poses across ±180° wrap-around cleanly', () {
      final poseFilter = OneEuroPoseFilter(minCutoff: 1.0, beta: 0.01);

      final first = poseFilter.filterEuler(
        pitchDeg: 0,
        rollDeg: 179.0,
        yawDeg: -179.0,
        timestampMs: 1000,
      );
      expect(first.rollDeg, closeTo(179.0, 1e-9));
      expect(first.yawDeg, closeTo(-179.0, 1e-9));

      final second = poseFilter.filterEuler(
        pitchDeg: 0,
        rollDeg: -179.0,
        yawDeg: 179.0,
        timestampMs: 1050,
      );
      expect(second.rollDeg.abs(), greaterThan(178.5));
      expect(second.yawDeg.abs(), greaterThan(178.5));
    });

    test('filters Euler poses and HeadphoneMotionSample cleanly', () {
      final poseFilter = OneEuroPoseFilter(minCutoff: 1.0, beta: 0.01);

      final first = poseFilter.filterEuler(
        pitchDeg: 0,
        rollDeg: 0,
        yawDeg: 0,
        timestampMs: 1000,
      );
      expect(first.pitchDeg, 0);
      expect(first.rollDeg, 0);
      expect(first.yawDeg, 0);

      final second = poseFilter.filterEuler(
        pitchDeg: 10,
        rollDeg: -4,
        yawDeg: 20,
        timestampMs: 1050,
      );
      expect(second.pitchDeg, inExclusiveRange(0, 10));
      expect(second.rollDeg, inExclusiveRange(-4, 0));
      expect(second.yawDeg, inExclusiveRange(0, 20));

      poseFilter.reset();
      const rawSample = HeadphoneMotionSample(
        pitchDeg: -12.0,
        rollDeg: 3.0,
        yawDeg: 8.0,
        accelerationMagnitude: 0.12,
        timestampMs: 2000,
      );
      final filteredSample = poseFilter.filterSample(rawSample);
      expect(filteredSample.pitchDeg, -12.0);
      expect(filteredSample.accelerationMagnitude, 0.12);
    });
  });
}
