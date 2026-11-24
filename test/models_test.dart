import 'dart:math' as math;

import 'package:airpods_motion_flutter/airpods_motion_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HeadphoneVector3', () {
    test('computes magnitude and supports JSON roundtrip', () {
      const vec = HeadphoneVector3(x: 3, y: 4, z: 0);
      expect(vec.magnitude, closeTo(5.0, 1e-9));

      final map = vec.toJson();
      final restored = HeadphoneVector3.fromMap(map);
      expect(restored, equals(vec));
      expect(restored.hashCode, equals(vec.hashCode));
    });

    test('fromMap handles missing keys and integer numbers', () {
      final vec = HeadphoneVector3.fromMap(<String, dynamic>{'x': 1, 'z': -2});
      expect(vec, equals(const HeadphoneVector3(x: 1.0, y: 0.0, z: -2.0)));
      expect(HeadphoneVector3.zero.magnitude, 0.0);
    });
  });

  group('HeadphoneQuaternion', () {
    test('identity and JSON roundtrip', () {
      expect(
        HeadphoneQuaternion.identity,
        equals(const HeadphoneQuaternion(x: 0, y: 0, z: 0, w: 1)),
      );

      const q = HeadphoneQuaternion(x: 0.1, y: -0.2, z: 0.3, w: 0.927);
      final restored = HeadphoneQuaternion.fromMap(q.toJson());
      expect(restored, equals(q));
      expect(restored.hashCode, equals(q.hashCode));
    });
  });

  group('HeadphoneHardwareModel & HeadphoneSensorLocation', () {
    test('inferFromName identifies AirPods and Beats models accurately', () {
      expect(
        HeadphoneHardwareModel.inferFromName("Sam's AirPods Pro"),
        HeadphoneHardwareModel.airPodsPro,
      );
      expect(
        HeadphoneHardwareModel.inferFromName('AirPods Pro 2'),
        HeadphoneHardwareModel.airPodsPro2,
      );
      expect(
        HeadphoneHardwareModel.inferFromName('AirPods Max'),
        HeadphoneHardwareModel.airPodsMax,
      );
      expect(
        HeadphoneHardwareModel.inferFromName('AirPods (3rd generation)'),
        HeadphoneHardwareModel.airPodsGen3,
      );
      expect(
        HeadphoneHardwareModel.inferFromName('AirPods 4'),
        HeadphoneHardwareModel.airPodsGen4,
      );
      expect(
        HeadphoneHardwareModel.inferFromName('Beats Fit Pro'),
        HeadphoneHardwareModel.beats,
      );
      expect(
        HeadphoneHardwareModel.inferFromName('Powerbeats Pro'),
        HeadphoneHardwareModel.beats,
      );
      expect(
        HeadphoneHardwareModel.inferFromName('Studio Headphones'),
        HeadphoneHardwareModel.beats,
      );
      expect(
        HeadphoneHardwareModel.inferFromName('Generic Headset'),
        HeadphoneHardwareModel.unknown,
      );
      expect(
        HeadphoneHardwareModel.inferFromName(''),
        HeadphoneHardwareModel.unknown,
      );
    });

    test('HeadphoneSensorLocation parses wire values', () {
      expect(
        HeadphoneSensorLocation.fromWireValue('defaultLocation'),
        HeadphoneSensorLocation.defaultLocation,
      );
      expect(
        HeadphoneSensorLocation.fromWireValue('leftEar'),
        HeadphoneSensorLocation.leftEar,
      );
      expect(
        HeadphoneSensorLocation.fromWireValue('headphoneRight'),
        HeadphoneSensorLocation.rightEar,
      );
      expect(
        HeadphoneSensorLocation.fromWireValue('invalid'),
        HeadphoneSensorLocation.unknown,
      );
    });
  });

  group('HeadphoneDevice', () {
    test('fromMap infers model when omitted and supports copyWith', () {
      final device = HeadphoneDevice.fromMap(<String, dynamic>{
        'name': 'Alex AirPods Max',
        'isConnected': true,
        'isMotionAvailable': true,
        'isActive': true,
        'sampleRateHz': 25,
        'isCalibrated': true,
        'sensorLocation': 'rightEar',
        'authorizationStatus': 'authorized',
        'isSimulated': false,
      });

      expect(device.model, HeadphoneHardwareModel.airPodsMax);
      expect(device.sensorLocation, HeadphoneSensorLocation.rightEar);
      expect(device.authorizationStatus, HeadphoneAuthorizationStatus.authorized);
      expect(device.isConnected, isTrue);
      expect(device.isActive, isTrue);

      final updated = device.copyWith(
        isCalibrated: false,
        sampleRateHz: 15,
        authorizationStatus: HeadphoneAuthorizationStatus.denied,
      );
      expect(updated.isCalibrated, isFalse);
      expect(updated.sampleRateHz, 15);
      expect(updated.authorizationStatus, HeadphoneAuthorizationStatus.denied);
      expect(HeadphoneDevice.fromMap(updated.toMap()), equals(updated));
      expect(HeadphoneDevice.fromMap(updated.toMap()).hashCode, equals(updated.hashCode));
    });
  });

  group('HeadphoneAuthorizationStatus & AirPodsMotionError', () {
    test('fromWireValue parses all authorization statuses', () {
      expect(
        HeadphoneAuthorizationStatus.fromWireValue('notDetermined'),
        HeadphoneAuthorizationStatus.notDetermined,
      );
      expect(
        HeadphoneAuthorizationStatus.fromWireValue('restricted'),
        HeadphoneAuthorizationStatus.restricted,
      );
      expect(
        HeadphoneAuthorizationStatus.fromWireValue('denied'),
        HeadphoneAuthorizationStatus.denied,
      );
      expect(
        HeadphoneAuthorizationStatus.fromWireValue('authorized'),
        HeadphoneAuthorizationStatus.authorized,
      );
      expect(
        HeadphoneAuthorizationStatus.fromWireValue('unknown'),
        HeadphoneAuthorizationStatus.unknown,
      );
      expect(
        HeadphoneAuthorizationStatus.fromWireValue(null),
        HeadphoneAuthorizationStatus.unknown,
      );
    });

    test('AirPodsMotionError supports fromMap, toMap, and equality', () {
      final error = AirPodsMotionError.fromMap(<String, dynamic>{
        'code': 'CMErrorDomain:105',
        'message': 'Motion permission denied.',
        'authorizationStatus': 'denied',
      });
      expect(error.code, 'CMErrorDomain:105');
      expect(error.message, 'Motion permission denied.');
      expect(error.authorizationStatus, HeadphoneAuthorizationStatus.denied);

      final roundtrip = AirPodsMotionError.fromMap(error.toMap());
      expect(roundtrip, equals(error));
      expect(roundtrip.hashCode, equals(error.hashCode));
      expect(error.toString(), contains('CMErrorDomain:105'));
    });
  });

  group('AirPodsMotionConfig', () {
    test('clamps sampleRateHz and smoothingAlpha even as const', () {
      const low = AirPodsMotionConfig(sampleRateHz: -5, smoothingAlpha: -0.5);
      const high = AirPodsMotionConfig(sampleRateHz: 250, smoothingAlpha: 2.5);

      expect(low.sampleRateHz, 1);
      expect(low.smoothingAlpha, 0.0);
      expect(high.sampleRateHz, 100);
      expect(high.smoothingAlpha, 1.0);
    });

    test('SimulatorFallbackMode and autoFallbackToSimulator compatibility', () {
      const defaultConfig = AirPodsMotionConfig();
      expect(
        defaultConfig.simulatorFallbackMode,
        SimulatorFallbackMode.syntheticLoop,
      );
      expect(defaultConfig.autoFallbackToSimulator, isTrue);

      const legacyDisabled = AirPodsMotionConfig(
        autoFallbackToSimulator: false,
      );
      expect(legacyDisabled.simulatorFallbackMode, SimulatorFallbackMode.none);
      expect(legacyDisabled.autoFallbackToSimulator, isFalse);

      // Explicit simulatorFallbackMode takes precedence over autoFallbackToSimulator.
      const manualOverride = AirPodsMotionConfig(
        autoFallbackToSimulator: false,
        simulatorFallbackMode: SimulatorFallbackMode.manual,
      );
      expect(manualOverride.simulatorFallbackMode, SimulatorFallbackMode.manual);
      expect(manualOverride.autoFallbackToSimulator, isTrue);

      const noneOverride = AirPodsMotionConfig(
        autoFallbackToSimulator: true,
        simulatorFallbackMode: SimulatorFallbackMode.none,
      );
      expect(noneOverride.simulatorFallbackMode, SimulatorFallbackMode.none);
      expect(noneOverride.autoFallbackToSimulator, isFalse);

      // Legacy map without simulatorFallbackMode derives from autoFallbackToSimulator.
      final legacyRestored = AirPodsMotionConfig.fromMap(<String, dynamic>{
        'sampleRateHz': 20,
        'autoFallbackToSimulator': false,
      });
      expect(legacyRestored.simulatorFallbackMode, SimulatorFallbackMode.none);
      expect(legacyRestored.autoFallbackToSimulator, isFalse);

      // copyWith preserves manual mode and supports toggling.
      final updatedRate = manualOverride.copyWith(sampleRateHz: 40);
      expect(updatedRate.simulatorFallbackMode, SimulatorFallbackMode.manual);
      expect(
        manualOverride.copyWith(autoFallbackToSimulator: false).simulatorFallbackMode,
        SimulatorFallbackMode.none,
      );
    });

    test('toMap and fromMap roundtrip', () {
      const config = AirPodsMotionConfig(
        sampleRateHz: 30,
        filterMode: AirPodsFilterMode.oneEuro,
        smoothingAlpha: 0.4,
        oneEuroMinCutoff: 1.5,
        oneEuroBeta: 0.02,
        oneEuroDCutoff: 1.2,
        simulatorFallbackMode: SimulatorFallbackMode.manual,
      );

      final restored = AirPodsMotionConfig.fromMap(config.toMap());
      expect(restored, equals(config));
      expect(restored.hashCode, equals(config.hashCode));
    });
  });

  group('HeadphoneMotionSample', () {
    test('toJson and fromMap preserve all 6-DoF fields and nested maps', () {
      const sample = HeadphoneMotionSample(
        pitchDeg: -5.5,
        rollDeg: 2.25,
        yawDeg: 14.75,
        quaternion: HeadphoneQuaternion(x: 0.1, y: 0.2, z: 0.3, w: 0.9),
        rotationRate: HeadphoneVector3(x: 0.01, y: -0.02, z: 0.03),
        userAcceleration: HeadphoneVector3(x: 0.3, y: 0.4, z: 0.0),
        gravity: HeadphoneVector3(x: 0.0, y: 0.1, z: -0.995),
        magneticField: HeadphoneVector3(x: 12.0, y: -4.0, z: 30.0),
        accelerationMagnitude: 0.5,
        sensorLocation: HeadphoneSensorLocation.leftEar,
        isCalibrated: true,
        isSimulated: false,
        timestampMs: 1700000000123,
      );

      final json = sample.toJson();
      final restored = HeadphoneMotionSample.fromMap(json);
      expect(restored, equals(sample));
      expect(restored.hashCode, equals(sample.hashCode));
    });

    test('fromMap computes accelerationMagnitude fallback when omitted', () {
      final restored = HeadphoneMotionSample.fromMap(<String, dynamic>{
        'pitchDeg': 10,
        'rollDeg': 0,
        'yawDeg': -5,
        'userAcceleration': <Object?, Object?>{'x': 3, 'y': 4, 'z': 0},
        'timestampMs': 42,
      });

      expect(restored.accelerationMagnitude, closeTo(5.0, 1e-9));
      expect(restored.quaternion, HeadphoneQuaternion.identity);
      expect(restored.gravity, HeadphoneVector3.zero);
      expect(restored.userAcceleration.magnitude, closeTo(math.sqrt(25), 1e-9));
    });
  });
}
