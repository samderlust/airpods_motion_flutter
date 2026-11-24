# airpods_motion_flutter

[![pub package](https://img.shields.io/pub/v/airpods_motion_flutter.svg)](https://pub.dev/packages/airpods_motion_flutter)
[![style: flutter_lints](https://img.shields.io/badge/style-flutter__lints-0175C2.svg)](https://pub.dev/packages/flutter_lints)
[![platform: iOS | macOS](https://img.shields.io/badge/platform-iOS%20%7C%20macOS-lightgrey.svg)](https://pub.dev/packages/airpods_motion_flutter)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Buy Me A Coffee](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://www.buymeacoffee.com/samderlust)

Calibrated 6-DoF AirPods & Beats head-motion telemetry (`CMHeadphoneMotionManager`) for Flutter (iOS 14+ & macOS 14+) with live `AVAudioSession` route detection, native 1-Euro / EMA smoothing, configurable throttling, and deterministic simulator & trace replay.

## Features

- **iOS 14+ & macOS 14+ (`CMHeadphoneMotionManager`)**: Supports both CocoaPods and Swift Package Manager (SPM).
- **Live Device & Audio Route Discovery**: `AVAudioSession` route observation on iOS + `CMHeadphoneMotionManagerDelegate` connect/disconnect events, hardware model inference (`AirPods Pro`, `AirPods Pro 2`, `AirPods Max`, `AirPods 3/4`, `Beats`), and active `HeadphoneSensorLocation` (`defaultLocation`, `leftEar`, `rightEar`).
- **Thread-Safe Quaternion Calibration**: Native `calibrate()` and `resetCalibration()` using `CMAttitude.multiply(byInverseOf:)` protected by `os_unfair_lock` on a `.userInitiated` `OperationQueue`.
- **Native Signal Conditioning & Throttling**: Configurable `sampleRateHz` (`1..100` Hz) with native **None**, **EMA**, or adaptive **1-Euro** filtering before crossing the `EventChannel`.
- **Full 6-DoF Telemetry**: Calibrated `pitchDeg`, `rollDeg`, `yawDeg` (`-Left / +Right`), `quaternion`, `rotationRate` (`rad/s`), `userAcceleration` (`G`), `gravity` (`G`), `accelerationMagnitude`, `sensorLocation`, `isCalibrated`, `isSimulated`, and `timestampMs`.
- **Deterministic Simulator & Trace Replay**: `AirPodsMotionSimulator` for iOS Simulator, non-Apple platforms, and deterministic `flutter test` suites.

---

## Architecture Overview

```text
CMHeadphoneMotionManager (iOS 14+ / macOS 14+) + AVAudioSession (iOS)
        │  (.userInitiated OperationQueue + os_unfair_lock)
        ▼
Native Calibration (multiply(byInverseOf:)) + Filter (None / EMA / 1-Euro) + Rate Throttle
        │
        ├─ MethodChannel: com.samderlust.airpods_motion_flutter/control
        └─ EventChannel:  com.samderlust.airpods_motion_flutter/events
        ▼
AirpodsMotionPlatform ─▶ MethodChannelAirpodsMotion ─▶ AirPodsMotion (Dart Facade)
                                                           ▲
                                                           │ (Fallback / Replay)
                                              AirPodsMotionSimulator
```

---

## Platform Setup

### iOS (`ios/Runner/Info.plist`)

Add `NSMotionUsageDescription` so CoreMotion can access AirPods/Beats head-motion sensors:

```xml
<key>NSMotionUsageDescription</key>
<string>This app uses headphone motion sensors to track head orientation.</string>
```

Minimum deployment target in `ios/Podfile`:

```ruby
platform :ios, '14.0'
```

### macOS (`macos/Runner/Info.plist`)

Add `NSMotionUsageDescription` in `macos/Runner/Info.plist` and ensure the macOS deployment target is `14.0` or higher.

---

## Quick Start

```dart
import 'package:airpods_motion_flutter/airpods_motion_flutter.dart';

final airpods = AirPodsMotion();

Future<void> start() async {
  final device = await airpods.getDeviceInfo();
  print('Device: ${device.name} (${device.model.name})');

  airpods.deviceStream.listen((status) {
    print('Connected=${status.isConnected}, Calibrated=${status.isCalibrated}');
  });

  airpods.motionStream.listen((sample) {
    print(
      'pitch=${sample.pitchDeg.toStringAsFixed(1)}° '
      'roll=${sample.rollDeg.toStringAsFixed(1)}° '
      'yaw=${sample.yawDeg.toStringAsFixed(1)}° '
      'accel=${sample.accelerationMagnitude.toStringAsFixed(3)}G',
    );
  });

  await airpods.startTracking(
    config: const AirPodsMotionConfig(
      sampleRateHz: 15,
      filterMode: AirPodsFilterMode.oneEuro,
    ),
  );
}
```

---

## Calibration

Call `calibrate()` while the user holds a neutral head posture to capture the current `CMAttitude` as the zero-point quaternion reference (`multiply(byInverseOf:)`). Call `resetCalibration()` to revert to uncalibrated world-frame angles.

```dart
await airpods.calibrate();
// ...
await airpods.resetCalibration();
```

---

## 1-Euro vs EMA Filtering

- **`AirPodsFilterMode.ema`**: Simple exponential moving average (`smoothingAlpha` in `0.0..1.0`, default `0.25`). Low CPU cost and predictable smoothing, though lower alphas introduce lag during quick head turns.
- **`AirPodsFilterMode.oneEuro`** (Casiez et al., CHI 2012): Adapts cutoff frequency based on signal velocity (`oneEuroMinCutoff`, `oneEuroBeta`, `oneEuroDCutoff`). Eliminates resting micro-jitter while keeping fast head turns responsive.
- **`AirPodsFilterMode.none`**: Delivers raw CoreMotion telemetry at `sampleRateHz`.

A pure-Dart `OneEuroFilter` and `OneEuroPoseFilter` are also exported for filtering simulated or replayed streams in Dart.

---

## 6-DoF Telemetry Reference (`HeadphoneMotionSample`)

Each `HeadphoneMotionSample` emitted by `airpods.motionStream` represents a single conditioned 6-DoF telemetry frame from Apple's `CMHeadphoneMotionManager` (or `AirPodsMotionSimulator`).

| Field | Type | Unit / Range | Description |
| --- | --- | --- | --- |
| `pitchDeg` | `double` | Degrees (`-90°..+90°`) | **Sagittal (vertical) head tilt** around the X-axis. Positive (`+`) when looking up toward the ceiling; negative (`-`) when looking down toward a desk or phone. Filtered by the active `AirPodsFilterMode` and relative to the zero-point if calibrated. |
| `rollDeg` | `double` | Degrees (`-180°..+180°`) | **Coronal (lateral) ear-to-shoulder tilt** around the Y-axis. Positive (`+`) when tilting the head toward the right shoulder; negative (`-`) when tilting toward the left shoulder. Filtered by the active `AirPodsFilterMode`. |
| `yawDeg` | `double` | Degrees (`-180°..+180°`) | **Horizontal head rotation** around the vertical Z-axis. Normalized so negative (`-`) means turning the head **Left** and positive (`+`) means turning the head **Right** (inverting CoreMotion's raw counter-clockwise convention). Filtered by the active `AirPodsFilterMode`. |
| `quaternion` | `HeadphoneQuaternion` | Unit quaternion `(x, y, z, w)` | **3D orientation quaternion** representing the headphone attitude relative to the reference frame (or relative to the user's calibrated neutral pose after `calibrate()`). Ideal for 3D rendering, SceneKit/Unity bridges, or custom rotation math without Euler gimbal lock. |
| `rotationRate` | `HeadphoneVector3` | `rad/s` `(x, y, z)` | **Instantaneous 3-axis angular velocity** from the AirPods gyroscope in radians per second (`x`: pitch rate, `y`: roll rate, `z`: yaw rate). Useful for detecting fast head gestures such as nods, head shakes, or sudden snaps. |
| `userAcceleration` | `HeadphoneVector3` | `G` `(x, y, z)` | **Linear acceleration imparted by the user** with the 1 G gravity vector already subtracted by CoreMotion sensor fusion (`1 G ≈ 9.81 m/s²`). Useful for step cadence, jump/squat detection, or sudden translation events. |
| `gravity` | `HeadphoneVector3` | `G` `(x, y, z)` | **Normalized gravity direction vector** expressed in the headphone's reference frame (`\|\|gravity\|\| ≈ 1.0 G`). Indicates which way "down" points relative to the headphones. |
| `magneticField` | `HeadphoneVector3?` | `µT` `(x, y, z)` | **Optional calibrated magnetic field vector** in microteslas when provided by the underlying motion frame or trace replay (`null` on headphones without a magnetometer). |
| `accelerationMagnitude` | `double` | `G` (`>= 0.0`) | **Scalar Euclidean norm of `userAcceleration`** ($\sqrt{a_x^2 + a_y^2 + a_z^2}$) smoothed through the active native filter (`EMA` or `1-Euro`). Handy as a single-threshold indicator of whether the user is stationary at a desk (`< 0.05 G`) vs. walking or moving (`> 0.15 G`). |
| `sensorLocation` | `HeadphoneSensorLocation` | Enum | **Active IMU earbud source** reported by iOS 15+ / macOS 14+ (`defaultLocation`, `leftEar`, `rightEar`, or `unknown`). Lets your app detect when a user removes one AirPod and CoreMotion switches the active IMU to the other ear. |
| `isCalibrated` | `bool` | Boolean | **`true` when a zero-point reference attitude is active** via `calibrate()`. When `false`, `pitchDeg`, `rollDeg`, `yawDeg`, and `quaternion` are reported in CoreMotion's uncalibrated startup frame. |
| `isSimulated` | `bool` | Boolean | **`true` when the sample was generated by `AirPodsMotionSimulator`** (synthetic loop, manual `emitEuler`/`emitSample`, or `replayTrace`), and `false` when captured from physical AirPods/Beats hardware. |
| `timestampMs` | `int` | Epoch `ms` | **Wall-clock capture timestamp** in milliseconds since Unix epoch (`DateTime.fromMillisecondsSinceEpoch(sample.timestampMs)`). Used for inter-frame delta calculations and deterministic trace recording/replay. |

---

## Simulator & Deterministic Test Replay

When `autoFallbackToSimulator` is `true` (default) and native motion hardware is unavailable (e.g., iOS Simulator, Linux, or unit tests), `AirPodsMotion` automatically enters simulator mode.

You can also drive `airpods.simulator` directly:

```dart
// Inject a single synthetic frame
airpods.simulator.emitEuler(pitchDeg: -12.0, yawDeg: 18.0);

// Run procedural sinusoidal motion
airpods.simulator.startSyntheticLoop(sampleRateHz: 15);

// Deterministically replay a recorded JSON trace at 2x speed
await airpods.simulator.replayTrace(recordedSamples, speedMultiplier: 2.0);
```
