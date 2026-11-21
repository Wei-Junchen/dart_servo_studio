import 'package:flutter_test/flutter_test.dart';
import 'package:dart_servo_studio/controller.dart';
import 'package:dart_servo_studio/models.dart';

import 'fake_target.dart';

class TestController extends StudioController {
  @override
  Future<void> savePreferences() async {}
}

TestController configure(FakeTarget target) => TestController()
  ..settings.host = '127.0.0.1'
  ..settings.port = target.port
  ..settings.launchCommander = false
  ..settings.elf = '';

Future<void> until(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!predicate() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(predicate(), true, reason: 'RTT condition did not converge');
}

void main() {
  test(
    'v8 calibrates 0° in integer microseconds without legacy offset RPC',
    () async {
      final peer = FakeTarget(protocol: 8);
      await peer.start();
      final c = configure(peer);
      try {
        await c.connect();
        expect(c.connected, true);
        expect(c.protocol, 8);
        expect(
          peer.commands.where(
            (v) =>
                v == 'servo get' ||
                v == 'servo saved' ||
                v.startsWith('servo setall '),
          ),
          isEmpty,
        );
        await c.setServoCalibrationMode(0);
        expect(peer.angles, [0, 0, 0, 0]);
        c.nudgeActiveValue(0, 1);
        await until(() => peer.zeroUs[0] == 1812 && !c.operation);
        c.nudgeActiveValue(0, -1);
        await until(() => peer.zeroUs[0] == 1811 && !c.operation);
        await c.tuneCalibrationPoint(0, 0, 1600);
        expect(c.servos[0].previewPulse, 1600);
        await c.setServoCalibrationMode(-30);
        await c.tuneCalibrationPoint(0, -30, 1450);
        await c.setServoCalibrationMode(30);
        await c.tuneCalibrationPoint(0, 30, 2150);
        expect(c.servos[0].pulseAt(15, 0), 1875);
        expect(peer.commands.contains('servo save'), false);
        await c.saveFlash();
        expect(peer.savedZeroUs![0], 1600);
        expect(c.flashMatches, true);
        await c.setServoCalibrationMode(0);
        await c.tuneCalibrationPoint(0, 0, 1610);
        expect(c.flashMatches, false);
        await c.loadFlashToRam();
        expect(c.servos[0].zeroUs, 1600);
        expect(c.flashMatches, true);
        await c.tuneCalibrationPoint(0, 0, 2200);
        expect(c.servos[0].pos30Valid, false);
        expect(c.servos[0].pos30Us, 0);
        await c.saveFlash();
        expect(c.flashMatches, true);
        expect(
          peer.commands.where(
            (v) =>
                v == 'servo get' ||
                v == 'servo saved' ||
                v.startsWith('servo setall '),
          ),
          isEmpty,
        );
      } finally {
        await c.disconnect();
        c.dispose();
        await peer.close();
      }
    },
  );

  test('v8 held-key nudges queue while an RTT write awaits ACK', () async {
    final peer = FakeTarget(protocol: 8)
      ..curveAckDelay = const Duration(milliseconds: 70);
    await peer.start();
    final c = configure(peer);
    try {
      await c.connect();
      await c.setServoCalibrationMode(0);
      final start = peer.zeroUs[0];
      c.nudgeActiveValue(0, 1);
      c.nudgeActiveValue(0, 1, steps: 2);
      c.nudgeActiveValue(0, 1, steps: 3);
      await until(() => peer.zeroUs[0] == start + 6 && !c.operation);
      expect(c.servos[0].zeroUs, start + 6);
      expect(
        peer.commands
            .where((v) => v.startsWith('servo curve set 0 zero '))
            .length,
        2,
      );
    } finally {
      await c.disconnect();
      c.dispose();
      await peer.close();
    }
  });

  test('releasing a v8 adjustment key drops unsent queued PWM steps', () async {
    final peer = FakeTarget(protocol: 8)
      ..curveAckDelay = const Duration(milliseconds: 100);
    await peer.start();
    final c = configure(peer);
    try {
      await c.connect();
      await c.setServoCalibrationMode(0);
      final start = peer.zeroUs[0];
      c.nudgeActiveValue(0, 1);
      c.nudgeActiveValue(0, 1, steps: 5);
      c.cancelQueuedNudges();
      await until(() => c.servos[0].zeroUs == start + 1 && !c.operation);
      expect(peer.zeroUs[0], start + 1);
    } finally {
      await c.disconnect();
      c.dispose();
      await peer.close();
    }
  });

  test('servo three-point points affect both slopes and only explicit save writes Flash', () async {
    final peer = FakeTarget(protocol: 7);
    await peer.start();
    final c = configure(peer);
    try {
      await c.connect();
      expect(c.servos[0].neg30Valid, false);
      await c.setServoCalibrationMode(-30);
      expect(c.servoCalibrationMode, -30);
      expect(peer.angles, [-30, 0, 0, 0]);
      c.selectServo(1);
      await until(() => peer.angles[1] == -30 && !c.operation);
      expect(peer.angles, [0, -30, 0, 0]);
      c.selectServo(0);
      await until(() => peer.angles[0] == -30 && !c.operation);
      await c.tuneCalibrationPoint(0, -30, 1450);
      await c.setServoCalibrationMode(30);
      await c.tuneCalibrationPoint(0, 30, 2150);
      expect(peer.angles, [30, 0, 0, 0]);
      c.nudgeActiveValue(0, 1);
      await until(() => peer.pos30Us[0] == 2151 && !c.operation);
      c.nudgeActiveValue(0, -1);
      await until(() => peer.pos30Us[0] == 2150 && !c.operation);
      expect(c.servos[0].pulseAt(-30, c.servos[0].offset), 1450);
      expect(c.servos[0].pulseAt(30, c.servos[0].offset), 2150);
      expect(c.servos[0].pulseAt(15, c.servos[0].offset), 1980);
      expect(peer.commands.contains('servo save'), false);
      await c.setServoCalibrationMode(0);
      expect(c.servoCalibrationMode, 0);
      expect(peer.angles, [0, 0, 0, 0]);
      await c.saveFlash();
      expect(c.servoCalibrationMode, 0);
      expect(c.flashMatches, true);
      expect(peer.savedCurveMask, 0x11);
      await c.setServoCalibrationMode(30);
      await c.tuneCalibrationPoint(0, 30, 2200);
      expect(c.flashMatches, false);
      await c.loadFlashToRam();
      expect(c.servos[0].pos30Us, 2150);
      expect(c.flashMatches, true);
      await c.disarm();
      expect(peer.manual, false);
      expect(peer.angles, [0, 0, 0, 0]);
    } finally {
      await c.disconnect();
      c.dispose();
      await peer.close();
    }
  });

  test(
    'older RTT firmware without cal saved keeps calibration window usable',
    () async {
      final peer = FakeTarget(protocol: 5)..supportsCalSaved = false;
      await peer.start();
      final c = configure(peer);
      try {
        await c.connect();
        c.openCalibration();
        await until(() => c.savedCalibration['unsupported'] == '1');
        expect(c.connected, true);
        expect(c.icmCalibration.containsKey('raw_lsb'), true);
      } finally {
        await c.disconnect();
        c.dispose();
        await peer.close();
      }
    },
  );

  test('calibration is polled only while connected dialog is open and Flash save is explicit', () async {
    final peer = FakeTarget(protocol: 5);
    await peer.start();
    final c = configure(peer);
    try {
      await c.connect();
      expect(peer.commands.where((v) => v.endsWith(' info')), isEmpty);
      c.openCalibration();
      await until(() => peer.commands.contains('cal icm info'));
      await until(() => c.icmCalibration.containsKey('live_raw_lsb'));
      await until(() => c.savedCalibration.containsKey('valid'));
      expect(c.icmCalibration['live_raw_lsb'], '0,2048,0');
      expect(c.savedCalibration['valid'], '0');
      expect(peer.commands.where((v) => v == 'cal saved').length, 1);
      expect(
        peer.commands.where(
          (v) => v.startsWith('cal icm ') && v != 'cal icm info',
        ),
        isEmpty,
      ); // Advisory pose never starts sampling.
      for (final face in ['x+', 'x-', 'y+', 'y-', 'z+', 'z-']) {
        await c.calibrationCommand('cal icm $face');
      }
      expect(c.icmCalibration['status'], '11');
      expect(peer.calibrationFlashSaves, 0);
      expect(c.savedCalibration['valid'], '0'); // RAM candidate is not Flash.
      await c.calibrationCommand('cal icm save', flash: true);
      expect(peer.calibrationFlashSaves, 1);
      expect(c.savedCalibration['valid'], '1');
      expect(c.savedCalibration['icm_lsb'], peer.savedIcmFaces.join(','));
      await c.calibrationCommand('cal adxl start');
      expect(c.adxlCalibration['status'], '9');
      expect(peer.calibrationFlashSaves, 1);
      await c.calibrationCommand('cal adxl save', flash: true);
      expect(peer.calibrationFlashSaves, 2);
      expect(c.savedCalibration['valid'], '5');
      expect(c.savedCalibration['adxl_offset'], '1.0,2.0,3.0');
      peer.savedAdxlOffset = [4, 5, 6];
      await c.refreshSavedCalibration();
      expect(c.savedCalibration['adxl_offset'], '4.0,5.0,6.0');
      c.closeCalibration();
      final count = peer.commands.where((v) => v.endsWith(' info')).length;
      final savedReads = peer.commands.where((v) => v == 'cal saved').length;
      await Future<void>.delayed(const Duration(milliseconds: 550));
      expect(peer.commands.where((v) => v.endsWith(' info')).length, count);
      expect(peer.commands.where((v) => v == 'cal saved').length, savedReads);
      await c.disconnect();
      expect(c.calibrationOpen, false);
    } finally {
      await c.disconnect();
      c.dispose();
      await peer.close();
    }
  });

  test('connection claims control without moving PWM; first offset edit writes RAM', () async {
    final peer = FakeTarget();
    await peer.start();
    final c = configure(peer);
    try {
      await c.connect();
      expect(c.connected, true);
      expect(c.clientControl && peer.control, true);
      expect(c.manual, false);
      expect(c.canWrite, true);
      expect(
        peer.commands.every(
          (v) => [
            'ping',
            'status',
            'servo get',
            'servo saved',
            'servo angles get',
            'servo map saved',
            'servo control acquire',
          ].contains(v),
        ),
        true,
      );
      expect(peer.angles, [0, 0, 0, 0]);
      await until(() => peer.commands.contains('servo control keepalive'));
      for (int i = 0; i < 50; i++) {
        c.setOffset(0, -28 + i / 10);
      }
      await until(() => !c.pending && peer.offsets[0] == -23.1);
      expect(c.manual, true);
      expect(
        peer.commands.where((v) => v.startsWith('servo setall ')).length,
        1,
      );
      expect(
        peer.commands.where((v) => v.startsWith('servo angles set ')),
        isEmpty,
      );
      expect(peer.offsets.skip(1), [-5, -18, -28]);
      expect(peer.savedOffsets, isNull); // RAM edits never burn Flash.
      expect(peer.commands.contains('servo save'), false);
      expect(peer.angles, [0, 0, 0, 0]);
    } finally {
      await c.disconnect();
      c.dispose();
      await peer.close();
    }
  });

  test('one common angle writes four identical values; offsets and mapping auto-sync', () async {
    final peer = FakeTarget();
    await peer.start();
    final c = configure(peer);
    try {
      await c.connect();
      for (int i = 0; i < 50; i++) {
        c.setCommonAngle(i / 2);
      }
      await until(() => !c.pending && peer.angles[0] == 24.5);
      expect(peer.angles, List.filled(4, 24.5));
      expect(
        peer.commands.where((v) => v.startsWith('servo angles set ')).length,
        1,
      );
      expect(peer.offsets, [-28, -5, -18, -28]);
      c.setMapping(0, 1);
      c.setOffsetInput(0, '-27.125');
      await until(() => !c.pending && peer.offsets[0] == -27.125);
      expect(peer.mapping, [1, 3, 2, 4]);
      expect(
        peer.angles,
        List.filled(4, 24.5),
      ); // Offset edit preserves commanded angle.
      c.setCommonAngle(-17.5);
      await until(() => !c.pending && peer.angles[0] == -17.5);
      for (final cmd in peer.commands.where(
        (v) => v.startsWith('servo angles set '),
      )) {
        final values = cmd.split(' ').skip(3).map(double.parse).toList();
        expect(values.length, 4);
        expect(values.toSet().length, 1);
      }
      expect(peer.savedMapping, isNull);
    } finally {
      await c.disconnect();
      c.dispose();
      await peer.close();
    }
  });

  test('save includes the latest queued RAM edits, excludes test angle, and does not lock next edit', () async {
    final peer = FakeTarget();
    await peer.start();
    final c = configure(peer);
    try {
      await c.connect();
      c.setCommonAngle(15);
      await until(() => !c.pending && peer.angles[0] == 15);
      c.setOffset(0, -26.125);
      c.setMapping(0, 1);
      await c.saveFlash(); // No apply button and no timer wait before saving.
      expect(c.flashMatches, true);
      expect(peer.savedOffsets![0], -26.125);
      expect(peer.savedMapping, [1, 3, 2, 4]);
      expect(peer.angles, [0, 0, 0, 0]);
      expect(c.manual, false);
      expect(c.canWrite, true);
      expect(c.editable, true);
      final save = peer.commands.indexOf('servo save');
      expect(peer.commands.take(save).contains('servo manual stop'), true);
      expect(peer.commands.where((v) => v == 'servo save').length, 1);
      c.setOffset(1, -4.5);
      await until(() => !c.pending && peer.offsets[1] == -4.5);
      expect(c.manual, true);
      expect(peer.savedOffsets![1], -5); // No automatic Flash write after save.
    } finally {
      await c.disconnect();
      c.dispose();
      await peer.close();
    }
  });

  test('newer slider edits survive delayed ACKs and concurrent save', () async {
    final peer = FakeTarget()
      ..offsetAckDelay = const Duration(milliseconds: 180);
    await peer.start();
    final c = configure(peer);
    try {
      await c.connect();
      c.setOffset(0, -27);
      await until(() => peer.offsets[0] == -27); // ACK still in flight.
      c.setOffset(0, -25);
      c.setCommonAngle(12);
      await until(
        () => !c.pending && peer.offsets[0] == -25 && peer.angles[0] == 12,
      );
      expect(c.servos[0].offset, -25);
      expect(c.servos[0].appliedOffset, -25);
      c.setOffset(0, -23);
      await until(() => peer.offsets[0] == -23);
      c.setOffset(0, -22);
      await c.saveFlash(); // Serialize after in-flight tick, flush newer desired value.
      expect(peer.savedOffsets![0], -22);
      expect(c.flashMatches, true);
      expect(c.connected, true);
    } finally {
      await c.disconnect();
      c.dispose();
      await peer.close();
    }
  });

  test(
    'invalid text is never written, and offset slider repairs the field',
    () async {
      final peer = FakeTarget();
      await peer.start();
      final c = configure(peer);
      try {
        await c.connect();
        for (final text in ['-', 'NaN', 'Infinity', '90.001', '-91', 'abc']) {
          c.setOffsetInput(0, text);
          expect(c.draftValid, false);
          expect(c.canSaveFlash, false);
        }
        c.setCommonAngle(25);
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(
          peer.commands.where(
            (v) =>
                v.startsWith('servo setall ') ||
                v.startsWith('servo angles set '),
          ),
          isEmpty,
        );
        c.setOffset(0, -26.5);
        await until(() => !c.pending && peer.offsets[0] == -26.5);
        expect(c.draftValid, true);
      } finally {
        await c.disconnect();
        c.dispose();
        await peer.close();
      }
    },
  );

  test(
    'rejected RAM write disconnects without retry or saving Flash',
    () async {
      final peer = FakeTarget()..rejectOffsets = true;
      await peer.start();
      final c = configure(peer);
      try {
        await c.connect();
        c.setOffset(0, -27);
        await until(() => !c.connected);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(
          peer.commands.where((v) => v.startsWith('servo setall ')).length,
          1,
        );
        expect(peer.commands.contains('servo save'), false);
        expect(peer.manual, false);
      } finally {
        await c.disconnect();
        c.dispose();
        await peer.close();
      }
    },
  );

  test(
    'protocol 1 and non-idle device remain read-only without auto-start',
    () async {
      for (final peer in [FakeTarget(protocol: 1)]) {
        await peer.start();
        final c = configure(peer);
        try {
          await c.connect();
          expect(c.connected, true);
          expect(c.canWrite, false);
          final offsets = c.servos.map((s) => s.offset).toList();
          c.setOffset(0, 20);
          c.setCommonAngle(20);
          c.setMapping(0, 1);
          await c.saveFlash();
          await Future<void>.delayed(const Duration(milliseconds: 120));
          expect(c.servos.map((s) => s.offset), offsets);
          expect(
            peer.commands.any(
              (s) =>
                  s.contains(' start') ||
                  s.contains(' set') ||
                  s == 'servo save',
            ),
            false,
          );
        } finally {
          await c.disconnect();
          c.dispose();
          await peer.close();
        }
      }
      final nonIdle = FakeTarget()..idle = false;
      await nonIdle.start();
      final c = configure(nonIdle);
      try {
        await c.connect();
        expect(c.connected, false);
        expect(nonIdle.control, false);
      } finally {
        c.dispose();
        await nonIdle.close();
      }
    },
  );

  test(
    'stopping flushes RAM and releases lease, without re-arming itself',
    () async {
      final peer = FakeTarget();
      await peer.start();
      final c = configure(peer);
      try {
        await c.connect();
        c.setCommonAngle(15);
        await until(() => !c.pending && peer.angles[0] == 15);
        c.setOffset(0, -25.5);
        await c.disarm();
        final starts = peer.commands
            .where((s) => s == 'servo manual start')
            .length;
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(peer.offsets[0], -25.5);
        expect(c.manual, false);
        expect(peer.angles, [0, 0, 0, 0]);
        expect(
          peer.commands.where((s) => s == 'servo manual start').length,
          starts,
        );
        expect(c.editable, true);
      } finally {
        await c.disconnect();
        c.dispose();
        await peer.close();
      }
    },
  );

  test(
    'close waits for in-flight RAM write, then neutralizes and releases lease',
    () async {
      final peer = FakeTarget()
        ..offsetAckDelay = const Duration(milliseconds: 150);
      await peer.start();
      final c = configure(peer);
      try {
        await c.connect();
        c.setOffset(0, -27);
        await until(() => peer.offsets[0] == -27);
        await c.disconnect();
        expect(peer.commands.last, 'servo control release');
        expect(peer.commands.contains('servo manual stop'), true);
        expect(peer.control, false);
        expect(peer.manual, false);
        expect(c.servos.every((s) => s.angle == 0), true);
      } finally {
        c.dispose();
        await peer.close();
      }
    },
  );

  test('positive angle raises PWM position and positive offset lowers it', () {
    final c = StudioController();
    c.setOffset(0, -20);
    c.setOffset(1, 10);
    c.setCommonAngle(15);
    expect(c.servos.map((s) => s.commandAngle), [15, 15, 15, 15]);
    expect(c.servos[0].directionAngle, 35);
    expect(c.servos[1].directionAngle, 5);
    expect(c.servos[0].pwmPositionDelta, 35);
    expect(c.servos[1].pwmPositionDelta, 5);
    expect(c.servos[0].previewPulse, greaterThan(c.servos[1].previewPulse));
    final s = ServoModel(0)
      ..offset = 90
      ..angle = -30;
    expect(s.directionAngle, -90);
    expect(s.pwmPositionDelta, -90);
    expect(s.directionClamped, true);
    expect(s.previewPulse, 500);
    c.dispose();
  });
  test(
    'protocol 4 GUI +10 sends positive RTT angle and opposes +10 offset',
    () async {
      final peer = FakeTarget()..offsets = [0, 0, 0, 0];
      await peer.start();
      final c = configure(peer);
      try {
        await c.connect();
        c.setOffset(0, 10);
        await until(() => !c.pending && peer.offsets[0] == 10);
        expect(c.servos[0].directionAngle, -10);
        c.setCommonAngle(10);
        await until(() => !c.pending && peer.angles[0] == 10);
        expect(peer.angles, List.filled(4, 10));
        expect(c.servos[0].directionAngle, 0);
        expect(c.servos[0].pwmPositionDelta, 0);
        expect(c.servos[0].previewPulse, 1500);
        expect(c.servos[0].pulse, 1500);
        expect(peer.commands.contains('servo save'), false);
        await c.refresh();
        expect(c.commonAngle, 10);
        expect(c.servos[0].angle, 10);
      } finally {
        await c.disconnect();
        c.dispose();
        await peer.close();
      }
    },
  );

  test('clear all offsets only updates RAM; fresh Flash load restores offsets and mapping', () async {
    final peer = FakeTarget()
      ..savedOffsets = [-22.5, -4.1, 0.25, 1]
      ..savedMapping = [2, 1, 4, 3];
    await peer.start();
    final c = configure(peer);
    try {
      await c.connect();
      c.clearAllOffsets();
      await until(() => !c.pending && peer.offsets.every((v) => v == 0));
      expect(peer.mapping, [3, 1, 2, 4]);
      expect(peer.savedOffsets, [-22.5, -4.1, 0.25, 1]);
      final savedReads = peer.commands.where((v) => v == 'servo saved').length;
      await c.loadFlashToRam();
      expect(
        peer.commands.where((v) => v == 'servo saved').length,
        savedReads + 1,
      );
      expect(peer.offsets, [-22.5, -4.1, 0.25, 1]);
      expect(peer.mapping, [2, 1, 4, 3]);
      expect(c.flashMatches, true);
      expect(peer.commands.contains('servo save'), false);
    } finally {
      await c.disconnect();
      c.dispose();
      await peer.close();
    }
  });

  test(
    'missing Flash record leaves RAM unchanged and connection usable',
    () async {
      final peer = FakeTarget();
      await peer.start();
      final c = configure(peer);
      try {
        await c.connect();
        await c.loadFlashToRam();
        expect(c.connected, true);
        expect(peer.offsets, [-28, -5, -18, -28]);
        expect(peer.commands.contains('servo manual start'), false);
        expect(c.message, contains('没有已保存'));
      } finally {
        await c.disconnect();
        c.dispose();
        await peer.close();
      }
    },
  );

  test('legacy Flash offsets restore without changing live PWM map', () async {
    final peer = FakeTarget()..savedOffsets = [-2, -3, -4, -5];
    await peer.start();
    final c = configure(peer);
    try {
      await c.connect();
      await c.loadFlashToRam();
      expect(peer.offsets, [-2, -3, -4, -5]);
      expect(peer.mapping, [3, 1, 2, 4]);
      expect(c.connected, true);
      expect(c.message, contains('保留当前通道'));
    } finally {
      await c.disconnect();
      c.dispose();
      await peer.close();
    }
  });
  test(
    'protocol 2 keeps offset editing but disables inconsistent test angles',
    () async {
      final peer = FakeTarget(protocol: 2);
      await peer.start();
      final c = configure(peer);
      try {
        await c.connect();
        expect(c.canWrite, true);
        expect(c.canMove, false);
        c.setCommonAngle(10);
        expect(c.commonAngle, 0);
        c.setOffset(0, -27.5);
        await until(() => !c.pending && peer.offsets[0] == -27.5);
        expect(
          peer.commands.where((v) => v.startsWith('servo angles set ')),
          isEmpty,
        );
      } finally {
        await c.disconnect();
        c.dispose();
        await peer.close();
      }
    },
  );
  test(
    'protocol 3 angle is displayed in protocol 4 direction but cannot move',
    () async {
      final peer = FakeTarget(protocol: 3)..angles = [10, 10, 10, 10];
      await peer.start();
      final c = configure(peer);
      try {
        await c.connect();
        expect(c.canWrite, true);
        expect(c.canMove, false);
        expect(c.commonAngle, -10); // Old +10 lowered PWM position.
        expect(c.servos[0].previewPulse, 1700);
        c.setCommonAngle(10);
        expect(c.commonAngle, -10);
        c.setOffset(0, -27.5);
        await until(() => !c.pending && peer.offsets[0] == -27.5);
        expect(
          peer.commands.where((v) => v.startsWith('servo angles set ')),
          isEmpty,
        );
      } finally {
        await c.disconnect();
        c.dispose();
        await peer.close();
      }
    },
  );
}
