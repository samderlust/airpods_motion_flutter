import 'package:airpods_motion_flutter/airpods_motion_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const controlChannel = MethodChannel(
    MethodChannelAirpodsMotion.methodChannelName,
  );
  const eventChannelMethod = MethodChannel(
    MethodChannelAirpodsMotion.eventChannelName,
  );
  const codec = StandardMethodCodec();

  late List<MethodCall> recordedCalls;
  late bool nativeStartShouldSucceed;
  late bool nativeCalibrateResult;
  late bool nativeResetResult;
  late String nativeAuthorizationStatus;
  late Map<String, dynamic> nativeDevicePayload;

  setUp(() {
    recordedCalls = <MethodCall>[];
    nativeStartShouldSucceed = true;
    nativeCalibrateResult = true;
    nativeResetResult = true;
    nativeAuthorizationStatus = 'authorized';
    nativeDevicePayload = <String, dynamic>{
      'name': 'AirPods Pro 2',
      'isConnected': true,
      'isMotionAvailable': true,
      'isActive': false,
      'sampleRateHz': 0,
      'isCalibrated': false,
      'sensorLocation': 'leftEar',
      'authorizationStatus': 'authorized',
      'isSimulated': false,
    };

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(controlChannel, (MethodCall call) async {
          recordedCalls.add(call);
          switch (call.method) {
            case 'getDeviceInfo':
              return nativeDevicePayload;
            case 'getAuthorizationStatus':
              return nativeAuthorizationStatus;
            case 'startTracking':
              return nativeStartShouldSucceed;
            case 'stopTracking':
              return true;
            case 'calibrate':
              return nativeCalibrateResult;
            case 'resetCalibration':
              return nativeResetResult;
            default:
              return null;
          }
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(eventChannelMethod, (MethodCall call) async {
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(controlChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(eventChannelMethod, null);
  });

  Future<void> pushNativeEvent(Map<String, dynamic> event) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          MethodChannelAirpodsMotion.eventChannelName,
          codec.encodeSuccessEnvelope(event),
          (_) {},
        );
  }

  group('MethodChannelAirpodsMotion & AirPodsMotion', () {
    test('getDeviceInfo parses hardware model and sensor location', () async {
      final airpods = AirPodsMotion(platform: MethodChannelAirpodsMotion());
      addTearDown(airpods.dispose);

      final device = await airpods.getDeviceInfo();
      expect(device.name, 'AirPods Pro 2');
      expect(device.model, HeadphoneHardwareModel.airPodsPro2);
      expect(device.isConnected, isTrue);
      expect(device.isMotionAvailable, isTrue);
      expect(device.sensorLocation, HeadphoneSensorLocation.leftEar);
      expect(
        device.authorizationStatus,
        HeadphoneAuthorizationStatus.authorized,
      );
      expect(device.isSimulated, isFalse);

      nativeAuthorizationStatus = 'denied';
      expect(
        await airpods.getAuthorizationStatus(),
        HeadphoneAuthorizationStatus.denied,
      );
    });

    test(
      'startTracking forwards config, calibrate and resetCalibration work',
      () async {
        final airpods = AirPodsMotion(platform: MethodChannelAirpodsMotion());
        addTearDown(airpods.dispose);

        const config = AirPodsMotionConfig(
          sampleRateHz: 30,
          filterMode: AirPodsFilterMode.oneEuro,
          smoothingAlpha: 0.35,
          oneEuroMinCutoff: 1.2,
          oneEuroBeta: 0.015,
          oneEuroDCutoff: 1.5,
          autoFallbackToSimulator: false,
        );

        final started = await airpods.startTracking(config: config);
        expect(started, isTrue);
        expect(airpods.isTracking, isTrue);
        expect(airpods.isSimulating, isFalse);

        final startCall = recordedCalls.firstWhere(
          (c) => c.method == 'startTracking',
        );
        expect(startCall.arguments, equals(config.toMap()));

        expect(await airpods.calibrate(), isTrue);
        expect(await airpods.resetCalibration(), isTrue);
        await airpods.stopTracking();
        expect(airpods.isTracking, isFalse);

        expect(
          recordedCalls.map((c) => c.method),
          containsAllInOrder([
            'startTracking',
            'calibrate',
            'resetCalibration',
            'stopTracking',
          ]),
        );
      },
    );

    test(
      'EventChannel dispatches deviceStream and 6-DoF motionStream',
      () async {
        final airpods = AirPodsMotion(platform: MethodChannelAirpodsMotion());
        addTearDown(airpods.dispose);

        final devices = <HeadphoneDevice>[];
        final samples = <HeadphoneMotionSample>[];
        final deviceSub = airpods.deviceStream.listen(devices.add);
        final motionSub = airpods.motionStream.listen(samples.add);

        await airpods.startTracking();

        await pushNativeEvent(<String, dynamic>{
          'type': 'device',
          'name': 'AirPods Max',
          'isConnected': true,
          'isMotionAvailable': true,
          'isActive': true,
          'sampleRateHz': 15,
          'isCalibrated': true,
          'sensorLocation': 'defaultLocation',
          'isSimulated': false,
        });

        await pushNativeEvent(<String, dynamic>{
          'type': 'pose',
          'pitchDeg': -6.25,
          'rollDeg': 1.5,
          'yawDeg': 11.0,
          'quaternion': <String, dynamic>{
            'x': 0.01,
            'y': 0.02,
            'z': 0.03,
            'w': 0.999,
          },
          'rotationRate': <String, dynamic>{'x': 0.1, 'y': 0.2, 'z': 0.3},
          'userAcceleration': <String, dynamic>{'x': 0.0, 'y': 0.03, 'z': 0.04},
          'gravity': <String, dynamic>{'x': 0.0, 'y': 0.0, 'z': -1.0},
          'accelerationMagnitude': 0.05,
          'sensorLocation': 'rightEar',
          'isCalibrated': true,
          'isSimulated': false,
          'timestampMs': 1700000000999,
        });

        await Future<void>.delayed(Duration.zero);
        await deviceSub.cancel();
        await motionSub.cancel();

        expect(devices, hasLength(1));
        expect(devices.first.model, HeadphoneHardwareModel.airPodsMax);
        expect(devices.first.isCalibrated, isTrue);

        expect(samples, hasLength(1));
        final s = samples.first;
        expect(s.pitchDeg, -6.25);
        expect(s.rollDeg, 1.5);
        expect(s.yawDeg, 11.0);
        expect(s.quaternion.w, 0.999);
        expect(s.rotationRate.z, 0.3);
        expect(s.userAcceleration.z, 0.04);
        expect(s.gravity.z, -1.0);
        expect(s.accelerationMagnitude, 0.05);
        expect(s.sensorLocation, HeadphoneSensorLocation.rightEar);
        expect(s.isCalibrated, isTrue);
        expect(s.timestampMs, 1700000000999);
      },
    );

    test(
      'falls back to simulator when hardware is unavailable and enabled',
      () async {
        nativeStartShouldSucceed = false;
        final airpods = AirPodsMotion(platform: MethodChannelAirpodsMotion());
        addTearDown(airpods.dispose);

        final devices = <HeadphoneDevice>[];
        final samples = <HeadphoneMotionSample>[];
        final deviceSub = airpods.deviceStream.listen(devices.add);
        final motionSub = airpods.motionStream.listen(samples.add);

        final nativeStarted = await airpods.startTracking(
          config: const AirPodsMotionConfig(
            sampleRateHz: 50,
            autoFallbackToSimulator: true,
          ),
        );

        expect(nativeStarted, isFalse);
        expect(airpods.isSimulating, isTrue);
        expect(airpods.isTracking, isTrue);
        expect(airpods.simulator.isRunning, isTrue);

        await Future<void>.delayed(const Duration(milliseconds: 55));
        expect(samples, isNotEmpty);
        expect(samples.first.isSimulated, isTrue);

        // Calibration updates simulated device status without calling native channel.
        expect(await airpods.calibrate(), isTrue);
        final calDevice = await airpods.getDeviceInfo();
        expect(calDevice.isCalibrated, isTrue);
        expect(calDevice.isSimulated, isTrue);

        expect(await airpods.resetCalibration(), isTrue);
        final resetDevice = await airpods.getDeviceInfo();
        expect(resetDevice.isCalibrated, isFalse);

        await airpods.stopTracking();
        expect(airpods.isSimulating, isFalse);
        expect(airpods.simulator.isRunning, isFalse);

        await deviceSub.cancel();
        await motionSub.cancel();
      },
    );

    test(
      'does not start simulator when autoFallbackToSimulator is false',
      () async {
        nativeStartShouldSucceed = false;
        final airpods = AirPodsMotion(platform: MethodChannelAirpodsMotion());
        addTearDown(airpods.dispose);

        final started = await airpods.startTracking(
          config: const AirPodsMotionConfig(autoFallbackToSimulator: false),
        );
        expect(started, isFalse);
        expect(airpods.isSimulating, isFalse);
        expect(airpods.isTracking, isFalse);
        expect(airpods.simulator.isRunning, isFalse);
      },
    );

    test(
      'handles MissingPluginException gracefully without mock handlers',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(controlChannel, null);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(eventChannelMethod, null);

        final airpods = AirPodsMotion(platform: MethodChannelAirpodsMotion());
        addTearDown(airpods.dispose);

        final info = await airpods.getDeviceInfo();
        expect(info.isSimulated, isTrue);
        expect(info.isMotionAvailable, isFalse);

        final started = await airpods.startTracking(
          config: const AirPodsMotionConfig(autoFallbackToSimulator: false),
        );
        expect(started, isFalse);
        await airpods.stopTracking();
      },
    );

    test('forwards native type: error events onto errorStream', () async {
      final airpods = AirPodsMotion(platform: MethodChannelAirpodsMotion());
      addTearDown(airpods.dispose);

      final errors = <AirPodsMotionError>[];
      final sub = airpods.errorStream.listen(errors.add);

      await airpods.startTracking();
      await pushNativeEvent(<String, dynamic>{
        'type': 'error',
        'code': 'CMErrorDomain:105',
        'message': 'Headphone motion authorization denied.',
        'authorizationStatus': 'denied',
      });

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(errors, hasLength(1));
      expect(errors.first.code, 'CMErrorDomain:105');
      expect(errors.first.message, 'Headphone motion authorization denied.');
      expect(
        errors.first.authorizationStatus,
        HeadphoneAuthorizationStatus.denied,
      );
    });

    test(
      'SimulatorFallbackMode.manual activates simulator without synthetic loop and supports manual emitEuler + calibrate',
      () async {
        nativeStartShouldSucceed = false;
        final airpods = AirPodsMotion(platform: MethodChannelAirpodsMotion());
        addTearDown(airpods.dispose);

        final samples = <HeadphoneMotionSample>[];
        final motionSub = airpods.motionStream.listen(samples.add);

        final nativeStarted = await airpods.startTracking(
          config: const AirPodsMotionConfig(
            sampleRateHz: 30,
            simulatorFallbackMode: SimulatorFallbackMode.manual,
          ),
        );

        expect(nativeStarted, isFalse);
        expect(airpods.isSimulating, isTrue);
        expect(airpods.isTracking, isTrue);
        expect(airpods.simulator.isRunning, isFalse);
        expect(
          await airpods.getAuthorizationStatus(),
          HeadphoneAuthorizationStatus.authorized,
        );

        await Future<void>.delayed(const Duration(milliseconds: 45));
        expect(samples, isEmpty);

        airpods.simulator.emitEuler(pitchDeg: 10.0, yawDeg: -20.0);
        expect(await airpods.calibrate(), isTrue);
        airpods.simulator.emitEuler(pitchDeg: 15.0, yawDeg: -10.0);
        await Future<void>.delayed(Duration.zero);
        await motionSub.cancel();

        expect(samples, hasLength(2));
        expect(samples[0].isCalibrated, isFalse);
        expect(samples[1].pitchDeg, closeTo(5.0, 1e-9));
        expect(samples[1].yawDeg, closeTo(10.0, 1e-9));
        expect(samples[1].isCalibrated, isTrue);
      },
    );

    test('dispose() calls native stopTracking() on non-singleton instance', () async {
      final airpods = AirPodsMotion(platform: MethodChannelAirpodsMotion());
      await airpods.startTracking();
      recordedCalls.clear();

      await airpods.dispose();

      expect(recordedCalls.map((c) => c.method), contains('stopTracking'));
      expect(airpods.isTracking, isFalse);
    });

    test(
      'AirPodsMotion.instance.dispose() stops tracking without closing singleton streams',
      () async {
        nativeStartShouldSucceed = false;
        final instance = AirPodsMotion.instance;
        await instance.startTracking(
          config: const AirPodsMotionConfig(
            simulatorFallbackMode: SimulatorFallbackMode.manual,
          ),
        );
        expect(instance.isTracking, isTrue);

        await instance.dispose();
        expect(instance.isTracking, isFalse);
        expect(instance.isSimulating, isFalse);

        // Singleton streams remain open and reusable after dispose().
        final samples = <HeadphoneMotionSample>[];
        final sub = instance.motionStream.listen(samples.add);
        await instance.startTracking(
          config: const AirPodsMotionConfig(
            simulatorFallbackMode: SimulatorFallbackMode.manual,
          ),
        );
        instance.simulator.emitEuler(pitchDeg: 4.0);
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        await instance.stopTracking();

        expect(samples, hasLength(1));
        expect(samples.first.pitchDeg, 4.0);
      },
    );
  });
}
