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
