import 'dart:math' as math;

/// An advisory pose derived from the ICM's *physical*, uncalibrated XYZ axes.
/// It never triggers a calibration request on its own.
class SixFacePose {
  const SixFacePose({
    required this.rawLsb,
    required this.oneGLsb,
    required this.closestFace,
    required this.confidence,
    required this.aligned,
  });

  /// Face order: X+, X-, Y+, Y-, Z+, Z-.
  final List<double> rawLsb;
  final double oneGLsb;
  final int closestFace;
  final double confidence;
  final bool aligned;

  static SixFacePose? fromFields(Map<String, String> fields) {
    final samples = int.tryParse(fields['live_samples'] ?? '');
    final oneG = double.tryParse(fields['one_g_lsb'] ?? '');
    final raw = (fields['live_raw_lsb'] ?? '')
        .split(',')
        .map(double.tryParse)
        .toList();
    if (samples == null ||
        samples <= 0 ||
        oneG == null ||
        !oneG.isFinite ||
        oneG <= 0 ||
        raw.length != 3 ||
        raw.any((value) => value == null || !value.isFinite)) {
      return null;
    }
    final vector = raw.cast<double>();
    final magnitude = math.sqrt(
      vector.fold<double>(0, (sum, v) => sum + v * v),
    );
    if (magnitude < 0.3 * oneG) return null;

    // The closest of the six ideal gravity vectors is the signed axis with
    // greatest absolute raw magnitude. Compute geometric error for the UI.
    var axis = 0;
    for (var i = 1; i < 3; i++) {
      if (vector[i].abs() > vector[axis].abs()) axis = i;
    }
    final positive = vector[axis] >= 0;
    final target = positive ? oneG : -oneG;
    var squaredError = 0.0;
    var crossSquared = 0.0;
    for (var i = 0; i < 3; i++) {
      final delta = vector[i] - (i == axis ? target : 0.0);
      squaredError += delta * delta;
      if (i != axis) crossSquared += vector[i] * vector[i];
    }
    final confidence = (1 - math.sqrt(squaredError) / oneG).clamp(0.0, 1.0);
    final crossRatio = math.sqrt(crossSquared) / oneG;
    return SixFacePose(
      rawLsb: vector,
      oneGLsb: oneG,
      closestFace: axis * 2 + (positive ? 0 : 1),
      confidence: confidence,
      aligned:
          confidence >= 0.75 &&
          crossRatio <= 0.35 &&
          magnitude >= oneG * 0.8 &&
          magnitude <= oneG * 1.2,
    );
  }
}
