import 'package:flutter_test/flutter_test.dart';
import 'package:dart_servo_studio/models/six_face_pose.dart';

void main() {
  Map<String, String> fields(
    List<num> raw, {
    num oneG = 2048,
    int samples = 1,
  }) => {
    'live_raw_lsb': raw.join(','),
    'one_g_lsb': '$oneG',
    'live_samples': '$samples',
  };

  test('physical raw axes classify all six signed faces', () {
    final vectors = [
      [2050, 12, -8],
      [-2050, 12, -8],
      [12, 2050, -8],
      [12, -2050, -8],
      [12, -8, 2050],
      [12, -8, -2050],
    ];
    for (var i = 0; i < 6; i++) {
      final pose = SixFacePose.fromFields(fields(vectors[i]));
      expect(pose?.closestFace, i);
      expect(pose?.aligned, true);
      expect(pose!.confidence, greaterThan(.98));
    }
  });

  test('range is supplied by firmware, not hard-coded to 2048', () {
    final pose = SixFacePose.fromFields(fields([0, -8200, 30], oneG: 8192));
    expect(pose?.closestFace, 3);
    expect(pose?.aligned, true);
  });

  test('tilted pose is only a weak suggestion, never an auto sample', () {
    final pose = SixFacePose.fromFields(fields([1100, 1100, 0]));
    expect(pose?.closestFace, 0);
    expect(pose?.aligned, false);
    expect(SixFacePose.fromFields(fields([0, 0, 0])), isNull);
    expect(SixFacePose.fromFields(fields([2050, 0, 0], samples: 0)), isNull);
    expect(
      SixFacePose.fromFields({
        'live_raw_lsb': 'NaN,0,0',
        'one_g_lsb': '2048',
        'live_samples': '1',
      }),
      isNull,
    );
  });
}
