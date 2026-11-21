import 'dart:math' as math;

import 'models.dart';

/// Photo-based proportions, not measured CAD dimensions. +X points nose -> tail.
class ModelPoint {
  const ModelPoint(this.x, this.y, this.z);
  final double x, y, z;
  ModelPoint operator +(ModelPoint b) => ModelPoint(x + b.x, y + b.y, z + b.z);
  ModelPoint operator -(ModelPoint b) => ModelPoint(x - b.x, y - b.y, z - b.z);
  ModelPoint operator *(double s) => ModelPoint(x * s, y * s, z * s);
  ModelPoint cross(ModelPoint b) =>
      ModelPoint(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x);
  double dot(ModelPoint b) => x * b.x + y * b.y + z * b.z;
  ModelPoint get normalized {
    final n = math.sqrt(dot(this));
    return n == 0 ? this : this * (1 / n);
  }
}

abstract final class DartGeometry {
  // One shared axis for the panel, horn, shaft and rotation indicator.
  // Every chord vertex is aft of this noseward leading-edge shaft.
  static const hingeX = -1.64;
  static const canardOutline = [
    (hingeX, .40),
    (hingeX, 1.28),
    (hingeX + .04, 1.32),
    (-.56, 1.32),
    (-.52, 1.28),
    (-.45, .40),
    (-.48, .37),
    (hingeX + .04, .37),
  ];
  static const tailOutline = [
    (1.19, .33),
    (1.29, 1.43),
    (1.93, 1.43),
    (2.10, .29),
  ];

  static ModelPoint radial(int id, double x, double radius, double tangent) {
    final phi = canardAzimuth(id);
    return ModelPoint(
      x,
      radius * math.cos(phi) - tangent * math.sin(phi),
      radius * math.sin(phi) + tangent * math.cos(phi),
    );
  }

  /// Rigid rotation around the leading-edge radial axis, including thickness.
  /// Points on the shaft (x=hingeX, thickness=0) never move with angle.
  static ModelPoint canard(
    int id,
    double x,
    double radius,
    double angleDeg, [
    double thickness = 0,
  ]) {
    final a = angleDeg * math.pi / 180, chord = x - hingeX;
    return radial(
      id,
      hingeX + chord * math.cos(a) - thickness * math.sin(a),
      radius,
      chord * math.sin(a) + thickness * math.cos(a),
    );
  }

  /// Flat panels and chamfered corners, not nested circular tubes.
  /// Section order is consistent, allowing an uninterrupted lofted shell.
  static List<ModelPoint> section(
    double x,
    double halfWidth,
    double halfHeight,
    double chamfer,
  ) => [
    ModelPoint(x, -halfWidth + chamfer, halfHeight),
    ModelPoint(x, halfWidth - chamfer, halfHeight),
    ModelPoint(x, halfWidth, halfHeight - chamfer),
    ModelPoint(x, halfWidth, -halfHeight + chamfer),
    ModelPoint(x, halfWidth - chamfer, -halfHeight),
    ModelPoint(x, -halfWidth + chamfer, -halfHeight),
    ModelPoint(x, -halfWidth, -halfHeight + chamfer),
    ModelPoint(x, -halfWidth, halfHeight - chamfer),
  ];

  static List<List<ModelPoint>> get shellSections => [
    section(-.47, .36, .33, .10),
    section(1.85, .36, .33, .10),
    section(2.06, .285, .265, .08),
  ];
}
