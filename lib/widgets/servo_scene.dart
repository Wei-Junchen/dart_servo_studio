import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../dart_geometry.dart';
import '../models.dart';

/// Approximate structural model from dart.jpg, not a dimensional/aerodynamic model.
/// Model +X is nose -> tail; rear-view screen right is +Y and screen up is +Z.
/// Rear-view quadrants are fixed: 1 upper-left, 2 upper-right, 3 lower-right, 4 lower-left.
// RTT v4 +angle raises PWM position, opposite to RTT v3. Reverse only the
// visualization to keep its observed motion aligned; offset is not rendered.
double canardPreviewAngle(ServoModel servo) => -servo.commandAngle;

class ServoScene extends StatefulWidget {
  const ServoScene({
    super.key,
    required this.servos,
    required this.selected,
    required this.onSelect,
  });
  final List<ServoModel> servos;
  final int selected;
  final ValueChanged<int> onSelect;
  @override
  State<ServoScene> createState() => _ServoSceneState();
}

class _ServoSceneState extends State<ServoScene> {
  double yaw = -.30, pitch = .52, zoom = 1;
  final labels = <int, Offset>{};
  void reset() => setState(() {
    yaw = -.30;
    pitch = .52;
    zoom = 1;
  });
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: GestureDetector(
          onPanUpdate: (e) => setState(() {
            yaw += e.delta.dx * .008;
            pitch = (pitch + e.delta.dy * .005).clamp(-1.15, 1.15);
          }),
          onTapUp: (e) {
            for (final item in labels.entries) {
              if ((item.value - e.localPosition).distance < 40) {
                widget.onSelect(item.key);
                break;
              }
            }
          },
          child: Listener(
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) {
                setState(
                  () =>
                      zoom = (zoom - e.scrollDelta.dy * .001).clamp(.55, 1.65),
                );
              }
            },
            child: CustomPaint(
              painter: _DartPainter(
                widget.servos,
                widget.selected,
                yaw,
                pitch,
                zoom,
                labels,
              ),
            ),
          ),
        ),
      ),
      Positioned(
        top: 18,
        left: 20,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '实物布局 · Canard',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 5),
            const Text(
              '前缘转轴 · 连续透明壳体 · 固定碳纤维尾翼',
              style: TextStyle(color: Color(0xff8298a9), fontSize: 11),
            ),
            const SizedBox(height: 4),
            const Text(
              '拖拽旋转 / 滚轮缩放 · 编号不会随视角变化',
              style: TextStyle(color: Color(0xff667f90), fontSize: 10),
            ),
          ],
        ),
      ),
      Positioned(
        top: 14,
        right: 12,
        child: Row(
          children: [
            IconButton(
              tooltip: '缩小',
              onPressed: () =>
                  setState(() => zoom = (zoom - .12).clamp(.55, 1.65)),
              icon: const Icon(Icons.remove, size: 17),
            ),
            IconButton(
              tooltip: '放大',
              onPressed: () =>
                  setState(() => zoom = (zoom + .12).clamp(.55, 1.65)),
              icon: const Icon(Icons.add, size: 17),
            ),
            TextButton(
              key: const ValueKey('camera-rear-view'),
              onPressed: () => setState(() {
                yaw = -math.pi / 2;
                pitch = 0;
                zoom = 1;
              }),
              child: const Text('后视', style: TextStyle(fontSize: 11)),
            ),
            TextButton(
              key: const ValueKey('camera-flat-view'),
              onPressed: reset,
              child: const Text('平放', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ),
      Positioned(
        bottom: 18,
        left: 18,
        child: _RearView(
          servos: widget.servos,
          selected: widget.selected,
          onSelect: widget.onSelect,
        ),
      ),
      Positioned(
        bottom: 20,
        right: 20,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '位置 ${widget.selected + 1} · PWM ${widget.servos[widget.selected].pwmIndex}',
              style: TextStyle(
                color: Color(servoColors[widget.selected]),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.servos.every((s) => (s.angle - widget.servos.first.angle).abs() < .0005) ? '统一测试角' : '单舵机校准角'} ${widget.servos[widget.selected].angle.toStringAsFixed(1)}°',
              style: TextStyle(
                color: Color(servoColors[widget.selected]),
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '正测试角使 PWM 位置增大；正 offset 使其减小',
              style: const TextStyle(color: Color(0xff748796), fontSize: 9),
            ),
            const Text(
              '舵面只按统一测试角示意，不渲染 offset',
              style: TextStyle(color: Color(0xff748796), fontSize: 9),
            ),
          ],
        ),
      ),
    ],
  );
}

class _RearView extends StatelessWidget {
  const _RearView({
    required this.servos,
    required this.selected,
    required this.onSelect,
  });
  final List<ServoModel> servos;
  final int selected;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) => Container(
    width: 174,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xff0b1925).withValues(alpha: .92),
      border: Border.all(color: const Color(0xff2a4253)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      children: [
        const Text(
          '编号基准：镖尾 → 镖头',
          style: TextStyle(color: Color(0xffb6c9d6), fontSize: 9),
        ),
        const SizedBox(height: 3),
        const Text(
          '后视 · 顺时针 1 → 2 → 3 → 4',
          style: TextStyle(color: Color(0xff6d8798), fontSize: 8),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [button(0), button(1)],
        ),
        const SizedBox(height: 4),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '镖轴',
              style: TextStyle(color: Color(0xff536d7e), fontSize: 10),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [button(3), button(2)],
        ),
      ],
    ),
  );
  Widget button(int index) => InkWell(
    key: ValueKey('rear-position-${index + 1}'),
    onTap: () => onSelect(index),
    borderRadius: BorderRadius.circular(6),
    child: Container(
      width: 67,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Color(servoColors[index])
            .withValues(alpha: selected == index ? .14 : .04),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Color(servoColors[index])
              .withValues(alpha: selected == index ? .65 : .2),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${index + 1}',
            style: TextStyle(
              color: Color(servoColors[index]),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'P${servos[index].pwmIndex}',
            style: const TextStyle(fontSize: 9, color: Color(0xff8298a9)),
          ),
        ],
      ),
    ),
  );
}

typedef _V = ModelPoint;

enum _Texture { plain, carbon, printed }

class _Face {
  _Face(
    this.points,
    this.color, {
    this.edge = const Color(0xff4b6574),
    this.texture = _Texture.plain,
  });
  final List<_V> points;
  final Color color, edge;
  final _Texture texture;
}

class _DartPainter extends CustomPainter {
  _DartPainter(
    this.servos,
    this.selected,
    this.yaw,
    this.pitch,
    this.zoom,
    this.labels,
  );
  final List<ServoModel> servos;
  final int selected;
  final double yaw, pitch, zoom;
  final Map<int, Offset> labels;
  late Offset center;
  late double scale;
  final faces = <_Face>[];
  _V rotate(_V v) {
    final x = v.x * math.cos(yaw) - v.y * math.sin(yaw),
        y = v.x * math.sin(yaw) + v.y * math.cos(yaw);
    return _V(
      x,
      y * math.cos(pitch) - v.z * math.sin(pitch),
      v.z * math.cos(pitch) + y * math.sin(pitch),
    );
  }

  Offset project(_V v) {
    final p = rotate(v), perspective = 7 / (7 + p.y);
    return center +
        Offset(p.x * scale * perspective, -p.z * scale * perspective);
  }

  void fitCamera(Size size) {
    // Fit the whole airframe while orbiting. Use the union of allowed poses so
    // changing a servo angle never shifts/scales the camera or its fixed shaft.
    final points = <_V>[
      ...DartGeometry.shellSections.expand((s) => s),
      ...DartGeometry.section(-2.06, .305, .315, .10),
      ...DartGeometry.section(2.14, .29, .27, .08),
      for (int id = 0; id < 4; id++) ...[
        for (final p in DartGeometry.tailOutline) radial(id, p.$1, p.$2, 0),
        radial(id, DartGeometry.hingeX, 1.35, 0),
        for (final angle in [-30.0, 0.0, 30.0])
          for (final p in DartGeometry.canardOutline)
            DartGeometry.canard(id, p.$1, p.$2, angle),
      ],
    ];
    final unit = points.map((v) {
      final p = rotate(v), perspective = 7 / (7 + p.y);
      return Offset(p.x * perspective, -p.z * perspective);
    }).toList();
    final left = unit.map((p) => p.dx).reduce(math.min),
        right = unit.map((p) => p.dx).reduce(math.max),
        top = unit.map((p) => p.dy).reduce(math.min),
        bottom = unit.map((p) => p.dy).reduce(math.max);
    final topPadding = math.min(70.0, size.height * .18),
        bottomPadding = math.min(75.0, size.height * .18);
    scale =
        [
          size.width / 5.75,
          size.height / 4.15,
          (size.width - 80) / (right - left),
          (size.height - topPadding - bottomPadding) / (bottom - top),
        ].reduce(math.min) *
        zoom;
    center = Offset(size.width * .52, size.height * .44);
    if (zoom <= 1) {
      center = Offset(
        center.dx.clamp(
          40 - left * scale,
          math.max(40 - left * scale, size.width - 40 - right * scale),
        ),
        center.dy.clamp(
          topPadding - top * scale,
          math.max(
            topPadding - top * scale,
            size.height - bottomPadding - bottom * scale,
          ),
        ),
      );
    }
  }

  void line(Canvas c, _V a, _V b, Color color, [double width = 1]) =>
      c.drawLine(
        project(a),
        project(b),
        Paint()
          ..color = color
          ..strokeWidth = width,
      );
  void text(
    Canvas c,
    String value,
    Offset at,
    Color color, {
    double size = 10,
  }) {
    (TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: 'Noto Sans CJK SC',
          fontSize: size,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout()).paint(c, at);
  }

  Color shade(Color base, _V normal, {double ambient = .48}) {
    final light = normal.normalized.dot(const _V(-.3, -.6, 1).normalized).abs();
    return Color.lerp(
      const Color(0xff172633),
      base,
      ambient + (1 - ambient) * light,
    )!.withValues(alpha: base.a);
  }

  void box(
    List<_V> front,
    List<_V> back,
    Color base, {
    Color? edge,
    _Texture texture = _Texture.plain,
    double ambient = .65,
  }) {
    final normal = (front[1] - front[0]).cross(front[2] - front[0]);
    final color = shade(base, normal, ambient: ambient);
    faces.add(_Face(front, color, edge: edge ?? base, texture: texture));
    faces.add(
      _Face(
        back.reversed.toList(),
        color,
        edge: edge ?? base,
        texture: texture,
      ),
    );
    for (int j = 0; j < front.length; j++) {
      faces.add(
        _Face(
          [
            front[j],
            back[j],
            back[(j + 1) % front.length],
            front[(j + 1) % front.length],
          ],
          shade(base, normal, ambient: .3),
          edge: edge ?? base,
        ),
      );
    }
  }

  void loft(
    List<List<_V>> sections,
    Color base, {
    Color? edge,
    _Texture texture = _Texture.plain,
    bool caps = true,
    double ambient = .65,
  }) {
    for (int s = 0; s < sections.length - 1; s++) {
      final a = sections[s], b = sections[s + 1];
      for (int j = 0; j < a.length; j++) {
        final k = (j + 1) % a.length;
        final poly = [a[j], b[j], b[k], a[k]];
        final color = shade(
          base,
          (b[j] - a[j]).cross(a[k] - a[j]),
          ambient: ambient,
        );
        faces.add(_Face(poly, color, edge: edge ?? color, texture: texture));
      }
    }
    if (caps) {
      for (final section in [sections.first, sections.last]) {
        faces.add(
          _Face(
            section,
            shade(base, const _V(1, 0, 0), ambient: ambient),
            edge: edge ?? base,
          ),
        );
      }
    }
  }

  void cuboid(
    double xa,
    double xb,
    double ya,
    double yb,
    double za,
    double zb,
    Color color, {
    Color? edge,
  }) => box(
    [_V(xa, ya, za), _V(xb, ya, za), _V(xb, yb, za), _V(xa, yb, za)],
    [_V(xa, ya, zb), _V(xb, ya, zb), _V(xb, yb, zb), _V(xa, yb, zb)],
    color,
    edge: edge,
  );

  // Used only for real mechanical shafts/fasteners, never for the body shell.
  void tube(_V start, _V end, double radius, Color base, {int sides = 12}) {
    final axis = (end - start).normalized;
    final u = axis
        .cross(axis.x.abs() < .9 ? const _V(1, 0, 0) : const _V(0, 0, 1))
        .normalized;
    final v = axis.cross(u);
    List<_V> ring(_V at) => List.generate(sides, (i) {
      final a = i * math.pi * 2 / sides;
      return at + u * (radius * math.cos(a)) + v * (radius * math.sin(a));
    });
    loft([ring(start), ring(end)], base, ambient: .72);
  }

  _V fin(int id, double x, double radius, [double thickness = 0]) =>
      DartGeometry.canard(
        id,
        x,
        radius,
        canardPreviewAngle(servos[id]),
        thickness,
      );

  _V radial(int id, double x, double r, double tangential) =>
      DartGeometry.radial(id, x, r, tangential);

  void addCanards() {
    for (int id = 0; id < 4; id++) {
      const hinge = DartGeometry.hingeX;
      const outline = DartGeometry.canardOutline;
      box(
        outline.map((p) => fin(id, p.$1, p.$2, -.013)).toList(),
        outline.map((p) => fin(id, p.$1, p.$2, .013)).toList(),
        const Color(0xfffaf7ed),
        edge: id == selected ? Color(servoColors[id]) : const Color(0xffb7bbb5),
        ambient: .90,
      );
      // Photo: shaft runs along the foremost edge, with ALL panel chord aft.
      tube(
        radial(id, hinge, .32, 0),
        radial(id, hinge, 1.35, 0),
        .043,
        const Color(0xffd1d9d6),
        sides: 16,
      );
      tube(
        radial(id, hinge, .32, 0),
        radial(id, hinge, .43, 0),
        .074,
        const Color(0xffe9e7df),
      );
      // The black case and metal mounting ears are fixed, not part of the wing.
      box(
        [
          radial(id, -1.69, .24, -.135),
          radial(id, -.59, .24, -.135),
          radial(id, -.59, .24, .135),
          radial(id, -1.69, .24, .135),
        ],
        [
          radial(id, -1.69, .38, -.135),
          radial(id, -.59, .38, -.135),
          radial(id, -.59, .38, .135),
          radial(id, -1.69, .38, .135),
        ],
        const Color(0xff1f2426),
        edge: const Color(0xff3b4346),
      );
      for (final x in [-1.77, -.53]) {
        box(
          [
            radial(id, x, .29, -.16),
            radial(id, x + .16, .29, -.16),
            radial(id, x + .16, .29, .16),
            radial(id, x, .29, .16),
          ],
          [
            radial(id, x, .325, -.16),
            radial(id, x + .16, .325, -.16),
            radial(id, x + .16, .325, .16),
            radial(id, x, .325, .16),
          ],
          const Color(0xffb5c0bd),
          edge: const Color(0xff7b8a8a),
        );
        for (final t in [-.10, .10]) {
          tube(
            radial(id, x + .08, .326, t),
            radial(id, x + .08, .352, t),
            .029,
            const Color(0xff151b1e),
          );
        }
      }
      // Small white horn at the shaft root, rigidly rotating with the panel.
      box(
        [
          fin(id, hinge, .39, -.068),
          fin(id, hinge + .28, .39, -.068),
          fin(id, hinge + .28, .39, .068),
          fin(id, hinge, .39, .068),
        ],
        [
          fin(id, hinge, .45, -.068),
          fin(id, hinge + .28, .45, -.068),
          fin(id, hinge + .28, .45, .068),
          fin(id, hinge, .45, .068),
        ],
        const Color(0xffeeeade),
        ambient: .85,
      );
    }
  }

  void addTail() {
    for (int id = 0; id < 4; id++) {
      // Four fixed slim carbon-fiber stabilizers. Never follow servo commands.
      _V p(double x, double radius, double thickness) =>
          radial(id, x, radius, thickness);
      const poly = DartGeometry.tailOutline;
      box(
        poly.map((v) => p(v.$1, v.$2, -.012)).toList(),
        poly.map((v) => p(v.$1, v.$2, .012)).toList(),
        const Color(0xff262d31),
        edge: const Color(0xff56616a),
        texture: _Texture.carbon,
      );
    }
    loft([
      DartGeometry.section(1.99, .29, .27, .08),
      DartGeometry.section(2.14, .275, .255, .08),
    ], const Color(0xff20272c));
  }

  void addBody() {
    // Compact black rectangular servo/electronics bay, NOT an axial round tube.
    loft(
      [
        DartGeometry.section(-1.79, .275, .275, .07),
        DartGeometry.section(-.43, .275, .275, .07),
      ],
      const Color(0xff2b3236),
      edge: const Color(0xff465054),
    );

    // Short rounded, blunt clear cover. No pointy nose or stepped sleeve rings.
    cuboid(
      -1.94,
      -1.78,
      -.17,
      .17,
      -.17,
      .17,
      const Color(0xff6d7169),
      edge: const Color(0xff959a8c),
    );
    loft(
      [
        DartGeometry.section(-2.06, .19, .21, .075),
        DartGeometry.section(-2.02, .26, .28, .095),
        DartGeometry.section(-1.91, .305, .315, .105),
        DartGeometry.section(-1.76, .305, .315, .085),
      ],
      const Color(0xffe0e6d9).withValues(alpha: .57),
      edge: const Color(0xffedf1e3).withValues(alpha: .22),
      ambient: .84,
    );

    // Restrained internal rails/board visible through the continuous casing.
    cuboid(
      -.44,
      1.93,
      -.13,
      .13,
      -.19,
      -.14,
      const Color(0xff404b4e),
      edge: const Color(0xff697675),
    );
    for (final y in [-.23, .23]) {
      cuboid(
        -.43,
        1.98,
        y - .015,
        y + .015,
        -.225,
        -.19,
        const Color(0xffa3b2b1),
      );
    }
    cuboid(
      -.40,
      .25,
      -.16,
      .16,
      -.12,
      -.055,
      const Color(0xff314a42),
      edge: const Color(0xff627569),
    );
    cuboid(-.29, -.03, -.11, .11, -.055, .025, const Color(0xff1c2427));

    // The main shell is one chamfered rectangular loft. Its full middle section
    // has the SAME width/height from front to rear; only the very end is beveled.
    loft(
      DartGeometry.shellSections,
      const Color(0xffced9d7).withValues(alpha: .51),
      edge: const Color(0xffdce6e2).withValues(alpha: .30),
      texture: _Texture.printed,
      caps: false,
      ambient: .82,
    );

    // Small access opening and clear rear panel on both side flats.
    // Details are mesh faces, so fins can occlude them naturally when orbiting.
    for (final side in [-1.0, 1.0]) {
      final y = side * .362;
      faces.add(
        _Face(
          [
            _V(.09, y, -.055),
            _V(.205, y, -.055),
            _V(.205, y, .065),
            _V(.09, y, .065),
          ],
          const Color(0xff15252b),
          edge: const Color(0xff83938e),
        ),
      );
      faces.add(
        _Face(
          [
            _V(.83, y, -.19),
            _V(1.83, y, -.19),
            _V(1.83, y, .13),
            _V(.83, y, .13),
          ],
          const Color(0xffd9e1dd).withValues(alpha: .07),
          edge: const Color(0xffd4ded8).withValues(alpha: .50),
        ),
      );
      for (final x in [1.01, 1.70]) {
        tube(
          _V(x, y, -.155),
          _V(x, y + side * .019, -.155),
          .026,
          const Color(0xffe1e4db),
        );
      }
    }
  }

  void drawTexture(Canvas canvas, _Face face, Path clip) {
    if (face.texture == _Texture.plain || face.points.length != 4) return;
    final a = face.points[0],
        b = face.points[1],
        d = face.points[3],
        e = face.points[2];
    final uLength = math.sqrt((b - a).dot(b - a)),
        vLength = math.sqrt((d - a).dot(d - a));
    // Patterns are projected in surface space, not pasted screen-space grids.
    Offset uv(double u, double v) => project(
      a * ((1 - u) * (1 - v)) +
          b * (u * (1 - v)) +
          e * (u * v) +
          d * ((1 - u) * v),
    );
    canvas.save();
    canvas.clipPath(clip);
    if (face.texture == _Texture.printed) {
      final columns = (uLength / .105).ceil().clamp(1, 70),
          rows = (vLength / .085).ceil().clamp(1, 12);
      final ink = Paint()
        ..color = const Color(0xffeff3e8).withValues(alpha: .23)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .65;
      for (int i = 0; i <= columns; i++) {
        for (int j = 0; j <= rows; j++) {
          final u = i / columns, v = (j + (i.isOdd ? .5 : 0)) / rows;
          final points = List.generate(6, (k) {
            final t = k * math.pi / 3;
            return uv(
              u + .55 * math.cos(t) / columns,
              v + .5 * math.sin(t) / rows,
            );
          });
          canvas.drawPath(Path()..addPolygon(points, true), ink);
        }
      }
    } else {
      final columns = (uLength / .085).ceil().clamp(1, 40),
          rows = (vLength / .085).ceil().clamp(1, 40);
      for (int i = 0; i < columns; i++) {
        for (int j = 0; j < rows; j++) {
          final horizontal = (i + j).isEven;
          for (int k = 1; k <= 3; k++) {
            final t = k / 4;
            canvas.drawLine(
              uv(
                (i + (horizontal ? .10 : t)) / columns,
                (j + (horizontal ? t : .10)) / rows,
              ),
              uv(
                (i + (horizontal ? .90 : t)) / columns,
                (j + (horizontal ? t : .90)) / rows,
              ),
              Paint()
                ..color = const Color(0xff909898)
                    .withValues(alpha: k == 2 ? .24 : .12)
                ..strokeWidth = .70,
            );
          }
        }
      }
    }
    canvas.restore();
  }

  @override
  void paint(Canvas c, Size size) {
    faces.clear();
    fitCamera(size);
    final rect = Offset.zero & size;
    c.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: const [Color(0xff203745), Color(0xff0d1b27)],
          radius: .9,
          center: const Alignment(0, -.2),
        ).createShader(rect),
    );
    for (int i = -6; i <= 6; i++) {
      line(
        c,
        _V(i * .5, -3, -1.43),
        _V(i * .5, 3, -1.43),
        const Color(0xff203747),
      );
      line(
        c,
        _V(-3, i * .5, -1.43),
        _V(3, i * .5, -1.43),
        const Color(0xff203747),
      );
    }
    addBody();
    addTail();
    addCanards();
    double depth(_Face f) =>
        f.points.map((p) => rotate(p).y).reduce((a, b) => a + b) /
        f.points.length;
    faces.sort((a, b) => depth(b).compareTo(depth(a)));
    for (final face in faces) {
      final projected = face.points.map(project).toList(),
          path = Path()..addPolygon(projected, true);
      c.drawPath(path, Paint()..color = face.color);
      c.drawPath(
        path,
        Paint()
          ..color = face.edge
          ..style = PaintingStyle.stroke
          ..strokeWidth = .65,
      );
      drawTexture(c, face, path);
    }
    drawRotationIndicator(c);
    labels.clear();
    for (int i = 0; i < 4; i++) {
      final color = Color(servoColors[i]), anchor = project(fin(i, -.86, 1.05));
      final raw = project(fin(i, -.86, 1.40));
      final end = Offset(
        raw.dx.clamp(48.0, size.width - 48),
        raw.dy.clamp(
          math.min(112.0, size.height * .25),
          math.max(
            math.min(112.0, size.height * .25) + 1,
            size.height - (size.height < 410 ? 85 : 165),
          ),
        ),
      );
      c.drawLine(
        anchor,
        end,
        Paint()
          ..color = color.withValues(alpha: .65)
          ..strokeWidth = 1,
      );
      c.drawCircle(anchor, 2.5, Paint()..color = color);
      final box = Rect.fromCenter(center: end, width: 83, height: 35);
      c.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(7)),
        Paint()..color = const Color(0xff10232f),
      );
      c.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(7)),
        Paint()
          ..color = color.withValues(alpha: i == selected ? .85 : .35)
          ..style = PaintingStyle.stroke,
      );
      text(
        c,
        '${i + 1}  PWM ${servos[i].pwmIndex}',
        end - const Offset(33, 12),
        color,
        size: 10,
      );
      text(
        c,
        'a ${servos[i].angle.toStringAsFixed(1)}°',
        end + const Offset(-35, 1),
        const Color(0xffa8bbc6),
        size: 8,
      );
      labels[i] = end;
    }
    final nose = project(const _V(-2.06, 0, 0)),
        tail = project(const _V(2.14, 0, 0));
    if ((nose - tail).distance >= 80) {
      text(
        c,
        '镖头',
        nose + const Offset(-27, 25),
        const Color(0xff91aab9),
        size: 11,
      );
    }
    text(
      c,
      '固定尾翼',
      tail + const Offset(-22, 33),
      const Color(0xff7893a4),
      size: 10,
    );
  }

  void drawRotationIndicator(Canvas c) {
    final color = Color(servoColors[selected]);
    final direction = <Offset>[];
    for (int j = 0; j <= 20; j++) {
      final a = .55 - j * .055;
      direction.add(
        project(
          radial(
            selected,
            DartGeometry.hingeX + .32 * math.cos(a),
            1.43,
            .32 * math.sin(a),
          ),
        ),
      );
    }
    final arrow = Path()..moveTo(direction.first.dx, direction.first.dy);
    for (final p in direction.skip(1)) {
      arrow.lineTo(p.dx, p.dy);
    }
    c.drawPath(
      arrow,
      Paint()
        ..color = color
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );
    final end = direction.last, delta = end - direction[direction.length - 2];
    if (delta.distance > 0) {
      final unit = delta / delta.distance;
      c.drawLine(
        end,
        end - unit * 7 + Offset(-unit.dy, unit.dx) * 3.5,
        Paint()
          ..color = color
          ..strokeWidth = 1.2,
      );
    }
    text(c, '+', end + const Offset(4, -8), color, size: 13);
  }

  @override
  bool shouldRepaint(covariant _DartPainter old) => true;
}
