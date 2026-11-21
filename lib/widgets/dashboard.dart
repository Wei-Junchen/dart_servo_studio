import 'dart:async';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller.dart';
import '../models.dart';
import 'servo_scene.dart';
import 'calibration_dialog.dart';

const muted = Color(0xff8298a9);
const border = Color(0xff263b4b);
const surface = Color(0xff11212e);

class _OffsetKeyboardShortcuts extends StatefulWidget {
  const _OffsetKeyboardShortcuts({
    required this.controller,
    required this.child,
  });
  final StudioController controller;
  final Widget child;

  @override
  State<_OffsetKeyboardShortcuts> createState() =>
      _OffsetKeyboardShortcutsState();
}

class _OffsetKeyboardShortcutsState extends State<_OffsetKeyboardShortcuts>
    with WidgetsBindingObserver {
  Timer? _repeatDelay;
  Timer? _repeatTimer;
  LogicalKeyboardKey? _heldKey;
  int? _heldServo;
  int _heldDirection = 0;
  int _repeatTicks = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant _OffsetKeyboardShortcuts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) _stopHold();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _stopHold();
  }

  @override
  void dispose() {
    _stopHold();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _stopHold() {
    widget.controller.cancelQueuedNudges();
    _repeatDelay?.cancel();
    _repeatTimer?.cancel();
    _repeatDelay = null;
    _repeatTimer = null;
    _heldKey = null;
    _heldServo = null;
    _heldDirection = 0;
    _repeatTicks = 0;
  }

  bool get _isEditingText {
    final focused = FocusManager.instance.primaryFocus?.context;
    return focused != null &&
        (focused.widget is EditableText ||
            focused.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  bool get _canAdjust {
    final keyboard = HardwareKeyboard.instance;
    return mounted &&
        ModalRoute.of(context)?.isCurrent == true &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed &&
        !_isEditingText &&
        (widget.controller.editable || widget.controller.keyboardNudgeInFlight);
  }

  int? _direction(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      return -1;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      return 1;
    }
    return null;
  }

  void _repeat() {
    final servo = _heldServo;
    if (servo == null ||
        !_canAdjust ||
        widget.controller.selectedServo != servo) {
      _stopHold();
      return;
    }
    _repeatTicks++;
    // 单击始终 1 µs；长按缓慢起步，逐级加速后封顶 5 µs/拍。
    final steps = (1 + (_repeatTicks ~/ 12)).clamp(1, 5);
    widget.controller.nudgeActiveValue(servo, _heldDirection, steps: steps);
  }

  void _startHold(LogicalKeyboardKey key, int direction) {
    _stopHold();
    _heldKey = key;
    _heldServo = widget.controller.selectedServo;
    _heldDirection = direction;
    widget.controller.nudgeActiveValue(_heldServo!, direction);
    _repeatDelay = Timer(const Duration(milliseconds: 420), () {
      if (!_canAdjust || _heldKey != key) {
        _stopHold();
        return;
      }
      _repeat();
      _repeatTimer = Timer.periodic(
        const Duration(milliseconds: 55),
        (_) => _repeat(),
      );
    });
  }

  KeyEventResult _handleKey(KeyEvent event) {
    final key = event.logicalKey;
    final direction = _direction(key);
    if (event is KeyUpEvent) {
      if (key == _heldKey) _stopHold();
      return direction != null
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!_canAdjust) {
      _stopHold();
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      if (event is KeyDownEvent) {
        _stopHold();
        widget.controller.selectRelativeServo(
          key == LogicalKeyboardKey.arrowUp ? -1 : 1,
        );
      }
      return KeyEventResult.handled;
    }
    if (direction == null) return KeyEventResult.ignored;
    // Native key-repeat is ignored: our timer gives consistent speed on all OSes.
    if (event is KeyDownEvent && _heldKey != key) {
      _startHold(key, direction);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onFocusChange: (focused) {
      if (!focused) _stopHold();
    },
    onKeyEvent: (_, event) => _handleKey(event),
    child: widget.child,
  );
}

class Dashboard extends StatelessWidget {
  const Dashboard({super.key, required this.controller});
  final StudioController controller;

  Future<bool> confirm(
    BuildContext context,
    String title,
    String text,
    String button,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: Text(text, style: const TextStyle(height: 1.8)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(button),
            ),
          ],
        ),
      ) ??
      false;
  @override
  Widget build(BuildContext context) => _OffsetKeyboardShortcuts(
    controller: controller,
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final c = controller;
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Container(
                  height: 76,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: border)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xff45dbc4).withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(
                          Icons.navigation_rounded,
                          color: Color(0xff45dbc4),
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DART / SERVO STUDIO',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'CANARD 调试台    ·    J-LINK RTT',
                            style: TextStyle(
                              color: muted,
                              fontSize: 10,
                              letterSpacing: 1.8,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      _chip(
                        c.manual
                            ? 'TEST ACTIVE'
                            : c.connected
                            ? c.supported
                                  ? 'RAM LIVE'
                                  : 'READ ONLY'
                            : 'OFFLINE',
                        c.manual
                            ? const Color(0xfff8bb65)
                            : c.connected
                            ? const Color(0xff45dbc4)
                            : muted,
                      ),
                      const SizedBox(width: 18),
                      const Icon(Icons.shield_outlined, size: 16, color: muted),
                      const SizedBox(width: 7),
                      const Text(
                        '地面调试 · 禁止带载发射',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: math.max(constraints.maxWidth, 1100),
                        height: constraints.maxHeight,
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(width: 246, child: _ConnectionPanel(c)),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: _panel(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          child: ServoScene(
                                            servos: c.servos,
                                            selected: c.selectedServo,
                                            onSelect: c.selectServo,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    _panel(
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                const Icon(
                                                  Icons.tune,
                                                  size: 16,
                                                  color: muted,
                                                ),
                                                const SizedBox(width: 8),
                                                const Text(
                                                  '统一角测试 / RAM 实时调校',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const Spacer(),
                                                Text(
                                                  !c.connected
                                                      ? '离线预览'
                                                      : c.protocol >= 2 &&
                                                            c.protocol < 4
                                                      ? '协议 ${c.protocol}：测试角禁用'
                                                      : c.protocol < 2
                                                      ? '协议 1：只读'
                                                      : !c.draftValid
                                                      ? '输入无效'
                                                      : c.pending
                                                      ? '正在同步 RAM…'
                                                      : c.flashMatches
                                                      ? 'Flash 与设备一致'
                                                      : '仅 RAM / 尚未保存',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: c.flashMatches
                                                        ? const Color(
                                                            0xff45dbc4,
                                                          )
                                                        : const Color(
                                                            0xfff8bb65,
                                                          ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                const Text(
                                                  '统一舵面测试角',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: muted,
                                                  ),
                                                ),
                                                const Spacer(),
                                                Text(
                                                  c.servoCalibrationMode != 0
                                                      ? '单路 ${c.servoCalibrationMode}° 校准中'
                                                      : c.mixedAngles
                                                      ? '当前四路角度不一致'
                                                      : '${c.commonAngle >= 0 ? '+' : ''}${c.commonAngle.toStringAsFixed(1)}° × 4',
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    color: Color(0xff45dbc4),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            SizedBox(
                                              height: 30,
                                              child: Slider(
                                                key: const ValueKey(
                                                  'common-angle-slider',
                                                ),
                                                value: c.commonAngle,
                                                min: -30,
                                                max: 30,
                                                divisions: 120,
                                                label:
                                                    '${c.commonAngle.toStringAsFixed(1)}°（四路相同）',
                                                onChanged:
                                                    c.servoCalibrationMode ==
                                                            0 &&
                                                        c.editable &&
                                                        (!c.connected ||
                                                            c.canMove)
                                                    ? c.setCommonAngle
                                                    : null,
                                              ),
                                            ),
                                            Row(
                                              children: [
                                                const Text(
                                                  '−30°',
                                                  style: TextStyle(
                                                    color: muted,
                                                    fontSize: 9,
                                                  ),
                                                ),
                                                const Spacer(),
                                                Text(
                                                  c.protocol >= 8
                                                      ? '正测试角提高 PWM · 三点 PWM 独立校准 · 不保存测试角'
                                                      : '正测试角与正 offset 反向 · 不保存测试角',
                                                  style: const TextStyle(
                                                    color: muted,
                                                    fontSize: 9,
                                                  ),
                                                ),
                                                const Spacer(),
                                                Text(
                                                  '+30°',
                                                  style: TextStyle(
                                                    color: muted,
                                                    fontSize: 9,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: [
                                                FilledButton.icon(
                                                  key: const ValueKey(
                                                    'common-angle-neutral',
                                                  ),
                                                  onPressed: c.editable
                                                      ? c.neutral
                                                      : null,
                                                  icon: const Icon(
                                                    Icons.center_focus_weak,
                                                    size: 16,
                                                  ),
                                                  label: const Text('统一角归零'),
                                                ),
                                                OutlinedButton.icon(
                                                  onPressed:
                                                      c.manual && !c.operation
                                                      ? c.disarm
                                                      : null,
                                                  icon: const Icon(
                                                    Icons.stop_circle_outlined,
                                                    size: 16,
                                                  ),
                                                  label: const Text('停止测试'),
                                                ),
                                                OutlinedButton.icon(
                                                  onPressed: c.canSaveFlash
                                                      ? () async {
                                                          if (await confirm(
                                                            context,
                                                            '保存到 Flash',
                                                            '保存四路 -30/0/+30° PWM 校准值和真实 PWM 映射，保留传感器校准参数。\n未完成的 RAM 修改会先同步，测试角回到 0°，再写入和回读校验。servo_angle 不会保存。',
                                                            '保存 Flash',
                                                          )) {
                                                            await c.saveFlash();
                                                          }
                                                        }
                                                      : null,
                                                  icon: const Icon(
                                                    Icons.save_outlined,
                                                    size: 16,
                                                  ),
                                                  label: const Text('保存 Flash'),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              c.connected &&
                                                      c.protocol >= 2 &&
                                                      c.protocol < 4
                                                  ? '旧协议 ${c.protocol}：请升级协议 8 后使用 µs 三点校准。'
                                                  : c.connected &&
                                                        c.protocol < 2
                                                  ? '协议 1 只读：请升级协议 8 后进行舵机调试。'
                                                  : c.protocol >= 8
                                                  ? '协议 8：三点均使用 PWM µs，短按 1 µs，长按逐级加速。'
                                                  : '协议 4：正测试角增大 PWM 位置，正 offset 减小；飞控输出不变。',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: muted,
                                                height: 1.7,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      height: constraints.maxHeight < 750
                                          ? 95
                                          : 146,
                                      child: _panel(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    14,
                                                    10,
                                                    10,
                                                    5,
                                                  ),
                                              child: Row(
                                                children: [
                                                  const Text(
                                                    'RTT CONSOLE',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: muted,
                                                      letterSpacing: 1.7,
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  Text(
                                                    c.address == null
                                                        ? 'CH 1'
                                                        : 'CH 1 · 0x${c.address!.toRadixString(16)}',
                                                    style: const TextStyle(
                                                      fontFamily: 'monospace',
                                                      fontSize: 10,
                                                      color: muted,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Expanded(
                                              child: c.logs.isEmpty
                                                  ? const Padding(
                                                      padding: EdgeInsets.all(
                                                        14,
                                                      ),
                                                      child: Text(
                                                        '等待连接。启动时不会连接 J-Link，也不会发送舵机指令。',
                                                        style: TextStyle(
                                                          color: muted,
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                    )
                                                  : ListView.builder(
                                                      reverse: true,
                                                      padding:
                                                          const EdgeInsets.fromLTRB(
                                                            14,
                                                            0,
                                                            14,
                                                            9,
                                                          ),
                                                      itemCount: c.logs.length,
                                                      itemBuilder:
                                                          (
                                                            context,
                                                            i,
                                                          ) => Padding(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  vertical: 2,
                                                                ),
                                                            child: Text(
                                                              c.logs[c
                                                                      .logs
                                                                      .length -
                                                                  1 -
                                                                  i],
                                                              style: const TextStyle(
                                                                color: Color(
                                                                  0xffa0b9c9,
                                                                ),
                                                                fontFamily:
                                                                    'monospace',
                                                                fontSize: 10,
                                                                height: 1.45,
                                                              ),
                                                            ),
                                                          ),
                                                    ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              SizedBox(
                                width: 326,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        const Text(
                                          'Canard 位置',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const Spacer(),
                                        const Text(
                                          'POSITION → PWM',
                                          style: TextStyle(
                                            color: muted,
                                            fontSize: 9,
                                            letterSpacing: 1.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    const Text(
                                      '↑/↓ 选位置 · ←/→ 或 -/= 微调 · 长按加速',
                                      style: TextStyle(
                                        color: muted,
                                        fontSize: 10,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'PWM 校准模式',
                                      style: TextStyle(
                                        color: muted,
                                        fontSize: 11,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Wrap(
                                      spacing: 7,
                                      runSpacing: 4,
                                      children: [
                                        for (final angle in [-30, 0, 30])
                                          ChoiceChip(
                                            key: ValueKey(
                                              'servo-cal-mode-$angle',
                                            ),
                                            label: Text('$angle°'),
                                            selected:
                                                c.servoCalibrationMode == angle,
                                            onSelected: angle == 0
                                                ? (c.editable
                                                      ? (_) => c
                                                            .setServoCalibrationMode(
                                                              angle,
                                                            )
                                                      : null)
                                                : (c.protocol >= 7 && c.canMove
                                                      ? (_) => c
                                                            .setServoCalibrationMode(
                                                              angle,
                                                            )
                                                      : null),
                                          ),
                                      ],
                                    ),
                                    if (c.servoCalibrationMode != 0) ...[
                                      const SizedBox(height: 4),
                                      TextButton.icon(
                                        key: const ValueKey(
                                          'servo-cal-move-selected',
                                        ),
                                        onPressed: c.canMove
                                            ? () => c.moveCalibrationTarget(
                                                c.selectedServo,
                                                c.servoCalibrationMode,
                                              )
                                            : null,
                                        icon: const Icon(
                                          Icons.my_location,
                                          size: 14,
                                        ),
                                        label: Text(
                                          '移动位置 ${c.selectedServo + 1} 到 ${c.servoCalibrationMode}°',
                                        ),
                                      ),
                                      const Text(
                                        '仅选中舵机运动；端点只写 RAM，保存 Flash 需手动确认。',
                                        style: TextStyle(
                                          color: muted,
                                          fontSize: 9,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 6),
                                    Expanded(
                                      child: ListView.separated(
                                        itemCount: 4,
                                        separatorBuilder: (_, _) =>
                                            const SizedBox(height: 10),
                                        itemBuilder: (context, i) => _ServoCard(
                                          key: ValueKey(i),
                                          controller: c,
                                          id: i,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton(
                                            key: const ValueKey(
                                              'clear-all-offsets',
                                            ),
                                            onPressed:
                                                c.editable &&
                                                    c.servoCalibrationMode == 0
                                                ? () {
                                                    FocusScope.of(context)
                                                        .unfocus();
                                                    c.clearAllOffsets();
                                                  }
                                                : null,
                                            child: Text(
                                              c.protocol >= 8
                                                  ? '中点全回 1500 µs'
                                                  : 'offset 全归零',
                                              style: TextStyle(fontSize: 10),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: OutlinedButton(
                                            key: const ValueKey(
                                              'load-flash-to-ram',
                                            ),
                                            onPressed:
                                                c.canWrite &&
                                                    c.servoCalibrationMode == 0
                                                ? () async {
                                                    FocusScope.of(context)
                                                        .unfocus();
                                                    await c.loadFlashToRam();
                                                  }
                                                : null,
                                            child: const Text(
                                              '从 Flash 载入',
                                              style: TextStyle(fontSize: 10),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: const BoxDecoration(
                    color: Color(0xff0e1d29),
                    border: Border(top: BorderSide(color: border)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        c.connecting
                            ? Icons.sync
                            : c.connected
                            ? Icons.circle
                            : Icons.circle_outlined,
                        size: 8,
                        color: c.connected ? const Color(0xff45dbc4) : muted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Tooltip(
                          message: c.message,
                          child: Text(
                            c.message,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: muted),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'PROFILE ${c.status?.profile ?? '—'}    /    ${c.status?.state ?? 'NO DEVICE'}    /    RPC ${c.protocol == 0 ? '—' : c.protocol}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Widget _chip(String text, Color color) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  decoration: BoxDecoration(
    color: color.withValues(alpha: .10),
    border: Border.all(color: color.withValues(alpha: .35)),
    borderRadius: BorderRadius.circular(6),
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 7),
      Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  ),
);
Widget _panel({required Widget child}) => Container(
  decoration: BoxDecoration(
    color: surface,
    border: Border.all(color: border),
    borderRadius: BorderRadius.circular(12),
  ),
  child: child,
);

class _ConnectionPanel extends StatelessWidget {
  const _ConnectionPanel(this.c);
  final StudioController c;

  Widget _field(
    String label,
    String initial,
    ValueChanged<String> change, {
    String? help,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      key: ValueKey('$label:$initial'),
      initialValue: initial,
      enabled: !c.connected && !c.connecting,
      onChanged: change,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        labelText: label,
        helperText: help,
        helperStyle: const TextStyle(fontSize: 9, color: muted),
        helperMaxLines: 2,
      ),
    ),
  );

  Future<void> _showSettings(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, redraw) => AlertDialog(
          title: const Text('连接设置'),
          content: SizedBox(
            width: 480,
            height: 490,
            child: ListView(
              children: [
                SwitchListTile(
                  title: const Text('由软件启动 J-Link Commander'),
                  subtitle: const Text('关闭后才使用已有 RTT TCP 服务'),
                  contentPadding: EdgeInsets.zero,
                  value: c.settings.launchCommander,
                  onChanged: c.connected || c.connecting
                      ? null
                      : (v) {
                          c.settings.launchCommander = v;
                          redraw(() {});
                          c.settingsChanged();
                        },
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _field(
                        'Firmware ELF',
                        c.settings.elf,
                        (v) => c.settings.elf = v,
                        help: '只解析 RTT 地址，不下载；须匹配板上固件',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: OutlinedButton(
                        onPressed: c.connected || c.connecting
                            ? null
                            : () async {
                                const typeGroup = XTypeGroup(
                                  label: 'ELF firmware',
                                  extensions: ['elf'],
                                );
                                final file = await openFile(
                                  acceptedTypeGroups: [typeGroup],
                                );
                                if (file != null) {
                                  c.settings.elf = file.path;
                                  redraw(() {});
                                  c.settingsChanged();
                                }
                              },
                        child: const Text('选择…'),
                      ),
                    ),
                  ],
                ),
                _field(
                  'RTT 地址（可覆盖 ELF）',
                  c.settings.rttAddress,
                  (v) => c.settings.rttAddress = v,
                  help: '留空由 ELF 解析；例如 0x20004404',
                ),
                if (c.settings.launchCommander) ...[
                  _field(
                    'Commander 程序',
                    c.settings.commander,
                    (v) => c.settings.commander = v,
                  ),
                  _field(
                    'MCU / Device',
                    c.settings.device,
                    (v) => c.settings.device = v,
                  ),
                  _field(
                    'SWD speed / kHz',
                    '${c.settings.speed}',
                    (v) => c.settings.speed = int.tryParse(v) ?? 0,
                  ),
                  _field(
                    'Probe S/N（可选）',
                    c.settings.serial,
                    (v) => c.settings.serial = v,
                  ),
                ],
                const Divider(),
                _field(
                  'RTT TCP Host',
                  c.settings.host,
                  (v) => c.settings.host = v,
                  help: 'J-Link 直连时通常保持 127.0.0.1',
                ),
                _field(
                  'RTT TCP Port',
                  '${c.settings.port}',
                  (v) => c.settings.port = int.tryParse(v) ?? 0,
                  help: 'J-Link 直连时无需手动修改',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await c.savePreferences();
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _panel(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.usb, size: 18, color: Color(0xff45dbc4)),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  '连接设备',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                key: const ValueKey('connection-settings-button'),
                tooltip: '高级连接设置',
                onPressed: () => _showSettings(context),
                icon: const Icon(Icons.settings_outlined, size: 18),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            c.settings.launchCommander
                ? 'J-Link 直连 · 自动读取设备设置'
                : '已有 RTT 服务 · 自动读取设备设置',
            style: const TextStyle(color: muted, fontSize: 10),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const ValueKey('connect-button'),
            onPressed: c.connecting
                ? null
                : c.connected
                ? c.disconnect
                : c.connect,
            icon: Icon(c.connected ? Icons.link_off : Icons.link, size: 17),
            label: Text(
              c.connecting
                  ? '正在连接…'
                  : c.connected
                  ? '断开连接'
                  : '连接板子',
            ),
          ),
          const SizedBox(height: 9),
          if (c.connected)
            OutlinedButton.icon(
              onPressed: !c.operation && !c.pending && c.draftValid
                  ? c.refresh
                  : null,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重新读取当前设置'),
            ),
          if (c.connected) ...[
            const SizedBox(height: 9),
            OutlinedButton.icon(
              key: const ValueKey('calibration-button'),
              onPressed: c.protocol >= 5 && !c.pending && !c.operation
                  ? () {
                      c.openCalibration();
                      showDialog<void>(
                        context: context,
                        builder: (_) => CalibrationDialog(controller: c),
                      ).whenComplete(c.closeCalibration);
                    }
                  : null,
              icon: const Icon(Icons.sensors, size: 16),
              label: const Text('ICM / ADXL 校准'),
            ),
          ],
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0xfff8bb65).withValues(alpha: .06),
              border: Border.all(
                color: const Color(0xfff8bb65).withValues(alpha: .18),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '先断开 Ozone 对同一探针的连接。\n连接只读取；第一次修改自动进入测试并写入 RAM。',
              style: TextStyle(
                color: Color(0xffcbb18a),
                fontSize: 10,
                height: 1.9,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '仅在设备型号、RTT 地址或 Commander 路径变化时，打开右上角设置。',
            style: TextStyle(color: muted, fontSize: 10, height: 1.6),
          ),
        ],
      ),
    ),
  );
}

class _ServoCard extends StatefulWidget {
  const _ServoCard({super.key, required this.controller, required this.id});
  final StudioController controller;
  final int id;
  @override
  State<_ServoCard> createState() => _ServoCardState();
}

class _ServoCardState extends State<_ServoCard> {
  final offsetController = TextEditingController();
  final offsetFocus = FocusNode();
  int? pwmDraft;
  int lastMode = 0;

  Future<void> commitPwm(int pwmUs) async {
    await widget.controller.tuneCalibrationPoint(
      widget.id,
      widget.controller.servoCalibrationMode,
      pwmUs,
    );
    if (mounted) setState(() => pwmDraft = null);
  }

  @override
  void dispose() {
    offsetController.dispose();
    offsetFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller,
        s = c.servos[widget.id],
        color = Color(servoColors[s.id]);
    final enabled = c.editable;
    final mode = c.servoCalibrationMode;
    if (lastMode != mode) {
      pwmDraft = null;
      lastMode = mode;
    }
    final zeroMode = mode == 0 && c.protocol >= 8;
    final legacyOffsetMode = mode == 0 && !zeroMode;
    final center = s.useZeroUs
        ? s.zeroUs.toDouble()
        : 1500 - s.offset * 2000 / 180;
    final positive = mode > 0;
    final endpoint = zeroMode
        ? s.zeroUs
        : positive
        ? (s.pos30Valid ? s.pos30Us : (center + 2000 / 6).round())
        : (s.neg30Valid ? s.neg30Us : (center - 2000 / 6).round());
    final pwmMin = zeroMode
        ? 500
        : positive
        ? center.floor() + 1
        : 500;
    final pwmMax = zeroMode
        ? 2500
        : positive
        ? 2500
        : center.ceil() - 1;
    final rangeValid = pwmMin < pwmMax;
    final pwmValue = rangeValid
        ? (pwmDraft ?? endpoint).clamp(pwmMin, pwmMax)
        : 1500;
    final canTune = rangeValid && c.canTuneCalibrationPoint(s.id);
    final savedBit = 1 << (s.id + (positive ? 4 : 0));
    final savedZero = c.savedCurves?.zero;
    final savedEndpoint = zeroMode
        ? (savedZero == null ? null : savedZero[s.id])
        : c.savedCurves != null && c.savedCurves!.mask & savedBit != 0
        ? (positive ? c.savedCurves!.pos[s.id] : c.savedCurves!.neg[s.id])
        : null;
    if (legacyOffsetMode &&
        !offsetFocus.hasFocus &&
        !c.invalidOffsets.contains(s.id)) {
      offsetController.text = s.offset.toStringAsFixed(3);
    }
    return GestureDetector(
      onTap: () => c.selectServo(s.id),
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: c.selectedServo == s.id
                ? color.withValues(alpha: .6)
                : border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 27,
                  height: 27,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    '${s.position}',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  '位置 ${s.position} · ${canardPositionNames[s.id]}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                Text(
                  legacyOffsetMode
                      ? '${s.offset >= 0 ? '+' : ''}${s.offset.toStringAsFixed(1)}°'
                      : '$pwmValue μs',
                  style: TextStyle(
                    color: color,
                    fontSize: legacyOffsetMode ? 22 : 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            if (legacyOffsetMode) ...[
              SizedBox(
                height: 36,
                child: Row(
                  children: [
                    IconButton(
                      key: ValueKey('offset-minus-${s.id}'),
                      tooltip: 'offset 减小 0.1°',
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      padding: EdgeInsets.zero,
                      iconSize: 17,
                      onPressed: enabled && s.offset > -90
                          ? () {
                              offsetFocus.unfocus();
                              c.nudgeOffset(s.id, -1);
                            }
                          : null,
                      icon: const Icon(Icons.remove),
                    ),
                    Expanded(
                      child: Slider(
                        key: ValueKey('offset-slider-${s.id}'),
                        value: s.offset.clamp(-90, 90),
                        min: -90,
                        max: 90,
                        divisions: 1800,
                        activeColor: color,
                        label: 'offset ${s.offset.toStringAsFixed(1)}°',
                        onChanged: enabled
                            ? (v) {
                                offsetFocus.unfocus();
                                c.setOffset(s.id, v);
                              }
                            : null,
                      ),
                    ),
                    IconButton(
                      key: ValueKey('offset-plus-${s.id}'),
                      tooltip: 'offset 增大 0.1°',
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      padding: EdgeInsets.zero,
                      iconSize: 17,
                      onPressed: enabled && s.offset < 90
                          ? () {
                              offsetFocus.unfocus();
                              c.nudgeOffset(s.id, 1);
                            }
                          : null,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  const Text(
                    '−90°',
                    style: TextStyle(color: muted, fontSize: 9),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: enabled ? () => c.setOffset(s.id, 0) : null,
                    child: const Text(
                      'servo_offset · 点此设为 0',
                      style: TextStyle(color: muted, fontSize: 10),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    '+90°',
                    style: TextStyle(color: muted, fontSize: 9),
                  ),
                ],
              ),
              Text(
                c.savedOffsets == null
                    ? 'Flash offset：未保存'
                    : 'Flash offset：${c.savedOffsets![s.id].toStringAsFixed(3)}°',
                style: const TextStyle(color: muted, fontSize: 9),
              ),
            ] else ...[
              SizedBox(
                height: 36,
                child: Row(
                  children: [
                    IconButton(
                      key: ValueKey('curve-minus-${s.id}'),
                      tooltip: '$mode° PWM 减少 1 μs',
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      padding: EdgeInsets.zero,
                      iconSize: 17,
                      onPressed: canTune && pwmValue > pwmMin
                          ? () => commitPwm(pwmValue - 1)
                          : null,
                      icon: const Icon(Icons.remove),
                    ),
                    Expanded(
                      child: Slider(
                        key: ValueKey('curve-slider-${s.id}'),
                        value: pwmValue.toDouble(),
                        min: rangeValid ? pwmMin.toDouble() : 500,
                        max: rangeValid ? pwmMax.toDouble() : 2500,
                        activeColor: color,
                        label: '$mode° · $pwmValue μs',
                        onChanged: canTune
                            ? (v) => setState(() => pwmDraft = v.round())
                            : null,
                        onChangeEnd: canTune
                            ? (v) => commitPwm(v.round())
                            : null,
                      ),
                    ),
                    IconButton(
                      key: ValueKey('curve-plus-${s.id}'),
                      tooltip: '$mode° PWM 增加 1 μs',
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      padding: EdgeInsets.zero,
                      iconSize: 17,
                      onPressed: canTune && pwmValue < pwmMax
                          ? () => commitPwm(pwmValue + 1)
                          : null,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
              Text(
                !rangeValid
                    ? '中点接近 PWM 边界，请先切回 0° 调整 µs'
                    : canTune
                    ? '$mode° 端点 · RAM 实时调整'
                    : '先点选此位置，将舵机移动到 $mode° 后调整',
                style: const TextStyle(color: muted, fontSize: 9),
              ),
            ],
            const SizedBox(height: 9),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    isExpanded: true,
                    iconSize: 18,
                    key: ValueKey('pwm-${s.id}-${s.pwmIndex}'),
                    initialValue: s.pwmIndex,
                    decoration: const InputDecoration(labelText: 'PWM 输出通道'),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xffdbe9f2),
                    ),
                    items: [
                      for (int i = 1; i <= 4; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(
                            '$i  /  ${pwmChannels[i]!.split(' · ').last}',
                          ),
                        ),
                    ],
                    onChanged: enabled && mode == 0
                        ? (v) => c.setMapping(s.id, v!)
                        : null,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: legacyOffsetMode
                      ? TextField(
                          key: ValueKey('offset-input-${s.id}'),
                          controller: offsetController,
                          focusNode: offsetFocus,
                          enabled: enabled,
                          style: const TextStyle(fontSize: 11),
                          decoration: InputDecoration(
                            labelText: 'servo_offset / °',
                            errorText: c.invalidOffsets.contains(s.id)
                                ? '范围 −90..90'
                                : null,
                          ),
                          onChanged: (v) => c.setOffsetInput(s.id, v),
                          onSubmitted: (v) {
                            offsetFocus.unfocus();
                            setState(() {});
                          },
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '−30/0/+30 PWM 校准',
                              style: TextStyle(color: color, fontSize: 10),
                            ),
                            Text(
                              c.savedCurves == null
                                  ? 'Flash：未保存'
                                  : savedEndpoint == null
                                  ? 'Flash：默认斜率'
                                  : 'Flash：$savedEndpoint μs',
                              style: const TextStyle(
                                color: muted,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              legacyOffsetMode
                  ? '测试角 ${s.angle.toStringAsFixed(1)}° · PWM 相对中位 ${s.pwmPositionDelta.toStringAsFixed(1)}°${s.directionClamped ? ' · 已限幅' : ''}'
                  : zeroMode
                  ? '目标 0° · 中点 PWM ${s.zeroUs} μs · 每次微调 1 μs'
                  : '目标 $mode° · 0° PWM ${center.round()} μs · ${(positive ? s.pos30Valid : s.neg30Valid) ? '已校准' : '默认斜率'}',
              style: TextStyle(
                color: s.directionClamped ? const Color(0xfff8bb65) : muted,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              c.connected && c.supported
                  ? '设备 RAM：中点 ${s.zeroUs} µs · PWM ${s.appliedPwm} · 当前 ${s.pulse.toStringAsFixed(0)} µs'
                  : '离线预览 ${s.previewPulse.toStringAsFixed(0)} µs · 不发送指令',
              style: const TextStyle(color: muted, fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }
}
