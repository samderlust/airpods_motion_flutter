/// Inferred Apple/Beats headphone hardware family from audio route naming.
enum HeadphoneHardwareModel {
  /// AirPods Pro (1st generation or generic AirPods Pro name).
  airPodsPro,

  /// AirPods Pro (2nd generation).
  airPodsPro2,

  /// AirPods Max.
  airPodsMax,

  /// AirPods (3rd generation).
  airPodsGen3,

  /// AirPods (4th generation).
  airPodsGen4,

  /// Spatial-audio-capable Beats headphones (e.g. Beats Fit Pro, Studio Pro).
  beats,

  /// Unrecognized or generic Bluetooth headphone name.
  unknown;

  /// Infers a [HeadphoneHardwareModel] from an audio output route [name].
  static HeadphoneHardwareModel inferFromName(String name) {
    final lower = name.trim().toLowerCase();
    if (lower.isEmpty) {
      return HeadphoneHardwareModel.unknown;
    }
    // Check Beats models first because names like "Beats Fit Pro" contain "pro".
    if (lower.contains('beats') ||
        lower.contains('powerbeats') ||
        lower.contains('studio') ||
        lower.contains('solo')) {
      return HeadphoneHardwareModel.beats;
    }
    if (lower.contains('max')) {
      return HeadphoneHardwareModel.airPodsMax;
    }
    if (lower.contains('pro 2') ||
        lower.contains('pro2') ||
        lower.contains('pro (2')) {
      return HeadphoneHardwareModel.airPodsPro2;
    }
    if (lower.contains('pro')) {
      return HeadphoneHardwareModel.airPodsPro;
    }
    if (lower.contains('4')) {
      return HeadphoneHardwareModel.airPodsGen4;
    }
    if (lower.contains('3')) {
      return HeadphoneHardwareModel.airPodsGen3;
    }
    return HeadphoneHardwareModel.unknown;
  }

  /// Parses a [HeadphoneHardwareModel] from a serialized enum name.
  static HeadphoneHardwareModel fromWireValue(String? value) {
    for (final item in values) {
      if (item.name == value) {
        return item;
      }
    }
    return HeadphoneHardwareModel.unknown;
  }
}

/// Active IMU earbud/headphone location reported by `CMDeviceMotion.SensorLocation`.
enum HeadphoneSensorLocation {
  /// Default or combined head sensor frame.
  defaultLocation,

  /// Motion telemetry sourced from the left earbud.
  leftEar,

  /// Motion telemetry sourced from the right earbud.
  rightEar,

  /// Sensor location unavailable (e.g., iOS 14 or disconnected).
  unknown;

  /// Parses a [HeadphoneSensorLocation] from its native wire representation.
  static HeadphoneSensorLocation fromWireValue(String? value) {
    switch (value) {
      case 'defaultLocation':
      case 'default':
      case '0':
        return HeadphoneSensorLocation.defaultLocation;
      case 'leftEar':
      case 'headphoneLeft':
      case 'left':
      case '1':
        return HeadphoneSensorLocation.leftEar;
      case 'rightEar':
      case 'headphoneRight':
      case 'right':
      case '2':
        return HeadphoneSensorLocation.rightEar;
      default:
        return HeadphoneSensorLocation.unknown;
    }
  }
}

/// Snapshot of the connected headphone device, motion capability, and tracking state.
class HeadphoneDevice {
  /// Creates a [HeadphoneDevice] status snapshot.
  const HeadphoneDevice({
    required this.name,
    this.model = HeadphoneHardwareModel.unknown,
    this.isConnected = false,
    this.isMotionAvailable = false,
    this.isActive = false,
    this.sampleRateHz = 0,
    this.isCalibrated = false,
    this.sensorLocation = HeadphoneSensorLocation.unknown,
    this.isSimulated = false,
  });

  /// Default snapshot representing no connected headphones.
  static const HeadphoneDevice disconnected = HeadphoneDevice(
    name: 'No Headphones',
  );

  /// Deserializes a [HeadphoneDevice] from a platform channel or JSON map.
  factory HeadphoneDevice.fromMap(Map<String, dynamic> map) {
    final name = (map['name'] as String?) ?? 'Headphones';
    final wireModel = map['model'] as String?;
    final model =
        wireModel != null
            ? HeadphoneHardwareModel.fromWireValue(wireModel)
            : HeadphoneHardwareModel.inferFromName(name);

    return HeadphoneDevice(
      name: name,
      model: model,
      isConnected: (map['isConnected'] as bool?) ?? false,
      isMotionAvailable: (map['isMotionAvailable'] as bool?) ?? false,
      isActive: (map['isActive'] as bool?) ?? false,
      sampleRateHz: (map['sampleRateHz'] as num?)?.toInt() ?? 0,
      isCalibrated: (map['isCalibrated'] as bool?) ?? false,
      sensorLocation: HeadphoneSensorLocation.fromWireValue(
        map['sensorLocation'] as String?,
      ),
      isSimulated: (map['isSimulated'] as bool?) ?? false,
    );
  }

  /// Display name reported by `AVAudioSession` or the simulator.
  final String name;

  /// Inferred hardware family.
  final HeadphoneHardwareModel model;

  /// Whether compatible Bluetooth headphones are currently connected.
  final bool isConnected;

  /// Whether `CMHeadphoneMotionManager.isDeviceMotionAvailable` is true.
  final bool isMotionAvailable;

  /// Whether `CMHeadphoneMotionManager.isDeviceMotionActive` is true (or simulator is active).
  final bool isActive;

  /// Effective telemetry emission rate in Hz.
  final int sampleRateHz;

  /// Whether a zero-point calibration reference is currently active.
  final bool isCalibrated;

  /// Active IMU sensor location (`leftEar`, `rightEar`, `defaultLocation`, or `unknown`).
  final HeadphoneSensorLocation sensorLocation;

  /// Whether this device status represents simulated telemetry.
  final bool isSimulated;

  /// Returns a copy of this [HeadphoneDevice] with the given fields replaced.
  HeadphoneDevice copyWith({
    String? name,
    HeadphoneHardwareModel? model,
    bool? isConnected,
    bool? isMotionAvailable,
    bool? isActive,
    int? sampleRateHz,
    bool? isCalibrated,
    HeadphoneSensorLocation? sensorLocation,
    bool? isSimulated,
  }) {
    return HeadphoneDevice(
      name: name ?? this.name,
      model: model ?? this.model,
      isConnected: isConnected ?? this.isConnected,
      isMotionAvailable: isMotionAvailable ?? this.isMotionAvailable,
      isActive: isActive ?? this.isActive,
      sampleRateHz: sampleRateHz ?? this.sampleRateHz,
      isCalibrated: isCalibrated ?? this.isCalibrated,
      sensorLocation: sensorLocation ?? this.sensorLocation,
      isSimulated: isSimulated ?? this.isSimulated,
    );
  }

  /// Serializes this device snapshot to a map.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'name': name,
    'model': model.name,
    'isConnected': isConnected,
    'isMotionAvailable': isMotionAvailable,
    'isActive': isActive,
    'sampleRateHz': sampleRateHz,
    'isCalibrated': isCalibrated,
    'sensorLocation': sensorLocation.name,
    'isSimulated': isSimulated,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HeadphoneDevice &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          model == other.model &&
          isConnected == other.isConnected &&
          isMotionAvailable == other.isMotionAvailable &&
          isActive == other.isActive &&
          sampleRateHz == other.sampleRateHz &&
          isCalibrated == other.isCalibrated &&
          sensorLocation == other.sensorLocation &&
          isSimulated == other.isSimulated;

  @override
  int get hashCode => Object.hash(
    name,
    model,
    isConnected,
    isMotionAvailable,
    isActive,
    sampleRateHz,
    isCalibrated,
    sensorLocation,
    isSimulated,
  );

  @override
  String toString() =>
      'HeadphoneDevice(name: $name, model: $model, isConnected: $isConnected, '
      'isMotionAvailable: $isMotionAvailable, isActive: $isActive, '
      'sampleRateHz: $sampleRateHz, isCalibrated: $isCalibrated, '
      'sensorLocation: $sensorLocation, isSimulated: $isSimulated)';
}
