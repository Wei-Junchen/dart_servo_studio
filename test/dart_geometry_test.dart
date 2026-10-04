import 'dart:math' as math;

import 'package:dart_servo_studio/dart_geometry.dart';
import 'package:dart_servo_studio/models.dart';
import 'package:flutter_test/flutter_test.dart';

double distance(ModelPoint a, ModelPoint b) => math.sqrt((a - b).dot(a - b));

void main() {
  test('shaft is at the foremost panel edge, never at mid-chord', () {
    final xs = DartGeometry.canardOutline.map((p) => p.$1).toList();
    expect(xs.reduce(math.min), DartGeometry.hingeX);
    expect(xs.every((x) => x >= DartGeometry.hingeX), true);
    expect(xs.reduce(math.max) - DartGeometry.hingeX, greaterThan(1));
  });

  test('every leading-edge shaft point stays fixed at all servo angles', () {
    for (int id = 0; id < 4; id++) {
      for (final radius in [.32, .4, .9, 1.28, 1.35]) {
        final axis = DartGeometry.radial(id, DartGeometry.hingeX, radius, 0);
        for (final angle in [-30.0, -15.0, 0.0, 15.0, 30.0]) {
          final p = DartGeometry.canard(id, DartGeometry.hingeX, radius, angle);
          expect(distance(p, axis), closeTo(0, 1e-12));
        }
      }
    }
  });

  test(
    'trailing edge moves around leading edge, with correct signed direction',
    () {
      for (int id = 0; id < 4; id++) {
        final phi = canardAzimuth(id);
        final tangent = ModelPoint(0, -math.sin(phi), math.cos(phi));
        final root = DartGeometry.radial(id, DartGeometry.hingeX, 1.28, 0);
        const chord = -.52 - DartGeometry.hingeX;
        for (final angle in [-30.0, 30.0]) {
          final p = DartGeometry.canard(id, -.52, 1.28, angle);
          expect(distance(p, root), closeTo(chord, 1e-12));
          expect(
            p.x,
            closeTo(
              DartGeometry.hingeX + chord * math.cos(angle * math.pi / 180),
              1e-12,
            ),
          );
          expect(
            (p - root).dot(tangent),
            closeTo(chord * math.sin(angle * math.pi / 180), 1e-12),
          );
        }
      }
    },
  );

  test('panel thickness and horn geometry rotate rigidly with the surface', () {
    for (int id = 0; id < 4; id++) {
      final a0 = DartGeometry.canard(id, -1.6, .4, 0, -.013);
      final b0 = DartGeometry.canard(id, -.52, 1.28, 0, .013);
      for (final angle in [-30.0, 20.0, 30.0]) {
        final a = DartGeometry.canard(id, -1.6, .4, angle, -.013);
        final b = DartGeometry.canard(id, -.52, 1.28, angle, .013);
        expect(distance(a, b), closeTo(distance(a0, b0), 1e-12));
        expect(
          distance(a, DartGeometry.canard(id, -1.6, .4, angle, .013)),
          closeTo(.026, 1e-12),
        );
      }
    }
  });

  test('main shell is a continuous flat-sided profile, not stepped tubes', () {
    final sections = DartGeometry.shellSections;
    expect(sections.length, 3); // straight main body + short tail bevel
    for (int i = 0; i < 8; i++) {
      expect(sections[0][i].y, sections[1][i].y);
      expect(sections[0][i].z, sections[1][i].z);
      expect(sections[2][i].x, greaterThan(sections[1][i].x));
    }
    expect(sections[0][0].z, sections[0][1].z); // flat top
    expect(sections[0][2].y, sections[0][3].y); // flat side
  });
}
