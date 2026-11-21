import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_servo_studio/main.dart';
import 'package:dart_servo_studio/controller.dart';
import 'package:dart_servo_studio/models.dart';
import 'package:dart_servo_studio/widgets/servo_scene.dart';
import 'package:dart_servo_studio/widgets/calibration_dialog.dart';

class NoPreferencesController extends StudioController {
  @override
  Future<void> savePreferences() async {}
}

void main() {
  testWidgets('v8 0° card uses absolute PWM microseconds instead of offset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1480, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController()
      ..connected = true
      ..clientControl = true
      ..protocol = 8
      ..calibrationServo = 0
      ..calibrationAngle = 0
      ..status = DeviceStatus({
        'idle': '1',
        'manual': '1',
        'flash_busy': '0',
        'save_pending': '0',
      });
    await tester.pumpWidget(ServoStudio(controller: c));
    expect(find.byKey(const ValueKey('curve-slider-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('offset-slider-0')), findsNothing);
    expect(find.textContaining('中点 PWM 1500'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('servo three-point mode is inline with PWM cards, not a dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1480, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController()
      ..connected = true
      ..clientControl = true
      ..protocol = 7
      ..status = DeviceStatus({
        'idle': '1',
        'manual': '1',
        'flash_busy': '0',
        'save_pending': '0',
      });
    await tester.pumpWidget(ServoStudio(controller: c));
    expect(find.byKey(const ValueKey('servo-cal-mode--30')), findsOneWidget);
    expect(find.byKey(const ValueKey('servo-cal-mode-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('servo-cal-mode-30')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('servo-calibration-button')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('offset-slider-0')), findsOneWidget);
    c.servoCalibrationMode = -30;
    c.calibrationServo = 0;
    c.calibrationAngle = -30;
    c.settingsChanged();
    await tester.pump();
    expect(find.byKey(const ValueKey('curve-slider-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('offset-slider-0')), findsNothing);
    expect(
      tester
          .widget<Slider>(find.byKey(const ValueKey('curve-slider-0')))
          .onChanged,
      isNotNull,
    );
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets(
    'ICM physical pose highlights the suggested face but never samples itself',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = StudioController()
        ..connected = true
        ..clientControl = true
        ..protocol = 6
        ..icmCalibration = {
          'status': '1',
          'valid': '0',
          'faces': '0',
          'raw_lsb': '0,0,0,0,0,0',
          'live_mps2': '0,-9.8,0',
          'live_raw_lsb': '2048,15,-10',
          'one_g_lsb': '2048',
          'live_samples': '25',
        }
        ..savedCalibration = {
          'valid': '5',
          'icm_range_g': '16',
          'current_range_g': '16',
          'basis_valid': '1',
          'icm_lsb': '2100,-2000,2080,-2030,2050,-2070',
          'adxl_offset': '1.250,-2.500,0.750',
          'applied_adxl': '1.250,-2.500,0.750',
        };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CalibrationDialog(controller: c)),
        ),
      );
      expect(find.text('X+ · 99% 匹配'), findsOneWidget);
      expect(find.text('建议采样'), findsOneWidget);
      expect(find.text('Flash 已保存 · 已验证快照'), findsOneWidget);
      expect(find.text('已保存 · 量程匹配'), findsOneWidget);
      expect(find.text('Flash XYZ：1.250,-2.500,0.750 m/s²'), findsOneWidget);
      expect(c.icmCalibration['faces'], '0');
      c.icmCalibration['live_raw_lsb'] = '-2000,40,0';
      c.savedCalibration['current_range_g'] = '8';
      c.settingsChanged();
      await tester.pump();
      expect(find.text('X− · 97% 匹配'), findsOneWidget);
      expect(find.text('量程不匹配：这组 Flash 六面值不会在启动时应用。'), findsOneWidget);
      expect(c.icmCalibration['faces'], '0');
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'connected RAM sliders are editable without unlock or confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(1480, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = StudioController()
        ..connected = true
        ..clientControl = true
        ..protocol = 4
        ..status = DeviceStatus({
          'idle': '1',
          'manual': '0',
          'flash_busy': '0',
          'save_pending': '0',
        });
      await tester.pumpWidget(ServoStudio(controller: controller));
      await tester.pump();
      expect(controller.canWrite, true);
      expect(find.text('解锁手动控制'), findsNothing);
      expect(find.text('应用设置'), findsNothing);
      final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('offset-slider-0')),
      );
      expect(slider.onChanged, isNotNull);
      slider.onChanged!(-27.5);
      await tester.pump();
      expect(controller.servos[0].offset, -27.5);
      expect(controller.servos.every((s) => s.angle == 0), true);
      tester
          .widget<Slider>(find.byKey(const ValueKey('common-angle-slider')))
          .onChanged!(12.5);
      await tester.pump();
      expect(controller.servos.map((s) => s.angle), [12.5, 12.5, 12.5, 12.5]);
      expect(controller.servos[0].offset, -27.5);
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.manual, false);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  for (final size in [
    const Size(1480, 1000),
    const Size(1100, 720),
    const Size(900, 700),
  ]) {
    testWidgets(
      'offline desktop layout $size has no overflow or hardware connection',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = StudioController();
        await tester.pumpWidget(ServoStudio(controller: controller));
        await tester.pump();
        expect(find.text('DART / SERVO STUDIO'), findsOneWidget);
        expect(find.text('OFFLINE'), findsOneWidget);
        expect(find.byType(ServoScene), findsOneWidget);
        expect(controller.connected, false);
        expect(controller.logs, isEmpty);
        controller.setOffset(0, 20);
        controller.setCommonAngle(15);
        await tester.pump();
        expect(controller.servos[0].offset, 20);
        expect(controller.servos.every((s) => s.angle == 15), true);
        await tester.drag(find.byType(ServoScene), const Offset(80, 30));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }

  testWidgets(
    'only Flash saving asks for confirmation; offset and common neutral do not',
    (tester) async {
      tester.view.physicalSize = const Size(1480, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = StudioController()
        ..connected = true
        ..clientControl = true
        ..protocol = 4
        ..status = DeviceStatus({
          'idle': '1',
          'manual': '0',
          'flash_busy': '0',
          'save_pending': '0',
        });
      await tester.pumpWidget(ServoStudio(controller: controller));
      await tester.tap(find.text('保存 Flash'));
      await tester.pumpAndSettle();
      expect(find.text('保存到 Flash'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();

      final offline = StudioController()
        ..setOffset(0, -27)
        ..setCommonAngle(15);
      await tester.pumpWidget(ServoStudio(controller: offline));
      await tester.tap(find.byKey(const ValueKey('common-angle-neutral')));
      await tester.pumpAndSettle();
      expect(offline.servos.every((s) => s.angle == 0), true);
      expect(offline.servos[0].offset, -27);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
      offline.dispose();
    },
  );

  testWidgets(
    'four angled leading-edge canards keep rear-view selection while orbiting',
    (tester) async {
      tester.view.physicalSize = const Size(1480, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = StudioController();
      await tester.pumpWidget(ServoStudio(controller: controller));
      for (int i = 0; i < 4; i++) {
        controller.setOffset(i, i.isEven ? 30 : -30);
      }
      controller.setCommonAngle(20);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('camera-rear-view')));
      await tester.pump();
      for (int i = 0; i < 4; i++) {
        await tester.tap(find.byKey(ValueKey('rear-position-${i + 1}')));
        await tester.pump();
        expect(controller.selectedServo, i);
        expect(controller.servos[i].offset, i.isEven ? 30 : -30);
        expect(controller.servos[i].commandAngle, 20);
      }
      await tester.tap(find.byKey(const ValueKey('camera-flat-view')));
      await tester.pump();
      for (final drag in [
        const Offset(-130, 20),
        const Offset(300, -120),
        const Offset(-170, 200),
      ]) {
        await tester.drag(find.byType(ServoScene), drag);
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      expect(controller.connected, false);
      expect(controller.logs, isEmpty);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'connection settings stay behind gear; offset buttons step 0.1 without dialog',
    (tester) async {
      tester.view.physicalSize = const Size(1480, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = NoPreferencesController();
      await tester.pumpWidget(ServoStudio(controller: c));
      expect(find.byKey(const ValueKey('connect-button')), findsOneWidget);
      expect(find.text('RTT TCP Host'), findsNothing);
      expect(
        find.byKey(const ValueKey('positive-direction-switch')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('connection-settings-button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('连接设置'), findsOneWidget);
      expect(find.text('Firmware ELF'), findsOneWidget);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('offset-plus-0')));
      await tester.pump();
      expect(c.servos[0].offset, 0.1);
      await tester.tap(find.byKey(const ValueKey('offset-minus-0')));
      await tester.pump();
      expect(c.servos[0].offset, 0);
      c.setOffset(0, 12);
      c.setOffset(1, -3);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('clear-all-offsets')));
      await tester.pump();
      expect(c.servos.every((s) => s.offset == 0), true);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  test('3D canard angle ignores offset but follows the sent common angle', () {
    final servo = ServoModel(0)..angle = 15;
    expect(canardPreviewAngle(servo), -15);
    servo.offset = 67;
    expect(canardPreviewAngle(servo), -15);
    servo.angle = -15;
    expect(canardPreviewAngle(servo), 15);
  });
  testWidgets(
    'keyboard up/down choose canard; left/right and -/= nudge offset',
    (tester) async {
      tester.view.physicalSize = const Size(1480, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = NoPreferencesController();
      await tester.pumpWidget(ServoStudio(controller: c));
      await tester.pump();
      expect(c.selectedServo, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(c.selectedServo, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.pump();
      expect(c.servos[1].offset, 0.1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(c.servos[1].offset, 0.2);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(c.servos[1].offset, 0.1);
      await tester.tap(find.byKey(const ValueKey('common-angle-slider')));
      await tester.pump();
      final commonAngle = c.commonAngle;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(c.servos[1].offset, 0.2); // Even after testing the common slider.
      expect(c.commonAngle, commonAngle);
      await tester.sendKeyEvent(LogicalKeyboardKey.minus);
      await tester.pump();
      expect(c.servos[1].offset, 0.1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(c.selectedServo, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(c.selectedServo, 3); // Wrap at the ends.
      await tester.tap(find.byKey(const ValueKey('offset-slider-0')));
      await tester.pump();
      c.selectServo(0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(c.selectedServo, 1); // Still works after a slider was clicked.
      final untouched = c.servos[1].offset;
      await tester.tap(find.byKey(const ValueKey('offset-input-0')));
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.pump();
      expect(c.servos[1].offset, untouched); // Typing must not move a servo.
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets('held offset key repeats, accelerates, and stops on release', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1480, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = NoPreferencesController();
    await tester.pumpWidget(ServoStudio(controller: c));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(c.servos[0].offset, 0.1);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(c.servos[0].offset, 0.1); // Ignore native repeat; use our timer.
    await tester.pump(const Duration(milliseconds: 349));
    expect(c.servos[0].offset, 0.1);
    await tester.pump(const Duration(milliseconds: 101));
    expect(c.servos[0].offset, greaterThan(0.1));
    await tester.pump(const Duration(seconds: 3));
    expect(c.servos[0].offset, greaterThan(5)); // Accelerated hold.
    final held = c.servos[0].offset;
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(seconds: 1));
    expect(c.servos[0].offset, held);

    c.setOffset(0, 89.9);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.equal);
    await tester.pump(const Duration(seconds: 2));
    expect(c.servos[0].offset, 90); // Never exceed the firmware's limit.
    await tester.sendKeyUpEvent(LogicalKeyboardKey.equal);

    // Moving into a text field cancels an ongoing hold instead of editing RAM.
    c.setOffset(0, 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.equal);
    await tester.pump();
    final beforeInput = c.servos[0].offset;
    await tester.tap(find.byKey(const ValueKey('offset-input-0')));
    await tester.pump(const Duration(seconds: 1));
    expect(c.servos[0].offset, beforeInput);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.equal);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  for (final protocol in [2, 3]) {
    testWidgets(
      'protocol $protocol disables the test-angle slider but keeps offset controls',
      (tester) async {
        tester.view.physicalSize = const Size(1480, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = NoPreferencesController()
          ..connected = true
          ..clientControl = true
          ..protocol = protocol
          ..status = DeviceStatus({
            'idle': '1',
            'flash_busy': '0',
            'save_pending': '0',
          });
        await tester.pumpWidget(ServoStudio(controller: c));
        expect(
          tester
              .widget<Slider>(find.byKey(const ValueKey('common-angle-slider')))
              .onChanged,
          isNull,
        );
        expect(
          tester
              .widget<Slider>(find.byKey(const ValueKey('offset-slider-0')))
              .onChanged,
          isNotNull,
        );
        expect(find.text('协议 $protocol：测试角禁用'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  }
}
