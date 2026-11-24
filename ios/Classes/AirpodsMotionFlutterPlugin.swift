import CoreMotion
import Foundation

#if os(iOS)
import AVFoundation
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif

private enum NativeFilterMode: String {
  case none
  case ema
  case oneEuro
}

/// Adaptive 1-Euro low-pass filter (Casiez, Roussel, & Vogel, CHI 2012).
private final class NativeOneEuroFilter {
  var minCutoff: Double
  var beta: Double
  var dCutoff: Double

  private var lastTimestampSec: Double?
  private var xPrev: Double?
  private var dxPrev: Double = 0.0

  init(minCutoff: Double = 1.0, beta: Double = 0.007, dCutoff: Double = 1.0) {
    self.minCutoff = max(1e-4, minCutoff)
    self.beta = max(0.0, beta)
    self.dCutoff = max(1e-4, dCutoff)
  }

  func reset() {
    lastTimestampSec = nil
    xPrev = nil
    dxPrev = 0.0
  }

  func filter(_ value: Double, timestampSec: Double) -> Double {
    guard let prevTs = lastTimestampSec, let prevX = xPrev else {
      lastTimestampSec = timestampSec
      xPrev = value
      dxPrev = 0.0
      return value
    }

    let dt = timestampSec - prevTs
    guard dt > 0 else {
      return prevX
    }
    lastTimestampSec = timestampSec

    let dx = (value - prevX) / dt
    let alphaD = smoothingFactor(dt: dt, cutoff: dCutoff)
    let dxHat = exponentialSmoothing(alpha: alphaD, x: dx, xPrev: dxPrev)

    let cutoff = minCutoff + beta * abs(dxHat)
    let alpha = smoothingFactor(dt: dt, cutoff: cutoff)
    let xHat = exponentialSmoothing(alpha: alpha, x: value, xPrev: prevX)

    xPrev = xHat
    dxPrev = dxHat
    return xHat
  }

  private func smoothingFactor(dt: Double, cutoff: Double) -> Double {
    let r = 2.0 * Double.pi * cutoff * dt
    return r / (r + 1.0)
  }

  private func exponentialSmoothing(alpha: Double, x: Double, xPrev: Double) -> Double {
    return alpha * x + (1.0 - alpha) * xPrev
  }
}

/// Bridges Apple's CMHeadphoneMotionManager (and AVAudioSession on iOS) to Flutter
/// with thread-safe quaternion calibration, EMA / 1-Euro filtering, and configurable throttling.
public final class AirpodsMotionFlutterPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, CMHeadphoneMotionManagerDelegate {
  private static let methodChannelName = "com.samderlust.airpods_motion_flutter/control"
  private static let eventChannelName = "com.samderlust.airpods_motion_flutter/events"

  private var eventSink: FlutterEventSink?
  private var motionManager: CMHeadphoneMotionManager?
  private var motionLock = os_unfair_lock()

  private let motionQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "com.samderlust.airpods_motion_flutter.queue"
    queue.maxConcurrentOperationCount = 1
    queue.qualityOfService = .userInitiated
    return queue
  }()

  private var referenceAttitude: CMAttitude?
  private var latestAttitude: CMAttitude?
  private var latestSensorLocation: String = "unknown"
  private var isHeadphoneConnected = false

  #if os(iOS)
  private var routeObserver: NSObjectProtocol?
  #endif

  // Configurable sampling & filter state (protected by motionLock)
  private var configuredSampleRateHz: Int = 15
  private var minEmitIntervalMs: Int64 = 66
  private var filterMode: NativeFilterMode = .ema
  private var smoothingAlpha: Double = 0.25

  private var hasFilteredSample = false
  private var filteredPitchDeg: Double = 0.0
  private var filteredRollDeg: Double = 0.0
  private var filteredYawDeg: Double = 0.0
  private var filteredAccel: Double = 0.0
  private var lastEmitTimeMs: Int64 = 0

  private var pitchOneEuro = NativeOneEuroFilter()
  private var rollOneEuro = NativeOneEuroFilter()
  private var yawOneEuro = NativeOneEuroFilter()
  private var accelOneEuro = NativeOneEuroFilter()

  deinit {
    removeAudioRouteObserver()
    stopTracking()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = AirpodsMotionFlutterPlugin()
    #if os(iOS)
    let messenger = registrar.messenger()
    #else
    let messenger = registrar.messenger
    #endif

    let methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: messenger
    )
    registrar.addMethodCallDelegate(instance, channel: methodChannel)

    let eventChannel = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: messenger
    )
    eventChannel.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getDeviceInfo":
      result(currentDeviceInfo())
    case "startTracking":
      startTracking(arguments: call.arguments, result: result)
    case "stopTracking":
      stopTracking()
      emitDeviceUpdate()
      result(true)
    case "calibrate":
      os_unfair_lock_lock(&motionLock)
      let latest = latestAttitude?.copy() as? CMAttitude
      if let latest {
        referenceAttitude = latest
        resetFiltersLocked()
      }
      os_unfair_lock_unlock(&motionLock)

      if latest != nil {
        emitDeviceUpdate()
        result(true)
      } else {
        result(false)
      }
    case "resetCalibration":
      os_unfair_lock_lock(&motionLock)
      referenceAttitude = nil
      resetFiltersLocked()
      os_unfair_lock_unlock(&motionLock)

      emitDeviceUpdate()
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    observeAudioRouteChanges()
    emitDeviceUpdate()
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    removeAudioRouteObserver()
    stopTracking()
    return nil
  }

  public func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
    os_unfair_lock_lock(&motionLock)
    isHeadphoneConnected = true
    os_unfair_lock_unlock(&motionLock)

    DispatchQueue.main.async { [weak self] in
      self?.emitDeviceUpdate()
    }
  }

  public func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
    os_unfair_lock_lock(&motionLock)
    isHeadphoneConnected = false
    latestSensorLocation = "unknown"
    resetFiltersLocked()
    os_unfair_lock_unlock(&motionLock)

    DispatchQueue.main.async { [weak self] in
      self?.emitDeviceUpdate()
    }
  }

  private func observeAudioRouteChanges() {
    #if os(iOS)
    removeAudioRouteObserver()
    routeObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification,
      object: AVAudioSession.sharedInstance(),
      queue: .main
    ) { [weak self] _ in
      self?.emitDeviceUpdate()
    }
    #endif
  }

  private func removeAudioRouteObserver() {
    #if os(iOS)
    if let observer = routeObserver {
      NotificationCenter.default.removeObserver(observer)
      routeObserver = nil
    }
    #endif
  }

  private func emitDeviceUpdate() {
    var payload = currentDeviceInfo()
    payload["type"] = "device"
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(payload)
    }
  }

  private func currentDeviceInfo() -> [String: Any] {
    var bluetoothName: String?
    var hasBluetoothRoute = false

    #if os(iOS)
    let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
    let bluetoothOutput = outputs.first {
      $0.portType == .bluetoothA2DP || $0.portType == .bluetoothHFP || $0.portType == .bluetoothLE
    }
    if let bluetoothOutput {
      bluetoothName = bluetoothOutput.portName
      hasBluetoothRoute = true
    }
    #endif

    let manager = ensureMotionManager()
    let isAvailable = manager.isDeviceMotionAvailable
    let isActive = manager.isDeviceMotionActive

    os_unfair_lock_lock(&motionLock)
    let motionConnected = isHeadphoneConnected
    let isCalibrated = referenceAttitude != nil
    let sampleRateHz = isAvailable ? configuredSampleRateHz : 0
    let sensorLocation = latestSensorLocation
    os_unfair_lock_unlock(&motionLock)

    let connected = hasBluetoothRoute || motionConnected || isActive
    let resolvedName = bluetoothName ?? (connected ? "AirPods" : "No Headphones")

    return [
      "name": resolvedName,
      "isConnected": connected,
      "isMotionAvailable": isAvailable,
      "isActive": isActive,
      "sampleRateHz": sampleRateHz,
      "isCalibrated": isCalibrated,
      "sensorLocation": sensorLocation,
      "isSimulated": false,
    ]
  }

  private func startTracking(arguments: Any?, result: @escaping FlutterResult) {
    applyConfig(arguments: arguments)

    let manager = ensureMotionManager()
    guard manager.isDeviceMotionAvailable else {
      result(false)
      return
    }

    manager.delegate = self

    if manager.isDeviceMotionActive {
      emitDeviceUpdate()
      result(true)
      return
    }

    manager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, error in
      guard let self, let motion, error == nil else { return }

      let relative = motion.attitude.copy() as? CMAttitude ?? motion.attitude
      let acc = motion.userAcceleration
      let rot = motion.rotationRate
      let grav = motion.gravity
      let rawAcc = sqrt(acc.x * acc.x + acc.y * acc.y + acc.z * acc.z)
      let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
      let monotonicSec = ProcessInfo.processInfo.systemUptime
      let locationName = self.sensorLocationName(motion)

      var shouldEmitDeviceUpdate = false
      var posePayload: [String: Any]?

      os_unfair_lock_lock(&self.motionLock)
      if !self.isHeadphoneConnected {
        self.isHeadphoneConnected = true
        shouldEmitDeviceUpdate = true
      }
      if self.latestSensorLocation != locationName {
        self.latestSensorLocation = locationName
        shouldEmitDeviceUpdate = true
      }
      self.latestAttitude = motion.attitude.copy() as? CMAttitude

      let isCalibrated = self.referenceAttitude != nil
      if let ref = self.referenceAttitude {
        relative.multiply(byInverseOf: ref)
      }

      let radToDeg = 180.0 / Double.pi
      let rawPitch = relative.pitch * radToDeg
      let rawRoll = relative.roll * radToDeg
      // CoreMotion yaw is +CCW (left); negate so -yaw = Left and +yaw = Right.
      let rawYaw = -relative.yaw * radToDeg

      let outPitch: Double
      let outRoll: Double
      let outYaw: Double
      let outAccel: Double

      switch self.filterMode {
      case .none:
        outPitch = rawPitch
        outRoll = rawRoll
        outYaw = rawYaw
        outAccel = rawAcc
      case .ema:
        if !self.hasFilteredSample {
          self.filteredPitchDeg = rawPitch
          self.filteredRollDeg = rawRoll
          self.filteredYawDeg = rawYaw
          self.filteredAccel = rawAcc
          self.hasFilteredSample = true
        } else {
          let a = self.smoothingAlpha
          self.filteredPitchDeg += a * (rawPitch - self.filteredPitchDeg)
          self.filteredRollDeg += a * (rawRoll - self.filteredRollDeg)
          self.filteredYawDeg += a * (rawYaw - self.filteredYawDeg)
          self.filteredAccel += a * (rawAcc - self.filteredAccel)
        }
        outPitch = self.filteredPitchDeg
        outRoll = self.filteredRollDeg
        outYaw = self.filteredYawDeg
        outAccel = self.filteredAccel
      case .oneEuro:
        outPitch = self.pitchOneEuro.filter(rawPitch, timestampSec: monotonicSec)
        outRoll = self.rollOneEuro.filter(rawRoll, timestampSec: monotonicSec)
        outYaw = self.yawOneEuro.filter(rawYaw, timestampSec: monotonicSec)
        outAccel = self.accelOneEuro.filter(rawAcc, timestampSec: monotonicSec)
      }

      if nowMs - self.lastEmitTimeMs >= self.minEmitIntervalMs {
        self.lastEmitTimeMs = nowMs
        let q = relative.quaternion
        posePayload = [
          "type": "pose",
          "pitchDeg": outPitch,
          "rollDeg": outRoll,
          "yawDeg": outYaw,
          "quaternion": [
            "x": q.x,
            "y": q.y,
            "z": q.z,
            "w": q.w,
          ],
          "rotationRate": [
            "x": rot.x,
            "y": rot.y,
            "z": rot.z,
          ],
          "userAcceleration": [
            "x": acc.x,
            "y": acc.y,
            "z": acc.z,
          ],
          "gravity": [
            "x": grav.x,
            "y": grav.y,
            "z": grav.z,
          ],
          "accelerationMagnitude": outAccel,
          "sensorLocation": locationName,
          "isCalibrated": isCalibrated,
          "isSimulated": false,
          "timestampMs": nowMs,
        ]
      }
      os_unfair_lock_unlock(&self.motionLock)

      if shouldEmitDeviceUpdate || posePayload != nil {
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          if shouldEmitDeviceUpdate {
            var devicePayload = self.currentDeviceInfo()
            devicePayload["type"] = "device"
            self.eventSink?(devicePayload)
          }
          if let payload = posePayload {
            self.eventSink?(payload)
          }
        }
      }
    }

    emitDeviceUpdate()
    result(true)
  }

  private func stopTracking() {
    if let manager = motionManager, manager.isDeviceMotionActive {
      manager.stopDeviceMotionUpdates()
    }
    os_unfair_lock_lock(&motionLock)
    resetFiltersLocked()
    os_unfair_lock_unlock(&motionLock)
  }

  private func applyConfig(arguments: Any?) {
    let args = arguments as? [String: Any] ?? [:]
    let rate = min(100, max(1, (args["sampleRateHz"] as? NSNumber)?.intValue ?? 15))
    let modeString = args["filterMode"] as? String ?? "ema"
    let mode = NativeFilterMode(rawValue: modeString) ?? .ema
    let alpha = min(1.0, max(0.0, (args["smoothingAlpha"] as? NSNumber)?.doubleValue ?? 0.25))
    let minCutoff = max(1e-4, (args["oneEuroMinCutoff"] as? NSNumber)?.doubleValue ?? 1.0)
    let beta = max(0.0, (args["oneEuroBeta"] as? NSNumber)?.doubleValue ?? 0.007)
    let dCutoff = max(1e-4, (args["oneEuroDCutoff"] as? NSNumber)?.doubleValue ?? 1.0)

    os_unfair_lock_lock(&motionLock)
    configuredSampleRateHz = rate
    minEmitIntervalMs = Int64(max(10, 1000 / rate))
    filterMode = mode
    smoothingAlpha = alpha
    pitchOneEuro = NativeOneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: dCutoff)
    rollOneEuro = NativeOneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: dCutoff)
    yawOneEuro = NativeOneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: dCutoff)
    accelOneEuro = NativeOneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: dCutoff)
    hasFilteredSample = false
    lastEmitTimeMs = 0
    os_unfair_lock_unlock(&motionLock)
  }

  /// Must be called with `motionLock` held.
  private func resetFiltersLocked() {
    hasFilteredSample = false
    lastEmitTimeMs = 0
    pitchOneEuro.reset()
    rollOneEuro.reset()
    yawOneEuro.reset()
    accelOneEuro.reset()
  }

  private func ensureMotionManager() -> CMHeadphoneMotionManager {
    if let existing = motionManager {
      return existing
    }
    let created = CMHeadphoneMotionManager()
    motionManager = created
    return created
  }

  private func sensorLocationName(_ motion: CMDeviceMotion) -> String {
    if #available(iOS 15.0, macOS 14.0, *) {
      switch motion.sensorLocation {
      case .default:
        return "defaultLocation"
      case .headphoneLeft:
        return "leftEar"
      case .headphoneRight:
        return "rightEar"
      @unknown default:
        return "unknown"
      }
    }
    return "unknown"
  }
}
