import 'dart:async';

import 'package:flutter/material.dart';

import '../controller.dart';
import '../models/six_face_pose.dart';

class CalibrationDialog extends StatelessWidget {
  const CalibrationDialog({super.key, required this.controller});
  final StudioController controller;

  static const faces = ['X+', 'X−', 'Y+', 'Y−', 'Z+', 'Z−'];
  static const commands = ['x+', 'x-', 'y+', 'y-', 'z+', 'z-'];

  String _icmState(String? value) => switch (value) {
    '0' => '未开始',
    '1' => '等待选择面',
    '2' => '正在采样',
    '3' => '等待写入',
    '4' => '正在写入 Flash',
    '5' => '已保存',
    '6' => '数据不合格，请重测对应面',
    '7' => '超时',
    '8' => '已取消',
    '9' => '请求被拒绝',
    '10' => 'Flash 错误',
    '11' => 'RAM 校准完成 · 等待你决定是否保存',
    _ => '读取中…',
  };

  String _adxlState(String? value) => switch (value) {
    '0' => '未开始',
    '1' => '正在采样',
    '2' => '等待写入',
    '3' => '正在写入 Flash',
    '4' => '已保存',
    '5' => '超时',
    '6' => 'Flash 错误',
    '7' => '已取消',
    '8' => '请求被拒绝',
    '9' => 'RAM 校准完成 · 等待你决定是否保存',
    _ => '读取中…',
  };

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final c = controller;
      final icm = c.icmCalibration, adxl = c.adxlCalibration;
      final ready = c.connected && c.protocol >= 5 && !c.operation;
      final mask = int.tryParse(icm['valid'] ?? '') ?? 0;
      final values = (icm['raw_lsb'] ?? '').split(',');
      final pose = SixFacePose.fromFields(icm);
      final canSampleFace =
          ready &&
          icm['status'] != '2' &&
          icm['status'] != '3' &&
          icm['status'] != '4';
      final icmReady = icm['status'] == '11';
      final adxlReady = adxl['status'] == '9';
      return AlertDialog(
        title: const Text('传感器校准 · J-Link RTT'),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '仅在此窗口打开且设备已连接时，客户端按需轮询状态；MCU 不主动推送采样数据。校准结果先留在 RAM，只有点击保存才写 Flash。',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 18),
                Text(
                  'ICM 六面 · ${_icmState(icm['status'])}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 5),
                Text(
                  '完成 ${icm['faces'] ?? '—'}/6 面 · 当前面 ${icm['active'] ?? '—'} · 样本 ${icm['samples'] ?? '—'}/${icm['target'] ?? '—'}',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  'ICM 当前机体 XYZ：${icm['live_mps2'] ?? '—'} m/s²',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 14),
                _SixFacePoseGuide(pose: pose),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth < 550 ? 2 : 3;
                    final width =
                        (constraints.maxWidth - (columns - 1) * 8) / columns;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(6, (i) {
                        final selected = pose?.closestFace == i;
                        final aligned = selected && pose!.aligned;
                        final done = (mask & (1 << i)) != 0;
                        final accent = aligned
                            ? const Color(0xff45dbc4)
                            : selected
                            ? const Color(0xffffc46c)
                            : const Color(0xff4c6575);
                        return SizedBox(
                          width: width,
                          child: OutlinedButton(
                            key: ValueKey('icm-face-$i'),
                            style: OutlinedButton.styleFrom(
                              alignment: Alignment.centerLeft,
                              backgroundColor: selected
                                  ? accent.withValues(alpha: .13)
                                  : const Color(0xff102430),
                              side: BorderSide(
                                color: selected
                                    ? accent
                                    : const Color(0xff304859),
                                width: selected ? 2 : 1,
                              ),
                              padding: const EdgeInsets.all(12),
                            ),
                            onPressed: canSampleFace
                                ? () => unawaited(
                                    c.calibrationCommand(
                                      'cal icm ${commands[i]}',
                                    ),
                                  )
                                : null,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      faces[i],
                                      style: TextStyle(
                                        color: selected ? accent : null,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Spacer(),
                                    Icon(
                                      done
                                          ? Icons.check_circle
                                          : selected
                                          ? Icons.my_location
                                          : Icons.circle_outlined,
                                      size: 17,
                                      color: done
                                          ? const Color(0xff45dbc4)
                                          : accent,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  selected
                                      ? (aligned ? '建议采样' : '最接近 · 继续摆正')
                                      : (done ? '已采集' : '待采集'),
                                  style: TextStyle(fontSize: 11, color: accent),
                                ),
                                Text(
                                  '记录 ${i < values.length ? values[i] : '—'} LSB',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xff8a9eac),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    );
                  },
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: ready
                          ? () =>
                                unawaited(c.calibrationCommand('cal icm reset'))
                          : null,
                      child: const Text('重置六面'),
                    ),
                    TextButton(
                      onPressed: ready
                          ? () => unawaited(
                              c.calibrationCommand('cal icm cancel'),
                            )
                          : null,
                      child: const Text('取消'),
                    ),
                    FilledButton.icon(
                      onPressed: ready && icmReady
                          ? () => unawaited(
                              c.calibrationCommand('cal icm save', flash: true),
                            )
                          : null,
                      icon: const Icon(Icons.save_outlined, size: 17),
                      label: const Text('确认保存 ICM 到 Flash'),
                    ),
                  ],
                ),
                const Divider(height: 30),
                Text(
                  'ADXL 相对 ICM offset · ${_adxlState(adxl['status'])}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 5),
                Text(
                  'ICM / ADXL 样本：${adxl['icm_samples'] ?? '—'} / ${adxl['adxl_samples'] ?? '—'} · 拒绝窗口：${adxl['rejected'] ?? '—'}',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  'ICM 三轴抖动峰峰值：${adxl['p2p'] ?? '—'} m/s²',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  '候选 offset：${adxl['offset'] ?? '—'} m/s²',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  '当前 ICM：${adxl['icm_live'] ?? '—'} m/s²',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  '当前 ADXL（未扣相对 offset）：${adxl['adxl_live'] ?? '—'} m/s²',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: ready
                          ? () => unawaited(
                              c.calibrationCommand('cal adxl start'),
                            )
                          : null,
                      child: const Text('开始 ADXL 采样'),
                    ),
                    TextButton(
                      onPressed: ready
                          ? () => unawaited(
                              c.calibrationCommand('cal adxl cancel'),
                            )
                          : null,
                      child: const Text('取消'),
                    ),
                    FilledButton.icon(
                      onPressed: ready && adxlReady && !icmReady
                          ? () => unawaited(
                              c.calibrationCommand(
                                'cal adxl save',
                                flash: true,
                              ),
                            )
                          : null,
                      icon: const Icon(Icons.save_outlined, size: 17),
                      label: const Text('确认保存 ADXL 到 Flash'),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                const Text(
                  '若本轮重新校准了 ICM，请先保存 ICM，再采样并保存 ADXL；保存 ICM 会使旧的 ADXL offset 失效。',
                  style: TextStyle(fontSize: 11, color: Colors.amber),
                ),
                const SizedBox(height: 18),
                _SavedCalibrationPanel(
                  saved: c.savedCalibration,
                  onRefresh: c.connected && !c.operation
                      ? () => unawaited(c.refreshSavedCalibration())
                      : null,
                ),
                if (c.message.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(c.message, style: const TextStyle(fontSize: 11)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      );
    },
  );
}

class _SavedCalibrationPanel extends StatelessWidget {
  const _SavedCalibrationPanel({required this.saved, required this.onRefresh});
  final Map<String, String> saved;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final flags = int.tryParse(saved['valid'] ?? '') ?? 0;
    final hasIcm = (flags & 1) != 0;
    final hasAdxl = (flags & 4) != 0;
    final icmValues = (saved['icm_lsb'] ?? '').split(',');
    final storedRange = saved['icm_range_g'];
    final currentRange = saved['current_range_g'];
    final rangeMatch = storedRange == currentRange;
    final unavailable = saved['unsupported'] == '1';
    final waiting = saved.isEmpty;
    return Container(
      key: const ValueKey('calibration-flash-panel'),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xff102431),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xff36566a)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.storage_outlined,
                size: 19,
                color: Color(0xff45dbc4),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Flash 已保存 · 已验证快照',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              TextButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('刷新'),
              ),
            ],
          ),
          const Text(
            '与上面的本轮采样 / RAM 候选值分开；未确认保存的结果不会出现在这里。',
            style: TextStyle(fontSize: 11, color: Color(0xff91a9b5)),
          ),
          const SizedBox(height: 12),
          if (waiting || unavailable)
            Text(
              unavailable ? '板上固件不支持读取校准 Flash 快照，请更新固件。' : '正在读取已保存配置…',
              style: const TextStyle(fontSize: 12, color: Color(0xffffc46c)),
            )
          else ...[
            Row(
              children: [
                const Text(
                  'ICM 六面',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 9),
                _savedTag(
                  hasIcm
                      ? (rangeMatch ? '已保存 · 量程匹配' : '已保存 · 量程不匹配')
                      : '未保存 · 默认参数',
                  hasIcm && rangeMatch,
                ),
              ],
            ),
            if (hasIcm) ...[
              const SizedBox(height: 7),
              Text(
                '存储量程 ±${storedRange ?? '—'}g · 当前量程 ±${currentRange ?? '—'}g',
                style: const TextStyle(fontSize: 11),
              ),
              const SizedBox(height: 5),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: List.generate(3, (axis) {
                  final plus = axis * 2;
                  final minus = plus + 1;
                  return _savedValueChip(
                    '${'XYZ'[axis]}+ ${plus < icmValues.length ? icmValues[plus] : '—'}  '
                    '${'XYZ'[axis]}− ${minus < icmValues.length ? icmValues[minus] : '—'} LSB',
                  );
                }),
              ),
              if (!rangeMatch)
                const Padding(
                  padding: EdgeInsets.only(top: 5),
                  child: Text(
                    '量程不匹配：这组 Flash 六面值不会在启动时应用。',
                    style: TextStyle(fontSize: 11, color: Color(0xffffc46c)),
                  ),
                ),
            ],
            const Divider(height: 22),
            Row(
              children: [
                const Text(
                  'ADXL 相对 offset',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 9),
                _savedTag(hasAdxl ? '已保存' : '未保存 · 默认 0', hasAdxl),
              ],
            ),
            if (hasAdxl) ...[
              const SizedBox(height: 7),
              Text(
                'Flash XYZ：${saved['adxl_offset'] ?? '—'} m/s²',
                style: const TextStyle(fontSize: 11),
              ),
            ],
            Text(
              '当前 RAM 应用 XYZ：${saved['applied_adxl'] ?? '—'} m/s²',
              style: const TextStyle(fontSize: 11, color: Color(0xff91a9b5)),
            ),
            if (hasAdxl && saved['basis_valid'] == '0')
              const Text(
                'ICM 基准无效，Flash 中的 ADXL offset 暂未应用。',
                style: TextStyle(fontSize: 11, color: Color(0xffffc46c)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _savedTag(String text, bool good) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: (good ? const Color(0xff45dbc4) : const Color(0xffffc46c))
          .withValues(alpha: .13),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10,
        color: good ? const Color(0xff45dbc4) : const Color(0xffffc46c),
      ),
    ),
  );

  Widget _savedValueChip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xff1b3643),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    ),
  );
}

class _SixFacePoseGuide extends StatelessWidget {
  const _SixFacePoseGuide({required this.pose});
  final SixFacePose? pose;

  @override
  Widget build(BuildContext context) {
    final p = pose;
    final accent = p == null
        ? const Color(0xff7b96a6)
        : p.aligned
        ? const Color(0xff45dbc4)
        : const Color(0xffffc46c);
    final label = p == null
        ? '等待 ICM 原始数据'
        : '${CalibrationDialog.faces[p.closestFace]} · ${(p.confidence * 100).round()}% 匹配';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xff193a47), Color(0xff0c1e2b)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: accent.withValues(alpha: .65)),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: .11), blurRadius: 20),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sensors, color: accent, size: 23),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '物理轴姿态识别',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'RAW XYZ · 仅高亮建议，不自动采样',
                      style: TextStyle(fontSize: 10, color: Color(0xff91a9b5)),
                    ),
                  ],
                ),
              ),
              Container(
                key: const ValueKey('icm-suggested-face'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  label,
                  style: TextStyle(fontWeight: FontWeight.bold, color: accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var axis = 0; axis < 3; axis++)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      'XYZ'[axis],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _AxisPoseBar(
                      value: p == null ? 0 : p.rawLsb[axis] / p.oneGLsb,
                      active: p != null && p.closestFace ~/ 2 == axis,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 9),
                  SizedBox(
                    width: 66,
                    child: Text(
                      p == null ? '—' : p.rawLsb[axis].toStringAsFixed(0),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontFeatures: [FontFeature.tabularFigures()],
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 5),
          Text(
            p == null
                ? '请连接新版固件并等待传感器样本；旧固件不提供物理轴实时原始读数。'
                : p.aligned
                ? '已接近 ${CalibrationDialog.faces[p.closestFace]} 朝上。放稳后点击下方高亮面确认采样。'
                : '当前最接近 ${CalibrationDialog.faces[p.closestFace]}，但还未对准；继续调整，确认静止后再采样。',
            key: const ValueKey('icm-pose-status'),
            style: TextStyle(fontSize: 11, color: accent),
          ),
        ],
      ),
    );
  }
}

class _AxisPoseBar extends StatelessWidget {
  const _AxisPoseBar({
    required this.value,
    required this.active,
    required this.color,
  });
  final double value;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 8,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final half = constraints.maxWidth / 2;
        final signed = value.clamp(-1.0, 1.0) * half;
        return Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xff263e49),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Positioned(
              left: signed >= 0 ? half : half + signed,
              width: signed.abs(),
              top: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: active ? color : const Color(0xff718c9d),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Positioned(
              left: half - 1,
              width: 2,
              top: 0,
              bottom: 0,
              child: const ColoredBox(color: Color(0xffb4cbd2)),
            ),
          ],
        );
      },
    ),
  );
}
