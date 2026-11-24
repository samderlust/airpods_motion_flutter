## 0.1.2

- Cleaned up `README.md` documentation.

## 0.1.1

- Added Apple privacy manifests (`PrivacyInfo.xcprivacy`) for iOS and macOS (CocoaPods resource bundles and SPM resources) and replaced `ProcessInfo.processInfo.systemUptime` with hardware-synchronized `motion.timestamp` (`ITMS-91053` compliance).
- Deduplicated CocoaPods and Swift Package Manager plugin sources by removing `ios/Classes/` and `macos/Classes/` and pointing both podspecs at `airpods_motion_flutter/Sources/airpods_motion_flutter/`.
- Added CoreMotion authorization status reporting (`HeadphoneAuthorizationStatus`, `HeadphoneDevice.authorizationStatus`, `getAuthorizationStatus()`) and runtime error forwarding (`AirPodsMotionError`, `errorStream`).
- Added `±180°` Euler angle wrap-around unwrapping to both native Swift (EMA & `NativeOneEuroFilter`) and pure-Dart (`OneEuroFilter` / `OneEuroPoseFilter`).
- Switched native emission throttling to monotonic `motion.timestamp` deltas instead of wall-clock `Date()`, and reported `sampleRateHz = 0` when tracking is inactive.
- Added `SimulatorFallbackMode` (`none`, `manual`, `syntheticLoop`) while keeping `autoFallbackToSimulator` backwards-compatible, plus `AirPodsMotionSimulator.calibrate()`, `resetCalibration()`, and `isCalibrated` offset subtraction.
- Protected `AirPodsMotion.instance.dispose()` from closing singleton broadcast streams and ensured `dispose()` stops native tracking on non-singleton instances.

## 0.1.0

- Initial release of `airpods_motion_flutter`.
- Added iOS 14+ and macOS 14+ `CMHeadphoneMotionManager` plugin with CocoaPods and Swift Package Manager (SPM) support.
- Added live `AVAudioSession` Bluetooth route detection on iOS and `CMHeadphoneMotionManagerDelegate` connect/disconnect events.
- Added thread-safe native quaternion zero-point calibration (`calibrate()` and `resetCalibration()`).
- Added native signal conditioning (`none`, `ema`, and `oneEuro` adaptive filtering) with configurable `sampleRateHz` throttling (`1..100` Hz).
- Added full 6-DoF `HeadphoneMotionSample` telemetry (`pitchDeg`, `rollDeg`, `yawDeg`, `quaternion`, `rotationRate`, `userAcceleration`, `gravity`, `accelerationMagnitude`, `sensorLocation`, `isCalibrated`, `isSimulated`, `timestampMs`).
- Added pure-Dart `OneEuroFilter` and `OneEuroPoseFilter` utilities.
- Added `AirPodsMotionSimulator` with single-frame injection, synthetic motion loop, and deterministic trace replay.
- Added example application and comprehensive test suite.
