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

/// Simulator behavior when native headphone motion hardware is unavailable.
enum SimulatorFallbackMode {
  /// Do not activate simulator mode; leave tracking inactive.
  none,

  /// Activate simulator mode without starting the procedural loop, allowing
  /// manual calls to `simulator.emitEuler` / `simulator.emitSample` / `simulator.replayTrace`.
  manual,

  /// Activate simulator mode and automatically start the procedural sinusoidal loop.
  syntheticLoop;

  /// Parses a [SimulatorFallbackMode] from its wire string name.
  static SimulatorFallbackMode fromWireValue(String? value) {
    for (final mode in values) {
      if (mode.name == value) {
        return mode;
      }
    }
    return SimulatorFallbackMode.syntheticLoop;
  }
}

/// Configuration for headphone motion sampling, filtering, and simulator fallback.
class AirPodsMotionConfig {
  /// Creates an [AirPodsMotionConfig].
  ///
  /// [sampleRateHz] is clamped to `1..100` Hz (default `15`).
  /// [smoothingAlpha] is clamped to `0.0..1.0` (default `0.25`).
  ///
  /// When [simulatorFallbackMode] is provided, it takes precedence over
  /// [autoFallbackToSimulator]. Otherwise [autoFallbackToSimulator] derives
  /// [SimulatorFallbackMode.syntheticLoop] when `true` or
  /// [SimulatorFallbackMode.none] when `false`.
  const AirPodsMotionConfig({
    int sampleRateHz = 15,
    this.filterMode = AirPodsFilterMode.ema,
    double smoothingAlpha = 0.25,
    this.oneEuroMinCutoff = 1.0,
    this.oneEuroBeta = 0.007,
    this.oneEuroDCutoff = 1.0,
    bool autoFallbackToSimulator = true,
    SimulatorFallbackMode? simulatorFallbackMode,
  }) : sampleRateHz =
           sampleRateHz < 1 ? 1 : (sampleRateHz > 100 ? 100 : sampleRateHz),
       smoothingAlpha =
           smoothingAlpha < 0.0
               ? 0.0
               : (smoothingAlpha > 1.0 ? 1.0 : smoothingAlpha),
       simulatorFallbackMode =
           simulatorFallbackMode ??
           (autoFallbackToSimulator
               ? SimulatorFallbackMode.syntheticLoop
               : SimulatorFallbackMode.none);

  /// Deserializes an [AirPodsMotionConfig] from a map.
  factory AirPodsMotionConfig.fromMap(Map<String, dynamic> map) {
    final rawMode = map['simulatorFallbackMode'] as String?;
    return AirPodsMotionConfig(
      sampleRateHz: (map['sampleRateHz'] as num?)?.toInt() ?? 15,
      filterMode: AirPodsFilterMode.fromWireValue(map['filterMode'] as String?),
      smoothingAlpha: (map['smoothingAlpha'] as num?)?.toDouble() ?? 0.25,
      oneEuroMinCutoff: (map['oneEuroMinCutoff'] as num?)?.toDouble() ?? 1.0,
      oneEuroBeta: (map['oneEuroBeta'] as num?)?.toDouble() ?? 0.007,
      oneEuroDCutoff: (map['oneEuroDCutoff'] as num?)?.toDouble() ?? 1.0,
      autoFallbackToSimulator:
          (map['autoFallbackToSimulator'] as bool?) ?? true,
      simulatorFallbackMode:
          rawMode != null
              ? SimulatorFallbackMode.fromWireValue(rawMode)
              : null,
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

  /// Behavior when native headphone motion hardware is unavailable.
  final SimulatorFallbackMode simulatorFallbackMode;

  /// Whether simulator fallback mode is enabled (`simulatorFallbackMode != SimulatorFallbackMode.none`).
  bool get autoFallbackToSimulator =>
      simulatorFallbackMode != SimulatorFallbackMode.none;

  /// Returns a copy of this configuration with the specified overrides.
  AirPodsMotionConfig copyWith({
    int? sampleRateHz,
    AirPodsFilterMode? filterMode,
    double? smoothingAlpha,
    double? oneEuroMinCutoff,
    double? oneEuroBeta,
    double? oneEuroDCutoff,
    bool? autoFallbackToSimulator,
    SimulatorFallbackMode? simulatorFallbackMode,
  }) {
    final resolvedMode =
        simulatorFallbackMode ??
        (autoFallbackToSimulator != null
            ? (autoFallbackToSimulator
                ? (this.simulatorFallbackMode == SimulatorFallbackMode.none
                    ? SimulatorFallbackMode.syntheticLoop
                    : this.simulatorFallbackMode)
                : SimulatorFallbackMode.none)
            : this.simulatorFallbackMode);

    return AirPodsMotionConfig(
      sampleRateHz: sampleRateHz ?? this.sampleRateHz,
      filterMode: filterMode ?? this.filterMode,
      smoothingAlpha: smoothingAlpha ?? this.smoothingAlpha,
      oneEuroMinCutoff: oneEuroMinCutoff ?? this.oneEuroMinCutoff,
      oneEuroBeta: oneEuroBeta ?? this.oneEuroBeta,
      oneEuroDCutoff: oneEuroDCutoff ?? this.oneEuroDCutoff,
      simulatorFallbackMode: resolvedMode,
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
    'simulatorFallbackMode': simulatorFallbackMode.name,
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
          simulatorFallbackMode == other.simulatorFallbackMode;

  @override
  int get hashCode => Object.hash(
    sampleRateHz,
    filterMode,
    smoothingAlpha,
    oneEuroMinCutoff,
    oneEuroBeta,
    oneEuroDCutoff,
    simulatorFallbackMode,
  );

  @override
  String toString() =>
      'AirPodsMotionConfig(sampleRateHz: $sampleRateHz, filterMode: $filterMode, '
      'smoothingAlpha: $smoothingAlpha, oneEuroMinCutoff: $oneEuroMinCutoff, '
      'oneEuroBeta: $oneEuroBeta, oneEuroDCutoff: $oneEuroDCutoff, '
      'autoFallbackToSimulator: $autoFallbackToSimulator, '
      'simulatorFallbackMode: $simulatorFallbackMode)';
}
