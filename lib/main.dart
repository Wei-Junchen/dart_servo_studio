import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controller.dart';
import 'widgets/dashboard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = StudioController();
  await controller.loadPreferences();
  runApp(ServoStudio(controller: controller));
}

class ServoStudio extends StatefulWidget {
  const ServoStudio({super.key, required this.controller});
  final StudioController controller;
  @override
  State<ServoStudio> createState() => _ServoStudioState();
}

class _ServoStudioState extends State<ServoStudio> {
  static const _window = MethodChannel('dart_servo_studio/window');
  AppLifecycleListener? _lifecycle;
  final List<StreamSubscription<ProcessSignal>> _signals = [];
  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await widget.controller.disconnect();
        return AppExitResponse.exit;
      },
    );
    _window.setMethodCallHandler((call) async {
      if (call.method == 'close_request') {
        await widget.controller.disconnect();
        await _window.invokeMethod<void>('close');
      }
    });
    if (!Platform.isWindows) {
      for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
        _signals.add(
          signal.watch().listen((_) async {
            await widget.controller.disconnect();
            exit(0);
          }),
        );
      }
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _window.setMethodCallHandler(null);
    for (final signal in _signals) {
      unawaited(signal.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Dart Servo Studio',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Noto Sans CJK SC',
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: const Color(0xff45dbc4),
            brightness: Brightness.dark,
          ).copyWith(
            primary: const Color(0xff45dbc4),
            surface: const Color(0xff11212e),
            onSurface: const Color(0xffdfebf3),
          ),
      scaffoldBackgroundColor: const Color(0xff0b1721),
      dividerColor: const Color(0xff263a49),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: const Color(0xff0c1924),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 13,
        ),
        labelStyle: const TextStyle(fontSize: 12, color: Color(0xff8a9eac)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xff2a3e4d)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xff2a3e4d)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          side: const BorderSide(color: Color(0xff304859)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      sliderTheme: const SliderThemeData(
        trackHeight: 3,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 400),
      ),
    ),
    home: Dashboard(controller: widget.controller),
  );
}
