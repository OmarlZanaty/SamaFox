import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'plinko_physics.dart';

/// Geometry of the board for the current size and row count.
///
/// Computed once per layout change and shared by the frame loop and the
/// painter, so peg contacts are detected against exactly the pegs being drawn.
class PlinkoLayoutGeometry {
  const PlinkoLayoutGeometry({
    required this.rows,
    required this.spacing,
    required this.centerX,
    required this.topY,
    required this.slotY,
    required this.slotHeight,
    required this.slotCount,
    required this.size,
  });

  final int rows, slotCount;
  final double spacing, centerX, topY, slotY, slotHeight;
  final Size size;

  Offset peg(int row, int index) =>
      Offset(centerX + (index - row / 2) * spacing, topY + row * spacing);

  Offset slot(int index) => Offset(
        centerX + (index - (slotCount - 1) / 2) * spacing,
        slotY + slotHeight / 2,
      );

  bool matches(Size other, int otherRows, int otherSlots) =>
      other == size && otherRows == rows && otherSlots == slotCount;
}

/// Mutable per-frame state. Lives outside the widget tree so the frame loop can
/// advance the animation without a single `setState` — the painter subscribes
/// to the ticker directly and repaints in isolation.
class PlinkoBoardModel {
  Duration now = Duration.zero;
  PlinkoLayoutGeometry? geometry;

  final List<PlinkoBall> balls = [];
  final List<PlinkoParticle> particles = [];

  /// Peg strike times, indexed by the flat peg number (row*(row+1)/2 + i).
  /// A flat list rather than a map keyed by "row:index": the old version
  /// allocated 136 strings every frame just to look up a timestamp.
  Float64List pegStruck = Float64List(0);

  /// Slot flash times in milliseconds, -1 for never.
  Float64List slotFlashed = Float64List(0);

  /// Slots a ball may still land in, pulsed as it nears the bottom.
  final Set<int> anticipated = {};

  Offset shake = Offset.zero;

  /// Rolling render quality, driven by measured frame time.
  final PlinkoQuality quality = PlinkoQuality();

  void ensureCapacity(int rows, int slots) {
    final pegs = rows * (rows + 1) ~/ 2;
    if (pegStruck.length != pegs) {
      pegStruck = Float64List(pegs)..fillRange(0, pegs, -1e9);
    }
    if (slotFlashed.length != slots) {
      slotFlashed = Float64List(slots)..fillRange(0, slots, -1e9);
    }
  }

  static int pegIndex(int row, int i) => row * (row + 1) ~/ 2 + i;
}

/// Sheds visual load when the device cannot hold frame rate.
///
/// A fixed effect budget has to target the slowest phone that will ever run the
/// game, which means flagships get the cheap version too. Measuring instead lets
/// each device run as rich as it can: the Redmi keeps 60fps by dropping sparks
/// and halos, a faster phone never loses them.
class PlinkoQuality {
  /// Exponential moving average of frame time in milliseconds.
  double _averageFrameMs = 16.7;
  Duration? _lastFrame;

  /// 1.0 = everything, down to 0.35 = essentials only.
  double _level = 1.0;

  double get level => _level;
  bool get halosEnabled => _level > 0.55;
  bool get trailsEnabled => _level > 0.45;
  bool get shadowsEnabled => _level > 0.7;

  /// Scales particle counts; a burst asks for this fraction of its full size.
  double get particleScale => _level;

  void sample(Duration now) {
    final last = _lastFrame;
    _lastFrame = now;
    if (last == null) return;

    final deltaMs = (now - last).inMicroseconds / 1000.0;
    // Ignore pauses: backgrounding the app should not trigger a quality drop.
    if (deltaMs <= 0 || deltaMs > 200) return;

    _averageFrameMs = _averageFrameMs * 0.9 + deltaMs * 0.1;

    // 60fps is 16.7ms. Degrade past ~22ms, recover under ~18ms, with a gap
    // between the thresholds so quality cannot oscillate frame to frame.
    if (_averageFrameMs > 22 && _level > 0.35) {
      _level = math.max(0.35, _level - 0.02);
    } else if (_averageFrameMs < 18 && _level < 1.0) {
      _level = math.min(1.0, _level + 0.008);
    }
  }
}

/// Small additive sprites built once at startup.
///
/// Drawing a soft glow with `MaskFilter.blur` costs a save-layer and a blur pass
/// *per call*; on a mid-range phone a few dozen particles that way is enough to
/// miss frame budget on its own. A pre-rendered radial gradient blitted with
/// `BlendMode.plus` is a plain textured quad, and batches through `drawAtlas`.
class PlinkoGlow {
  PlinkoGlow._(this.dot, this.halo);

  final ui.Image dot;
  final ui.Image halo;

  static Future<PlinkoGlow> create() async {
    final dot = await _radial(
        64,
        const [Colors.white, Colors.white24, Colors.transparent],
        const [0.0, 0.35, 1.0]);
    final halo = await _radial(
        128, const [Colors.white, Colors.transparent], const [0.0, 1.0]);
    return PlinkoGlow._(dot, halo);
  }

  static Future<ui.Image> _radial(
      int size, List<Color> colors, List<double> stops) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble());
    canvas.drawRect(
      rect,
      Paint()
        ..shader =
            RadialGradient(colors: colors, stops: stops).createShader(rect),
    );
    return recorder.endRecording().toImage(size, size);
  }
}

/// Reusable transform/rect buffers for `drawAtlas`.
///
/// The peg field is 136 sprites at 16 rows. As individual `drawImageRect` calls
/// that is 136 draw ops a frame; through `drawAtlas` it is one, and the buffers
/// are allocated once instead of per frame.
class AtlasBuffer {
  Float32List _transforms = Float32List(0);
  Float32List _rects = Float32List(0);
  Int32List _colors = Int32List(0);
  int _count = 0;

  void reset(int capacity) {
    if (_transforms.length < capacity * 4) {
      _transforms = Float32List(capacity * 4);
      _rects = Float32List(capacity * 4);
      _colors = Int32List(capacity);
    }
    _count = 0;
  }

  /// [scale] is sprite-pixels to logical-pixels; [rotation] in radians.
  void add(
    ui.Image image,
    Offset center,
    double scale, {
    double rotation = 0,
    Color color = Colors.white,
  }) {
    final i = _count * 4;
    final cos = math.cos(rotation) * scale;
    final sin = math.sin(rotation) * scale;
    final w = image.width.toDouble();
    final h = image.height.toDouble();

    _transforms[i] = cos;
    _transforms[i + 1] = sin;
    _transforms[i + 2] = center.dx - (cos * w - sin * h) / 2;
    _transforms[i + 3] = center.dy - (sin * w + cos * h) / 2;

    _rects[i] = 0;
    _rects[i + 1] = 0;
    _rects[i + 2] = w;
    _rects[i + 3] = h;

    // ignore: deprecated_member_use
    _colors[_count] = color.value;
    _count++;
  }

  void flush(Canvas canvas, ui.Image image, Paint paint, {BlendMode? blend}) {
    if (_count == 0) return;
    canvas.drawRawAtlas(
      image,
      Float32List.sublistView(_transforms, 0, _count * 4),
      Float32List.sublistView(_rects, 0, _count * 4),
      Int32List.sublistView(_colors, 0, _count),
      blend ?? BlendMode.modulate,
      null,
      paint,
    );
    _count = 0;
  }
}
