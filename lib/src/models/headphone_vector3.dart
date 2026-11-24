import 'dart:math' as math;

/// A 3D vector representing angular velocity, linear acceleration, gravity,
/// or magnetic field telemetry from headphone motion sensors.
class HeadphoneVector3 {
  /// Creates a 3D vector with [x], [y], and [z] components.
  const HeadphoneVector3({required this.x, required this.y, required this.z});

  /// A zero vector `(0, 0, 0)`.
  static const HeadphoneVector3 zero = HeadphoneVector3(x: 0, y: 0, z: 0);

  /// Deserializes a [HeadphoneVector3] from a key-value map.
  factory HeadphoneVector3.fromMap(Map<String, dynamic> map) {
    return HeadphoneVector3(
      x: (map['x'] as num?)?.toDouble() ?? 0.0,
      y: (map['y'] as num?)?.toDouble() ?? 0.0,
      z: (map['z'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// X-axis component.
  final double x;

  /// Y-axis component.
  final double y;

  /// Z-axis component.
  final double z;

  /// Euclidean norm (`sqrt(x^2 + y^2 + z^2)`).
  double get magnitude => math.sqrt(x * x + y * y + z * z);

  /// Serializes this vector to a JSON-compatible map.
  Map<String, dynamic> toJson() => <String, dynamic>{'x': x, 'y': y, 'z': z};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HeadphoneVector3 &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y &&
          z == other.z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'HeadphoneVector3(x: $x, y: $y, z: $z)';
}
