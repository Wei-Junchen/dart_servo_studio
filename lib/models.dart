import 'dart:io';
import 'dart:math' as math;

const servoColors = [0xff45dbc4, 0xff659bff, 0xfff8bb65, 0xffdc87ef];
const canardPositionNames = ['左上', '右上', '右下', '左下'];
// Fixed rear-view quadrants, not camera-relative or PWM-relative.
double canardAzimuth(int index) => math.pi * 3 / 4 - index * math.pi / 2;

const defaultMapping = [3, 1, 2, 4];
const pwmChannels = {
  1: 'TIM3 · CH1',
  2: 'TIM3 · CH3',
  3: 'TIM3 · CH4',
  4: 'TIM3 · CH2',
};

class ConnectionSettings {
  String host = '127.0.0.1';
  int port = 19021;
  bool launchCommander = true;
  String commander = Platform.isWindows ? 'JLink.exe' : 'JLinkExe';
  String device = 'STM32F411CEUx';
  int speed = 4000;
  String serial = '';
  String elf = '/home/litwei/projects/2027_GuideDart/build/gcc/F411Frame.elf';
  String rttAddress = '';
  Map<String, Object> toJson() => {
    'host': host,
    'port': port,
    'launchCommander': launchCommander,
    'commander': commander,
    'device': device,
    'speed': speed,
    'serial': serial,
    'elf': elf,
    'rttAddress': rttAddress,
  };
  void load(Map<String, dynamic> map) {
    host = map['host'] as String? ?? host;
    port = map['port'] as int? ?? port;
    launchCommander = map['launchCommander'] as bool? ?? launchCommander;
    commander = map['commander'] as String? ?? commander;
    device = map['device'] as String? ?? device;
    speed = map['speed'] as int? ?? speed;
    serial = map['serial'] as String? ?? serial;
    elf = map['elf'] as String? ?? elf;
    rttAddress = map['rttAddress'] as String? ?? rttAddress;
  }
}

class ServoModel {
  ServoModel(this.id)
    : pwmIndex = defaultMapping[id],
      appliedPwm = defaultMapping[id];
  final int id;
  int get position => id + 1;
  int pwmIndex, appliedPwm;
  double angle = 0, appliedAngle = 0, offset = 0, appliedOffset = 0;
  // RTT protocol 4 uses the ordinary Servo_SetAng sign.
  double get commandAngle => angle;
  // Positive angle raises PWM position; positive offset lowers it.
  double get directionAngle => (commandAngle - offset).clamp(-90, 90);
  double get pwmPositionDelta => directionAngle;
  bool get directionClamped => (commandAngle - offset).abs() > 90;
  double get previewPulse =>
      ((90 + commandAngle - offset).clamp(0, 180) / 180 * 2000 + 500)
          .floorToDouble();
  double get pulse =>
      ((90 + appliedAngle - appliedOffset).clamp(0, 180) / 180 * 2000 + 500)
          .floorToDouble();
  bool get settingsDirty =>
      pwmIndex != appliedPwm || (offset - appliedOffset).abs() >= .0005;
}

class DeviceStatus {
  DeviceStatus(this.fields);
  final Map<String, String> fields;
  bool get idle => fields['idle'] == '1';
  bool get busy => fields['flash_busy'] == '1' || fields['save_pending'] == '1';
  bool get manual => fields['manual'] == '1';
  String get profile => fields['profile'] ?? '—';
  String get state => switch (fields['state']) {
    '0' => 'REST',
    '1' => 'AC',
    '2' => 'TGP',
    '3' => 'END',
    '4' => 'ADXL CAL',
    '5' => 'ICM CAL',
    _ => 'UNKNOWN',
  };
}

Map<String, String> parseFields(String text) => {
  for (final m in RegExp(r'([a-z_]+)=([^\s]+)').allMatches(text)) m[1]!: m[2]!,
};
List<double> parseFourDegrees(String? text, {double limit = 90}) {
  final values = text?.split(',').map(double.parse).toList();
  if (values == null ||
      values.length != 4 ||
      values.any((v) => !v.isFinite || v.abs() > limit)) {
    throw const FormatException('固件返回了无效的四路角度');
  }
  return values;
}

List<int> parseMapping(String? text) {
  final values = text?.split(',').map(int.parse).toList();
  if (values == null ||
      values.length != 4 ||
      values.toSet().length != 4 ||
      values.any((v) => v < 1 || v > 4)) {
    throw const FormatException('固件返回了无效的 PWM 映射');
  }
  return values;
}

String degrees(double value) {
  if (!value.isFinite) throw const FormatException('角度不能是 NaN / Inf');
  return value.toStringAsFixed(3);
}
