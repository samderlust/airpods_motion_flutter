/// Native signal-conditioning mode applied before emitting samples to Dart.
enum AirPodsFilterMode {
  /// Emit raw CoreMotion samples without smoothing.
  none,

  /// Exponential Moving Average (EMA) low-pass filter using `smoothingAlpha`.
  ema,

  /// Adaptive 1-Euro low-pass filter balancing jitter removal and low lag.
  oneEuro;

  /// Parses an [AirPodsFilterMode] from its wire string name.
  static AirPodsFilterMode fromWireValue(String? value) {
    for (final mode in values) {
      if (mode.name == value) {
        return mode;
      }
    }
    return AirPodsFilterMode.ema;
  }
}

/// Configuration for headphone motion sampling, filtering, and simulator fallback.
class AirPodsMotionConfig {
  /// Creates an [AirPodsMotionConfig].
  ///
  /// [sampleRateHz] is clamped to `1..100` Hz (default `15`).
  /// [smoothingAlpha] is clamped to `0.0..1.0` (default `0.25`).
  const AirPodsMotionConfig({
    int sampleRateHz = 15,
    this.filterMode = AirPodsFilterMode.ema,
    double smoothingAlpha = 0.25,
    this.oneEuroMinCutoff = 1.0,
    this.oneEuroBeta = 0.007,
    this.oneEuroDCutoff = 1.0,
    this.autoFallbackToSimulator = true,
  }) : sampleRateHz =
           sampleRateHz < 1 ? 1 : (sampleRateHz > 100 ? 100 : sampleRateHz),
       smoothingAlpha =
           smoothingAlpha < 0.0
               ? 0.0
               : (smoothingAlpha > 1.0 ? 1.0 : smoothingAlpha);

  /// Deserializes an [AirPodsMotionConfig] from a map.
  factory AirPodsMotionConfig.fromMap(Map<String, dynamic> map) {
    return AirPodsMotionConfig(
      sampleRateHz: (map['sampleRateHz'] as num?)?.toInt() ?? 15,
      filterMode: AirPodsFilterMode.fromWireValue(map['filterMode'] as String?),
      smoothingAlpha: (map['smoothingAlpha'] as num?)?.toDouble() ?? 0.25,
      oneEuroMinCutoff: (map['oneEuroMinCutoff'] as num?)?.toDouble() ?? 1.0,
      oneEuroBeta: (map['oneEuroBeta'] as num?)?.toDouble() ?? 0.007,
      oneEuroDCutoff: (map['oneEuroDCutoff'] as num?)?.toDouble() ?? 1.0,
      autoFallbackToSimulator:
          (map['autoFallbackToSimulator'] as bool?) ?? true,
    );
  }

  /// Target EventChannel emission rate in Hz (`1..100`).
  final int sampleRateHz;

  /// Native smoothing algorithm applied to attitude and acceleration magnitude.
  final AirPodsFilterMode filterMode;

  /// EMA smoothing factor in `0.0..1.0` used when [filterMode] is [AirPodsFilterMode.ema].
  final double smoothingAlpha;

  /// Minimum cutoff frequency (Hz) for [AirPodsFilterMode.oneEuro].
  final double oneEuroMinCutoff;

  /// Speed coefficient for [AirPodsFilterMode.oneEuro].
  final double oneEuroBeta;

  /// Derivative cutoff frequency (Hz) for [AirPodsFilterMode.oneEuro].
  final double oneEuroDCutoff;

  /// Automatically activates simulator mode when native motion hardware is unavailable.
  final bool autoFallbackToSimulator;

  /// Returns a copy of this configuration with the specified overrides.
  AirPodsMotionConfig copyWith({
    int? sampleRateHz,
    AirPodsFilterMode? filterMode,
    double? smoothingAlpha,
    double? oneEuroMinCutoff,
    double? oneEuroBeta,
    double? oneEuroDCutoff,
    bool? autoFallbackToSimulator,
  }) {
    return AirPodsMotionConfig(
      sampleRateHz: sampleRateHz ?? this.sampleRateHz,
      filterMode: filterMode ?? this.filterMode,
      smoothingAlpha: smoothingAlpha ?? this.smoothingAlpha,
      oneEuroMinCutoff: oneEuroMinCutoff ?? this.oneEuroMinCutoff,
      oneEuroBeta: oneEuroBeta ?? this.oneEuroBeta,
      oneEuroDCutoff: oneEuroDCutoff ?? this.oneEuroDCutoff,
      autoFallbackToSimulator:
          autoFallbackToSimulator ?? this.autoFallbackToSimulator,
    );
  }

  /// Serializes this configuration into a MethodChannel-ready map.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'sampleRateHz': sampleRateHz,
    'filterMode': filterMode.name,
    'smoothingAlpha': smoothingAlpha,
    'oneEuroMinCutoff': oneEuroMinCutoff,
    'oneEuroBeta': oneEuroBeta,
    'oneEuroDCutoff': oneEuroDCutoff,
    'autoFallbackToSimulator': autoFallbackToSimulator,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AirPodsMotionConfig &&
          runtimeType == other.runtimeType &&
          sampleRateHz == other.sampleRateHz &&
          filterMode == other.filterMode &&
          smoothingAlpha == other.smoothingAlpha &&
          oneEuroMinCutoff == other.oneEuroMinCutoff &&
          oneEuroBeta == other.oneEuroBeta &&
          oneEuroDCutoff == other.oneEuroDCutoff &&
          autoFallbackToSimulator == other.autoFallbackToSimulator;

  @override
  int get hashCode => Object.hash(
    sampleRateHz,
    filterMode,
    smoothingAlpha,
    oneEuroMinCutoff,
    oneEuroBeta,
    oneEuroDCutoff,
    autoFallbackToSimulator,
  );

  @override
  String toString() =>
      'AirPodsMotionConfig(sampleRateHz: $sampleRateHz, filterMode: $filterMode, '
      'smoothingAlpha: $smoothingAlpha, oneEuroMinCutoff: $oneEuroMinCutoff, '
      'oneEuroBeta: $oneEuroBeta, oneEuroDCutoff: $oneEuroDCutoff, '
      'autoFallbackToSimulator: $autoFallbackToSimulator)';
}
