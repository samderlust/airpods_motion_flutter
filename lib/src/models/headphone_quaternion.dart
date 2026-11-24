/// A unit quaternion `(x, y, z, w)` representing 3D headphone orientation.
class HeadphoneQuaternion {
  /// Creates a quaternion with components [x], [y], [z], and [w].
  const HeadphoneQuaternion({
    required this.x,
    required this.y,
    required this.z,
    required this.w,
  });

  /// Identity quaternion `(0, 0, 0, 1)` representing zero rotation.
  static const HeadphoneQuaternion identity = HeadphoneQuaternion(
    x: 0,
    y: 0,
    z: 0,
    w: 1,
  );

  /// Deserializes a [HeadphoneQuaternion] from a key-value map.
  factory HeadphoneQuaternion.fromMap(Map<String, dynamic> map) {
    return HeadphoneQuaternion(
      x: (map['x'] as num?)?.toDouble() ?? 0.0,
      y: (map['y'] as num?)?.toDouble() ?? 0.0,
      z: (map['z'] as num?)?.toDouble() ?? 0.0,
      w: (map['w'] as num?)?.toDouble() ?? 1.0,
    );
  }

  /// X imaginary component.
  final double x;

  /// Y imaginary component.
  final double y;

  /// Z imaginary component.
  final double z;

  /// Real (scalar) component.
  final double w;

  /// Serializes this quaternion to a JSON-compatible map.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'x': x,
    'y': y,
    'z': z,
    'w': w,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HeadphoneQuaternion &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y &&
          z == other.z &&
          w == other.w;

  @override
  int get hashCode => Object.hash(x, y, z, w);

  @override
  String toString() => 'HeadphoneQuaternion(x: $x, y: $y, z: $z, w: $w)';
}
