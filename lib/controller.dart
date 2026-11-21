import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'services/rtt_client.dart';
import 'services/jlink_session.dart';

class StudioController extends ChangeNotifier {
  void settingsChanged() => _changed();
  final settings = ConnectionSettings();
  final servos = List.generate(4, ServoModel.new);
  final invalidOffsets = <int>{};
  bool get draftValid => invalidOffsets.isEmpty;
  final List<String> logs = [];
  final JLinkSession _jlink = JLinkSession();
  RttClient? _client;
  DeviceStatus? status;
  bool connected = false, connecting = false, operation = false, manual = false;
  bool clientControl = false;
  bool calibrationOpen = false;
  Map<String, String> icmCalibration = {}, adxlCalibration = {};
  Map<String, String> savedCalibration = {};
  bool _disconnecting = false, _disposed = false, _angleDirty = false;
  bool _nudgeSending = false;
  int _queuedNudgeUs = 0, _nudgeServo = -1, _nudgeMode = 0;
  bool _tickRunning = false;
  double commonAngle = 0;
  int protocol = 0, selectedServo = 0, servoCalibrationMode = 0;
  int? address;
  String message = '离线预览 · 尚未连接设备';
  List<double>? savedOffsets;
  List<int>? savedMapping;
  ServoCurves? savedCurves;
  int? calibrationServo;
  int calibrationAngle = 0;
  Timer? _timer;
  DateTime _heartbeat = DateTime(2000), _poll = DateTime(2000);
  DateTime _controlHeartbeat = DateTime(2000);
  DateTime _calPoll = DateTime(2000);
  bool get supported => protocol >= 2;
  bool get canWrite =>
      connected &&
      clientControl &&
      supported &&
      !operation &&
      !_disconnecting &&
      status?.idle == true &&
      status?.busy == false;
  bool get draftDirty => servos.any((s) => s.settingsDirty);
  bool get canMove => canWrite && draftValid && protocol >= 4;
  bool get keyboardNudgeInFlight =>
      _nudgeSending && connected && !_disconnecting;
  void cancelQueuedNudges() => _queuedNudgeUs = 0;
  bool get editable =>
      !connecting && !_disconnecting && !operation && (!connected || canWrite);
  bool get pending => draftDirty || _angleDirty;
  bool get mixedAngles =>
      servos.any((s) => (s.angle - commonAngle).abs() >= .0005);
  bool get canSaveFlash => canWrite && draftValid;
  bool get flashMatches =>
      savedOffsets != null &&
      savedMapping != null &&
      List.generate(
        4,
        (i) =>
            (savedOffsets![i] - servos[i].appliedOffset).abs() < .0005 &&
            savedMapping![i] == servos[i].appliedPwm,
      ).every((v) => v) &&
      (protocol < 7 ||
          (savedCurves != null &&
              _curvesEqual(savedCurves!, _currentCurves())));

  ServoCurves _currentCurves() => ServoCurves(
    servos.map((s) => s.neg30Us).toList(),
    servos.map((s) => s.pos30Us).toList(),
    List.generate(
      4,
      (i) =>
          (servos[i].neg30Valid ? 1 << i : 0) |
          (servos[i].pos30Valid ? 1 << (i + 4) : 0),
    ).fold(0, (a, b) => a | b),
    protocol >= 8 ? servos.map((s) => s.zeroUs).toList() : null,
  );

  bool _curvesEqual(ServoCurves a, ServoCurves b) =>
      a.mask == b.mask &&
      listEquals(a.neg, b.neg) &&
      listEquals(a.pos, b.pos) &&
      listEquals(a.zero, b.zero);

  void _installCurves(ServoCurves curves) {
    for (var i = 0; i < 4; i++) {
      servos[i].neg30Valid = curves.mask & (1 << i) != 0;
      servos[i].pos30Valid = curves.mask & (1 << (i + 4)) != 0;
      servos[i].neg30Us = curves.neg[i];
      servos[i].pos30Us = curves.pos[i];
      if (curves.zero != null) {
        servos[i].useZeroUs = true;
        servos[i].zeroUs = curves.zero![i];
        servos[i].offset = servos[i].appliedOffset =
            (1500 - curves.zero![i]) * 180 / 2000;
      }
    }
    _changed();
  }

  File get preferencesFile {
    final env = Platform.environment;
    final root = Platform.isWindows
        ? env['APPDATA']
        : env['XDG_CONFIG_HOME'] ?? '${env['HOME']}/.config';
    return File('$root/dart_servo_studio/settings.json');
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void log(String text) {
    if (text.isEmpty) return;
    final time = DateTime.now().toIso8601String().substring(11, 19);
    for (final line in text.split('\n')) {
      if (line.trim().isNotEmpty) logs.add('$time  ${line.trim()}');
    }
    if (logs.length > 160) logs.removeRange(0, logs.length - 160);
    _changed();
  }

  Future<void> loadPreferences() async {
    try {
      if (await preferencesFile.exists()) {
        final json = jsonDecode(
          await preferencesFile.readAsString(),
        ) as Map<String, dynamic>;
        settings.load(json['connection'] as Map<String, dynamic>? ?? {});
      }
    } catch (e) {
      log('本地设置未加载：$e');
    }
    _changed();
  }

  Future<void> savePreferences() async {
    try {
      final file = preferencesFile;
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode({'connection': settings.toJson()}),
      );
      await temporary.rename(file.path);
    } catch (e) {
      log('本地设置未保存：$e');
    }
  }

  Future<void> connect() async {
    if (connecting || connected || _disconnecting) return;
    connecting = true;
    message = '正在连接 J-Link / RTT…';
    _changed();
    _jlink.onLog = log;
    try {
      address = await _jlink.resolveAddress(settings);
      log(
        address == null
            ? 'RTT 使用自动发现；失败时请填写匹配的 ELF 或地址'
            : 'RTT 地址 0x${address!.toRadixString(16)}（仅解析，不下载固件）',
      );
      if (settings.launchCommander) await _jlink.start(settings);
      final client = _client = RttClient(
        onLog: log,
        onDisconnect: (error) {
          log('$error');
          message = '$error';
          unawaited(disconnect(sendStop: false, preserveMessage: true));
        },
      );
      await client.connect(settings.host, settings.port, address: address);
      final protocolToken =
          parseFields(await client.command('ping'))['protocol'] ?? '';
      // v4 is intentionally non-numeric so old GUIs fail closed rather than
      // applying their former protocol>=3 angle convention to new firmware.
      protocol =
          int.tryParse(protocolToken.replaceFirst(RegExp(r'^v'), '')) ?? 0;
      await _readSettings();
      final ownership = parseFields(
        await client.command('servo control acquire'),
      );
      if (ownership['active'] != '1') throw StateError('MCU 未交出舵机控制权，连接已拒绝');
      clientControl = true;
      _controlHeartbeat = DateTime.now();
      status = DeviceStatus({...?status?.fields, 'control': '1'});
      connected = true;
      message = protocol >= 8
          ? '连接成功 · 三点 PWM 均按整数 µs 校准；修改只写 RAM'
          : protocol >= 4
          ? '连接成功 · 正测试角提高 PWM 位置、正 offset 降低 PWM 位置；修改写入 RAM'
          : supported
          ? '旧协议 $protocol：offset / 映射可调；升级固件至协议 4 后可调统一测试角'
          : '固件协议 $protocol：仅只读，请下载新版固件启用角度 / PWM 映射';
      _timer = Timer.periodic(
        const Duration(milliseconds: 80),
        (_) => unawaited(_tick()),
      );
      await savePreferences();
    } catch (e) {
      message = '连接失败：$e';
      log(message);
      await disconnect(sendStop: false, preserveMessage: true);
    } finally {
      connecting = false;
      _changed();
    }
  }

  Future<void> _readSettings() async {
    invalidOffsets.clear();
    final client = _client!;
    status = DeviceStatus(parseFields(await client.command('status')));
    if (clientControl && status!.fields['control'] != '1') {
      throw StateError('MCU 舵机控制租约已失效');
    }
    final offsets = protocol >= 8
        ? List<double>.filled(4, 0)
        : parseFourDegrees(
            parseFields(await client.command('servo get'))['offset_deg'],
          );
    List<double> angles = [0, 0, 0, 0];
    List<int> mapping = List.of(defaultMapping);
    if (supported) {
      final fields = parseFields(await client.command('servo angles get'));
      angles = parseFourDegrees(fields['angle_deg'], limit: 90);
      mapping = parseMapping(fields['pwm_index']);
    }
    for (int i = 0; i < 4; i++) {
      final s = servos[i];
      s.offset = s.appliedOffset = offsets[i];
      s.pwmIndex = s.appliedPwm = mapping[i];
      // Protocol 3 used the inverted public test angle. Protocol 2 and 4
      // use the ordinary Servo_SetAng / PWM-positive direction.
      s.appliedAngle = s.angle = protocol == 3 ? -angles[i] : angles[i];
    }
    if (protocol >= 7) {
      _installCurves(
        ServoCurves.parse(parseFields(await client.command('servo curve get'))),
      );
    }
    commonAngle = angles.every((v) => (v - angles.first).abs() < .0005)
        ? (protocol == 3 ? -angles.first : angles.first).clamp(-30, 30)
        : 0;
    _angleDirty = false;
    savedOffsets = null;
    savedMapping = null;
    savedCurves = null;
    if (protocol < 8) {
      try {
        savedOffsets = parseFourDegrees(
          parseFields(await client.command('servo saved'))['offset_deg'],
        );
      } on RttCommandError catch (e) {
        if (!e.message.startsWith('NO_SAVED_SERVO')) rethrow;
      }
    }
    if (supported) {
      try {
        savedMapping = parseMapping(
          parseFields(await client.command('servo map saved'))['pwm_index'],
        );
      } on RttCommandError catch (e) {
        if (!e.message.startsWith('NO_SAVED_MAPPING')) rethrow;
      }
    }
    if (protocol >= 7 && (savedOffsets != null || protocol >= 8)) {
      try {
        savedCurves = ServoCurves.parse(
          parseFields(await client.command('servo curve saved')),
        );
        if (protocol >= 8 && savedCurves!.zero != null) {
          savedOffsets = savedCurves!.zero!
              .map((us) => (1500 - us) * 180 / 2000)
              .toList();
        }
      } on RttCommandError catch (e) {
        if (!e.message.startsWith('NO_SAVED_SERVO')) rethrow;
      }
    }
    _changed();
  }

  Future<void> refresh() => pending || !draftValid
      ? Future<void>.value()
      : _action(() async {
          await _readSettings();
          message = '已读取设备当前设置';
        });

  Future<void> _tick() async {
    final client = _client;
    if (!connected ||
        operation ||
        _tickRunning ||
        client == null ||
        client.busy ||
        _disconnecting) {
      return;
    }
    _tickRunning = true;
    final now = DateTime.now();
    bool changed = false;
    try {
      if (clientControl &&
          now.difference(_controlHeartbeat).inMilliseconds >= 450) {
        final control = parseFields(
          await client.command('servo control keepalive'),
        );
        if (control['active'] != '1') throw StateError('MCU 舵机控制租约已失效');
        _controlHeartbeat = DateTime.now();
        if (manual) {
          await client.command('servo manual keepalive');
          _heartbeat = DateTime.now();
        }
      } else if (manual && now.difference(_heartbeat).inMilliseconds >= 450) {
        await client.command('servo manual keepalive');
        _heartbeat = DateTime.now();
      } else if (canWrite && draftValid && pending) {
        // First user edit automatically acquires the MCU lease. No UI unlock.
        await _ensureManual();
        await _flushRam();
        if (canMove && _angleDirty) await _flushAngles();
        message = pending ? '正在同步最新修改到 RAM…' : '修改已写入 RAM · 尚未保存 Flash';
        changed = true;
      } else if (calibrationOpen &&
          protocol >= 5 &&
          now.difference(_calPoll).inMilliseconds >= 400) {
        await _readCalibration();
        _calPoll = DateTime.now();
        changed = true;
      } else if (now.difference(_poll).inMilliseconds >= 800) {
        final next = DeviceStatus(parseFields(await client.command('status')));
        if (clientControl && next.fields['control'] != '1') {
          throw StateError('MCU 舵机控制租约已失效');
        }
        changed = !mapEquals(status?.fields, next.fields);
        status = next;
        _poll = DateTime.now();
        if (manual && !status!.manual) {
          manual = false;
          servoCalibrationMode = 0;
          calibrationServo = null;
          _angleDirty = false;
          _resetAngles();
          message = '设备已退出测试（超时 / 状态变化）· 统一角已回中，offset 保留';
          log(message);
        }
      }
      if (changed) _changed();
    } catch (e) {
      message = '$e';
      log(message);
      // Rejected / ambiguous control is not retried. MCU lease is the final fallback.
      _tickRunning = false;
      await disconnect(preserveMessage: true);
    } finally {
      _tickRunning = false;
    }
  }

  Future<void> _waitIdle() async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while ((_client?.busy == true || _tickRunning) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 15));
    }
    if (_client == null || _client!.busy || _tickRunning) {
      throw StateError('RTT 链路不可用');
    }
  }

  void openCalibration() {
    if (!connected || protocol < 5 || pending || operation) return;
    calibrationOpen = true;
    icmCalibration = {};
    adxlCalibration = {};
    savedCalibration = {};
    _calPoll = DateTime(2000);
    _changed();
  }

  void closeCalibration() {
    calibrationOpen = false;
    _changed();
  }

  Future<void> _readCalibration() async {
    final client = _client!;
    icmCalibration = parseFields(await client.command('cal icm info'));
    adxlCalibration = parseFields(await client.command('cal adxl info'));
    if (savedCalibration.isEmpty) await _readSavedCalibration();
    status = DeviceStatus(parseFields(await client.command('status')));
    _poll = DateTime.now();
    _changed();
  }

  Future<void> _readSavedCalibration() async {
    try {
      savedCalibration = parseFields(await _client!.command('cal saved'));
    } on RttCommandError catch (e) {
      if (!e.message.contains('UNKNOWN_COMMAND')) rethrow;
      savedCalibration = {'unsupported': '1'};
    }
    _changed();
  }

  Future<void> refreshSavedCalibration() async {
    if (!connected || !calibrationOpen || operation) return;
    await _action(() async {
      await _readSavedCalibration();
      message = savedCalibration['unsupported'] == '1'
          ? '板上固件不支持读取已保存的校准值；请更新固件'
          : '已读取 Flash 已验证配置快照（只读）';
    });
  }

  Future<void> calibrationCommand(String command, {bool flash = false}) async {
    if (!connected || protocol < 5 || operation) return;
    operation = true;
    _changed();
    try {
      await _waitIdle();
      if (manual) await _stopManual();
      await _client!.command(command, flash: flash);
      await _readCalibration();
      if (flash) await _readSavedCalibration();
      _calPoll = DateTime.now();
      message = flash ? '校准参数已写入 Flash 并回读验证' : '校准请求已发送；结果仅在 RAM，保存由你决定';
    } on RttCommandError catch (e) {
      message = '$e';
      log(message);
      await _readCalibration();
    } catch (e) {
      message = '$e';
      log(message);
      await disconnect(preserveMessage: true);
    } finally {
      operation = false;
      _changed();
    }
  }

  Future<void> _action(Future<void> Function() body) async {
    if (operation || !connected) return;
    operation = true;
    _changed();
    try {
      await _waitIdle();
      await body();
    } catch (e) {
      message = '$e';
      log(message);
      // Never replay a rejected/ambiguous RAM write in a subsequent timer tick.
      await disconnect(preserveMessage: true);
    } finally {
      operation = false;
      _changed();
    }
  }

  Future<void> _ensureManual() async {
    if (manual) return;
    final fields = parseFields(await _client!.command('servo manual start'));
    if (fields['active'] != '1') throw StateError('固件未进入舵机测试模式');
    manual = true;
    _heartbeat = DateTime.now();
    for (final s in servos) {
      s.appliedAngle = 0;
    }
    // Preserve a queued common-angle request; offset-only entry starts at 0°.
    if (!_angleDirty) _resetAngles();
    status = DeviceStatus({...?status?.fields, 'manual': '1'});
  }

  Future<void> disarm() async {
    servoCalibrationMode = 0;
    calibrationServo = null;
    if (!manual || !connected) return;
    await _action(() async {
      await _flushRam();
      await _stopManual();
    });
  }

  Future<void> _stopManual() async {
    await _client!.command('servo manual stop');
    manual = false;
    calibrationServo = null;
    _resetAngles();
    status = DeviceStatus(parseFields(await _client!.command('status')));
    message = '统一角已回中并释放测试控制 · offset 保留，下一次修改直接生效';
  }

  Future<void> neutral() async {
    if (!editable) return;
    servoCalibrationMode = 0;
    calibrationServo = null;
    if (!connected) {
      setCommonAngle(0);
      return;
    }
    await _action(() async {
      await _ensureManual();
      await _flushRam();
      await _client!.command('servo neutral');
      _resetAngles();
      await _client!.command('servo manual keepalive');
      _heartbeat = DateTime.now();
      message = '四路 servo_angle 已统一回到 0°（保留各自 offset）';
    });
  }

  void selectServo(int id) {
    if (id < 0 || id >= servos.length) return;
    if ((servoCalibrationMode != 0 || protocol >= 8) && operation) return;
    selectedServo = id;
    _changed();
    if ((servoCalibrationMode != 0 || protocol >= 8) && canMove) {
      unawaited(moveCalibrationTarget(id, servoCalibrationMode));
    }
  }

  Future<void> setServoCalibrationMode(int angle) async {
    if (![-30, 0, 30].contains(angle) || !editable) return;
    if (angle != 0 && (!connected || protocol < 7 || !canMove)) return;
    servoCalibrationMode = angle;
    _changed();
    if (angle == 0 && protocol < 8) {
      calibrationServo = null;
      if (connected && manual) await neutral();
    } else {
      await moveCalibrationTarget(selectedServo, angle);
    }
  }

  bool canTuneCalibrationPoint(int id) =>
      (servoCalibrationMode != 0 || protocol >= 8) &&
      canWrite &&
      calibrationServo == id &&
      calibrationAngle == servoCalibrationMode;

  void nudgeActiveValue(int id, int direction, {int steps = 1}) {
    if (servoCalibrationMode == 0 && protocol < 8) {
      nudgeOffset(id, direction, steps: steps);
      return;
    }
    if (!(canTuneCalibrationPoint(id) ||
            (protocol >= 8 &&
                _nudgeSending &&
                _nudgeServo == id &&
                _nudgeMode == servoCalibrationMode &&
                connected &&
                !_disconnecting &&
                status?.idle == true)) ||
        direction.abs() != 1 ||
        steps < 1 ||
        steps > 5) {
      return;
    }
    if (protocol >= 8) {
      if (_nudgeServo != id || _nudgeMode != servoCalibrationMode) {
        _queuedNudgeUs = 0;
        _nudgeServo = id;
        _nudgeMode = servoCalibrationMode;
      }
      _queuedNudgeUs = (_queuedNudgeUs + direction * steps).clamp(-500, 500);
      if (!_nudgeSending) unawaited(_drainNudges());
      return;
    }
    _nudgeOnce(id, direction * steps);
  }

  Future<void> _drainNudges() async {
    _nudgeSending = true;
    try {
      while (_queuedNudgeUs != 0 &&
          connected &&
          !_disconnecting &&
          calibrationServo == _nudgeServo &&
          calibrationAngle == _nudgeMode) {
        final delta = _queuedNudgeUs.clamp(-5, 5);
        _queuedNudgeUs -= delta;
        final next = _nudgeTarget(_nudgeServo, delta);
        if (next == null) continue;
        await tuneCalibrationPoint(_nudgeServo, _nudgeMode, next);
      }
    } finally {
      _queuedNudgeUs = 0;
      _nudgeSending = false;
    }
  }

  void _nudgeOnce(int id, int delta) {
    final next = _nudgeTarget(id, delta);
    if (next != null) {
      unawaited(tuneCalibrationPoint(id, servoCalibrationMode, next));
    }
  }

  int? _nudgeTarget(int id, int delta) {
    final servo = servos[id];
    final center = servo.useZeroUs
        ? servo.zeroUs.toDouble()
        : 1500 - servo.offset * 2000 / 180;
    final positive = servoCalibrationMode > 0;
    final current = servoCalibrationMode == 0
        ? servo.zeroUs
        : positive
        ? (servo.pos30Valid ? servo.pos30Us : (center + 2000 / 6).round())
        : (servo.neg30Valid ? servo.neg30Us : (center - 2000 / 6).round());
    final lower = servoCalibrationMode == 0
        ? 500
        : positive
        ? center.floor() + 1
        : 500;
    final upper = servoCalibrationMode == 0
        ? 2500
        : positive
        ? 2500
        : center.ceil() - 1;
    if (lower > upper) return null;
    final next = (current + delta).clamp(lower, upper);
    return next == current ? null : next;
  }

  void setCommonAngle(double value) {
    if (!editable || (connected && !canMove) || !value.isFinite) return;
    servoCalibrationMode = 0;
    commonAngle = double.parse(degrees(value.clamp(-30, 30)));
    calibrationServo = null;
    for (final s in servos) {
      s.angle =
          commonAngle; // Protocol 3 sends the same positive angle to all four.
    }
    if (connected) _angleDirty = true;
    _changed();
  }

  void clearAllOffsets() {
    if (!editable) return;
    if (protocol >= 8) {
      if (!connected) {
        for (final servo in servos) {
          servo.zeroUs = 1500;
        }
        message = '离线预览：四路中点已回到 1500 µs';
        _changed();
        return;
      }
      unawaited(
        _action(() async {
          await _ensureManual();
          for (var i = 0; i < 4; i++) {
            await _keepaliveIfDue();
            final curves = ServoCurves.parse(
              parseFields(
                await _client!.command('servo curve set $i zero 1500'),
              ),
            );
            _installCurves(curves);
          }
          message = '四路中点回到 1500 µs，已写入 RAM · Flash 未修改';
        }),
      );
      return;
    }
    invalidOffsets.clear();
    for (final servo in servos) {
      servo.offset = 0;
    }
    message = connected
        ? (protocol >= 8
              ? '四路中点回到 1500 µs，正在写入 RAM · Flash 未修改'
              : '四路 offset 归零，正在写入 RAM · Flash 未修改')
        : '离线预览：四路中点已回到 1500 µs';
    _changed();
  }

  Future<void> loadFlashToRam() async {
    if (!canWrite) return;
    await _action(() async {
      final client = _client!;
      if (protocol >= 8) {
        final curves = ServoCurves.parse(
          parseFields(await client.command('servo curve saved')),
        );
        final centers = curves.zero;
        if (centers == null) throw StateError('Flash 缺少 0° PWM 校准值');
        final mapping = parseMapping(
          parseFields(await client.command('servo map saved'))['pwm_index'],
        );
        await _ensureManual();
        if (!listEquals(mapping, servos.map((s) => s.appliedPwm).toList())) {
          await client.command('servo map set ${mapping.join(' ')}');
        }
        for (var i = 0; i < 4; i++) {
          await _keepaliveIfDue();
          await client.command('servo curve set $i zero ${centers[i]}');
        }
        for (var i = 0; i < 4; i++) {
          for (final positive in [false, true]) {
            await _keepaliveIfDue();
            final bit = 1 << (i + (positive ? 4 : 0));
            final side = positive ? 'pos' : 'neg';
            final command = curves.mask & bit != 0
                ? 'servo curve set $i $side ${positive ? curves.pos[i] : curves.neg[i]}'
                : 'servo curve reset $i $side';
            await client.command(command);
          }
        }
        _installCurves(
          ServoCurves.parse(
            parseFields(await client.command('servo curve get')),
          ),
        );
        for (var i = 0; i < 4; i++) {
          servos[i].pwmIndex = servos[i].appliedPwm = mapping[i];
        }
        if (!_curvesEqual(curves, _currentCurves())) {
          throw StateError('Flash 三点校准载入 RAM 后回读不一致');
        }
        savedCurves = curves;
        savedMapping = mapping;
        savedOffsets = centers.map((us) => (1500 - us) * 180 / 2000).toList();
        message = '已从 Flash 载入三点 PWM 与通道映射到 RAM · 未写 Flash';
        log(message);
        return;
      }
      List<double> offsets;
      try {
        offsets = parseFourDegrees(
          parseFields(await client.command('servo saved'))['offset_deg'],
        );
      } on RttCommandError catch (e) {
        if (!e.message.startsWith('NO_SAVED_SERVO')) rethrow;
        savedOffsets = null;
        message = 'Flash 没有已保存的舵机 offset；RAM 保持不变';
        log(message);
        return;
      }
      List<int>? mapping;
      try {
        mapping = parseMapping(
          parseFields(await client.command('servo map saved'))['pwm_index'],
        );
      } on RttCommandError catch (e) {
        if (!e.message.startsWith('NO_SAVED_MAPPING')) rethrow;
      }
      final curves = protocol >= 7
          ? ServoCurves.parse(
              parseFields(await client.command('servo curve saved')),
            )
          : null;
      // Validate the complete snapshot before touching RAM. Old Flash records
      // may contain offsets but no PWM map; preserve the live map in that case.
      savedOffsets = offsets;
      savedMapping = mapping;
      invalidOffsets.clear();
      for (int i = 0; i < 4; i++) {
        servos[i].offset = offsets[i];
        if (mapping != null) servos[i].pwmIndex = mapping[i];
      }
      if (draftDirty) {
        await _ensureManual();
        await _flushRam();
      }
      if (curves != null && !_curvesEqual(curves, _currentCurves())) {
        await _ensureManual();
        if (curves.zero != null) {
          for (var i = 0; i < 4; i++) {
            await client.command('servo curve set $i zero ${curves.zero![i]}');
          }
        }
        for (var i = 0; i < 4; i++) {
          for (final positive in [false, true]) {
            final bit = 1 << (i + (positive ? 4 : 0));
            final side = positive ? 'pos' : 'neg';
            final command = curves.mask & bit != 0
                ? 'servo curve set $i $side ${positive ? curves.pos[i] : curves.neg[i]}'
                : 'servo curve reset $i $side';
            await client.command(command);
          }
        }
        _installCurves(
          ServoCurves.parse(
            parseFields(await client.command('servo curve get')),
          ),
        );
        if (!_curvesEqual(curves, _currentCurves())) {
          throw StateError('Flash 曲线载入 RAM 后回读不一致');
        }
      }
      savedCurves = curves;
      message = mapping == null
          ? '已从 Flash 载入 offset 到 RAM；旧记录无 PWM 映射，保留当前通道'
          : '已从 Flash 载入 offset 与 PWM 映射到 RAM · 未写 Flash';
      log(message);
    });
  }

  void selectRelativeServo(int direction) {
    if (direction != -1 && direction != 1) return;
    selectServo((selectedServo + direction + servos.length) % servos.length);
  }

  void nudgeOffset(int id, int direction, {int steps = 1}) {
    if (!editable ||
        id < 0 ||
        id >= servos.length ||
        (direction != -1 && direction != 1) ||
        steps < 1 ||
        steps > 5) {
      return;
    }
    final next = (servos[id].offset + direction * steps * 0.1)
        .clamp(-90, 90)
        .toDouble();
    if ((next - servos[id].offset).abs() < 0.0005) return;
    setOffset(id, next);
  }

  void setOffset(int id, double value) {
    if (!editable || !value.isFinite || value.abs() > 90) return;
    invalidOffsets.remove(id);
    servos[id].offset = double.parse(degrees(value));
    selectedServo = id;
    _changed();
  }

  void setMapping(int id, int pwm) {
    if (!editable || pwm < 1 || pwm > 4) return;
    final other = servos.indexWhere((s) => s.pwmIndex == pwm);
    if (other >= 0) servos[other].pwmIndex = servos[id].pwmIndex;
    servos[id].pwmIndex = pwm;
    _changed();
  }

  void _resetAngles() {
    _angleDirty = false;
    commonAngle = 0;
    for (final servo in servos) {
      servo.angle = servo.appliedAngle = 0;
    }
  }

  void setOffsetInput(int id, String text) {
    if (!editable) return;
    final value = double.tryParse(text);
    if (value == null || !value.isFinite || value.abs() > 90) {
      invalidOffsets.add(id);
      _changed();
    } else {
      invalidOffsets.remove(id);
      setOffset(id, value);
    }
  }

  Future<void> _keepaliveIfDue() async {
    if (manual && DateTime.now().difference(_heartbeat).inMilliseconds >= 300) {
      await _client!.command('servo manual keepalive');
      _heartbeat = DateTime.now();
    }
  }

  Future<void> _flushRam() async {
    if (!draftValid) return;
    final mapping = servos.map((s) => s.pwmIndex).toList();
    if (servos.any((s) => s.pwmIndex != s.appliedPwm)) {
      await _keepaliveIfDue();
      final applied = parseMapping(
        parseFields(
          await _client!.command('servo map set ${mapping.join(' ')}'),
        )['pwm_index'],
      );
      if (!listEquals(applied, mapping)) throw StateError('PWM 映射应答不一致');
      for (int i = 0; i < 4; i++) {
        servos[i].appliedPwm = applied[i];
      }
    }
    if (protocol >= 8) return;
    if (!draftValid ||
        !servos.any((s) => (s.offset - s.appliedOffset).abs() >= .0005)) {
      return;
    }
    // Snapshot after mapping ACK; don't overwrite a newer edit with an old ACK.
    final offsets = servos.map((s) => s.offset).toList();
    await _keepaliveIfDue();
    final applied = parseFourDegrees(
      parseFields(
        await _client!.command(
          'servo setall ${offsets.map(degrees).join(' ')}',
        ),
      )['offset_deg'],
    );
    if (!_sameDegrees(applied, offsets)) throw StateError('servo_offset 应答不一致');
    for (int i = 0; i < 4; i++) {
      servos[i].appliedOffset = applied[i];
    }
    if (protocol >= 7) {
      _installCurves(
        ServoCurves.parse(
          parseFields(await _client!.command('servo curve get')),
        ),
      );
    }
  }

  Future<void> moveCalibrationTarget(int id, int angle) async {
    if (protocol < 7 ||
        !canMove ||
        id < 0 ||
        id >= 4 ||
        ![-30, 0, 30].contains(angle)) {
      return;
    }
    await _action(() async {
      selectedServo = id;
      await _ensureManual();
      if (draftDirty) await _flushRam();
      for (final servo in servos) {
        servo.angle = servo.id == id ? angle.toDouble() : 0;
      }
      commonAngle = 0;
      _angleDirty = true;
      await _flushAngles();
      calibrationServo = id;
      calibrationAngle = angle;
      message = '位置 ${id + 1} 已指令到 $angle°；请对照治具，调节对应 PWM';
    });
  }

  Future<void> tuneCalibrationPoint(int id, int angle, int pwmUs) async {
    if (protocol < 7 ||
        !canWrite ||
        calibrationServo != id ||
        calibrationAngle != angle ||
        (angle == 0 && protocol < 8) ||
        pwmUs < 500 ||
        pwmUs > 2500) {
      return;
    }
    await _action(() async {
      await _keepaliveIfDue();
      final side = angle < 0
          ? 'neg'
          : angle > 0
          ? 'pos'
          : 'zero';
      final curves = ServoCurves.parse(
        parseFields(await _client!.command('servo curve set $id $side $pwmUs')),
      );
      if ((angle < 0
              ? curves.neg[id]
              : angle > 0
              ? curves.pos[id]
              : curves.zero?[id]) !=
          pwmUs) {
        throw StateError('舵机端点 PWM 应答不一致');
      }
      _installCurves(curves);
      message = '位置 ${id + 1} 的 $angle° PWM = $pwmUs μs，已写入 RAM；Flash 尚未保存';
    });
  }

  bool _sameDegrees(List<double> a, List<double> b) =>
      List.generate(4, (i) => (a[i] - b[i]).abs() < .0005).every((v) => v);

  Future<void> _flushAngles() async {
    await _keepaliveIfDue();
    final angle = servos.map((s) => s.commandAngle).toList();
    _angleDirty = false;
    final applied = parseFourDegrees(
      parseFields(
        await _client!.command(
          'servo angles set ${angle.map(degrees).join(' ')}',
        ),
      )['angle_deg'],
      limit: 30,
    );
    if (!_sameDegrees(applied, angle)) throw StateError('servo_angle 应答不一致');
    for (int i = 0; i < 4; i++) {
      servos[i].appliedAngle = applied[i];
    }
  }

  Future<void> saveFlash() async {
    if (!canSaveFlash) return;
    await _action(() async {
      // Include edits queued less than one timer period before the save click.
      if (draftDirty) {
        await _ensureManual();
        await _flushRam();
      }
      final expectedOffsets = servos.map((s) => s.offset).toList();
      final expectedMapping = servos.map((s) => s.pwmIndex).toList();
      final expectedCurves = _currentCurves();
      // Do not hold a manual lease across a potentially long Flash transaction.
      if (manual) await _stopManual();
      await _client!.command('servo save', flash: true);
      await _readSettings();
      servoCalibrationMode = 0;
      if (!flashMatches ||
          !_sameDegrees(savedOffsets!, expectedOffsets) ||
          !listEquals(savedMapping, expectedMapping) ||
          (protocol >= 7 &&
              (savedCurves == null ||
                  !_curvesEqual(savedCurves!, expectedCurves)))) {
        throw StateError('Flash 回读与请求设置不一致');
      }
      message = 'Flash 保存并回读验证成功 · 统一角已回中，RAM 控件仍可直接操作';
      log(message);
    });
  }

  Future<void> disconnect({
    bool sendStop = true,
    bool preserveMessage = false,
  }) async {
    if (_disconnecting) return;
    _disconnecting = true;
    _timer?.cancel();
    _timer = null;
    final client = _client;
    try {
      if (sendStop && client?.connected == true) {
        await _waitIdle();
        if (manual) await client!.command('servo manual stop');
        if (clientControl) await client!.command('servo control release');
      }
    } catch (e) {
      log('未收到回中应答：$e；固件心跳超时后回中');
    } finally {
      await client?.close();
      _client = null;
      await _jlink.stop();
      calibrationOpen = false;
      icmCalibration = adxlCalibration = {};
      savedCalibration = {};
      manual = connected = clientControl = false;
      servoCalibrationMode = 0;
      calibrationServo = null;
      _resetAngles();
      status = null;
      if (!preserveMessage) message = '已断开 · 离线预览';
      _disconnecting = false;
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(disconnect());
    super.dispose();
  }
}
