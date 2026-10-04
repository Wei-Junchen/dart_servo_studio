import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:dart_servo_studio/models.dart';
import 'package:dart_servo_studio/controller.dart';

void main() {
  test('rear-view quadrants: upper-left 1, clockwise 2 3 4', () {
    final coordinates = List.generate(
      4,
      (i) => (math.cos(canardAzimuth(i)), math.sin(canardAzimuth(i))),
    );
    expect(coordinates.map((p) => p.$1.sign).toList(), [-1.0, 1.0, 1.0, -1.0]);
    expect(coordinates.map((p) => p.$2.sign).toList(), [1.0, 1.0, -1.0, -1.0]);
    expect(canardPositionNames, ['左上', '右上', '右下', '左下']);
  });
  test(
    'all selections exchange the old owner and preserve physical positions',
    () {
      for (int position = 0; position < 4; position++) {
        for (int pwm = 1; pwm <= 4; pwm++) {
          final c = StudioController();
          final before = c.servos.map((s) => s.pwmIndex).toList();
          final other = before.indexOf(pwm);
          c.setMapping(position, pwm);
          expect(c.servos[position].pwmIndex, pwm);
          expect(c.servos[other].pwmIndex, before[position]);
          expect(c.servos.map((s) => s.pwmIndex).toSet(), {1, 2, 3, 4});
          expect(c.servos.map((s) => s.position).toList(), [1, 2, 3, 4]);
          c.dispose();
        }
      }
    },
  );
  test('example position 1: PWM 1 -> 2 exchanges the existing PWM 2 owner', () {
    final c = StudioController();
    c.setMapping(0, 1); // Start with position 1 on output 1.
    final owner = c.servos.indexWhere((s) => s.pwmIndex == 2);
    c.setMapping(0, 2);
    expect(c.servos[0].pwmIndex, 2);
    expect(c.servos[owner].pwmIndex, 1);
    c.dispose();
  });
  test('invalid offset drafts cannot become silent valid writes', () {
    final c = StudioController();
    for (final invalid in ['', 'NaN', 'Infinity', '90.001', '-91', 'abc']) {
      c.setOffsetInput(0, invalid);
      expect(c.draftValid, false);
      expect(c.servos[0].offset, 0);
    }
    c.setOffsetInput(0, '-27.125');
    expect(c.draftValid, true);
    expect(c.servos[0].offset, -27.125);
    c.dispose();
  });
}
