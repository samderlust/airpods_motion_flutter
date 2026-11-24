import 'dart:math' as math;

import 'package:airpods_motion_flutter/airpods_motion_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AirPodsMotionSimulator', () {
    late AirPodsMotionSimulator simulator;

    setUp(() {
      simulator = AirPodsMotionSimulator();
    });

    tearDown(() async {
      await simulator.dispose();
    });

    test('emitSample emits exact sample onto stream', () async {
      const sample = HeadphoneMotionSample(
        pitchDeg: -8.5,
        rollDeg: 1.5,
        yawDeg: 12.0,
        accelerationMagnitude: 0.04,
        isCalibrated: true,
        isSimulated: true,
        timestampMs: 12345,
      );

      final future = expectLater(simulator.stream, emits(sample));
      simulator.emitSample(sample);
      await future;
    });

    test('emitEuler constructs normalized quaternion and gravity', () async {
      final emitted = <HeadphoneMotionSample>[];
      final sub = simulator.stream.listen(emitted.add);

      simulator.emitEuler(
        pitchDeg: 15.0,
        rollDeg: -5.0,
        yawDeg: 30.0,
        acceleration: 0.05,
        timestampMs: 5000,
      );
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(emitted, hasLength(1));
      final s = emitted.first;
      expect(s.pitchDeg, 15.0);
      expect(s.rollDeg, -5.0);
      expect(s.yawDeg, 30.0);
      expect(s.isSimulated, isTrue);
      expect(s.isCalibrated, isFalse);
      expect(s.timestampMs, 5000);

      final qNorm = math.sqrt(
        s.quaternion.x * s.quaternion.x +
            s.quaternion.y * s.quaternion.y +
            s.quaternion.z * s.quaternion.z +
            s.quaternion.w * s.quaternion.w,
      );
      expect(qNorm, closeTo(1.0, 1e-6));
      expect(s.gravity.magnitude, closeTo(1.0, 1e-6));
    });

    test('calibrate and resetCalibration zero subsequent emitEuler outputs', () async {
      final emitted = <HeadphoneMotionSample>[];
      final sub = simulator.stream.listen(emitted.add);

      expect(simulator.isCalibrated, isFalse);

      simulator.emitEuler(pitchDeg: 10.0, rollDeg: -5.0, yawDeg: 175.0);
      expect(simulator.calibrate(), isTrue);
      expect(simulator.isCalibrated, isTrue);

      // Re-emitting the calibration pose yields zeroed angles with isCalibrated=true.
      simulator.emitEuler(pitchDeg: 10.0, rollDeg: -5.0, yawDeg: 175.0);
      // Crossing ±180° from +175° to -175° produces +10° yaw delta.
      simulator.emitEuler(pitchDeg: 12.0, rollDeg: -3.0, yawDeg: -175.0);

      simulator.resetCalibration();
      expect(simulator.isCalibrated, isFalse);

      simulator.emitEuler(pitchDeg: 12.0, rollDeg: -3.0, yawDeg: -175.0);

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(emitted, hasLength(4));
      expect(emitted[0].isCalibrated, isFalse);
      expect(emitted[1].pitchDeg, closeTo(0.0, 1e-9));
      expect(emitted[1].rollDeg, closeTo(0.0, 1e-9));
      expect(emitted[1].yawDeg, closeTo(0.0, 1e-9));
      expect(emitted[1].isCalibrated, isTrue);

      expect(emitted[2].pitchDeg, closeTo(2.0, 1e-9));
      expect(emitted[2].rollDeg, closeTo(2.0, 1e-9));
      expect(emitted[2].yawDeg, closeTo(10.0, 1e-9));
      expect(emitted[2].isCalibrated, isTrue);

      expect(emitted[3].pitchDeg, closeTo(12.0, 1e-9));
      expect(emitted[3].rollDeg, closeTo(-3.0, 1e-9));
      expect(emitted[3].yawDeg, closeTo(-175.0, 1e-9));
      expect(emitted[3].isCalibrated, isFalse);
    });

    test(
      'startSyntheticLoop emits periodic samples and stop halts emission',
      () async {
        final emitted = <HeadphoneMotionSample>[];
        final sub = simulator.stream.listen(emitted.add);

        simulator.startSyntheticLoop(
          sampleRateHz: 50,
          pitchAmplitudeDeg: 10.0,
          yawAmplitudeDeg: 15.0,
        );
        expect(simulator.isRunning, isTrue);

        await Future<void>.delayed(const Duration(milliseconds: 95));
        simulator.stop();
        expect(simulator.isRunning, isFalse);

        final countAfterStop = emitted.length;
        expect(countAfterStop, greaterThanOrEqualTo(2));

        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(emitted.length, countAfterStop);
        await sub.cancel();
      },
    );

    test('replayTrace replays frames in deterministic order', () async {
      final trace = <HeadphoneMotionSample>[
        const HeadphoneMotionSample(
          pitchDeg: 1,
          rollDeg: 0,
          yawDeg: 0,
          timestampMs: 1000,
        ),
        const HeadphoneMotionSample(
          pitchDeg: 2,
          rollDeg: 0,
          yawDeg: 5,
          timestampMs: 1020,
        ),
        const HeadphoneMotionSample(
          pitchDeg: 3,
          rollDeg: 0,
          yawDeg: 10,
          timestampMs: 1040,
        ),
      ];

      final received = <HeadphoneMotionSample>[];
      final sub = simulator.stream.listen(received.add);

      await simulator.replayTrace(trace, speedMultiplier: 4.0);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(received, equals(trace));
    });

    test('replayTrace rejects non-positive speedMultiplier', () async {
      expect(
        () => simulator.replayTrace(const [], speedMultiplier: 0),
        throwsArgumentError,
      );
    });

    test('stop cancels an in-flight replayTrace cleanly', () async {
      final trace = <HeadphoneMotionSample>[
        const HeadphoneMotionSample(
          pitchDeg: 1,
          rollDeg: 0,
          yawDeg: 0,
          timestampMs: 1000,
        ),
        const HeadphoneMotionSample(
          pitchDeg: 2,
          rollDeg: 0,
          yawDeg: 0,
          timestampMs: 1500,
        ),
      ];

      final received = <HeadphoneMotionSample>[];
      final sub = simulator.stream.listen(received.add);

      final replayFuture = simulator.replayTrace(trace, speedMultiplier: 1.0);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      simulator.stop();
      await replayFuture;
      await sub.cancel();

      expect(received, hasLength(1));
    });
  });
}
