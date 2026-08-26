import 'dart:convert';
import 'package:flutter/widgets.dart';

/// Where a decorated product's EMPTY inner box is, and which part of it may be
/// stretched — both configured per product in لوحة التحكم and shipped with the
/// artwork.
///
/// The client's rule, repeated for chat bubbles, the entry banner and mic
/// frames alike: *"انا محدود داخل مربع الفقاعه الفارغ ... مليش علاقه بأي زخرفة"*.
/// The app is never allowed to guess where the decoration ends — the dashboard
/// says so, as FRACTIONS of the artwork (0..0.49 in from each edge) so the
/// numbers survive any upload resolution.
///
/// * [insets] — the inner box content is laid out in. Text/avatars never leave
///   it, and the widget grows (both axes) until the content fits.
/// * [slice] — the 9-slice centre. Only this rectangle stretches, so decorated
///   end-caps keep their shape however long the message gets.
@immutable
class ProductLayout {
  const ProductLayout({this.insets, this.slice});

  final _Box? insets;
  final _Box? slice;

  static const ProductLayout empty = ProductLayout();

  bool get isEmpty => insets == null && slice == null;

  /// True when لوحة التحكم actually marked out an inner box for this product.
  /// Callers use it to choose between "place on the configured hole" and their
  /// own built-in geometry.
  bool get hasInsets => insets != null;

  /// Parses whatever the server sent: a decoded map, or a JSON string (some
  /// endpoints hand the column through verbatim). Anything unusable becomes
  /// [empty], which makes the caller fall back to its built-in look.
  static ProductLayout parse(dynamic raw) {
    if (raw == null) return empty;
    dynamic obj = raw;
    if (obj is String) {
      final s = obj.trim();
      if (s.isEmpty) return empty;
      try {
        obj = jsonDecode(s);
      } catch (_) {
        return empty;
      }
    }
    if (obj is! Map) return empty;
    return ProductLayout(
      insets: _Box.parse(obj['insets']),
      slice: _Box.parse(obj['slice']),
    );
  }

  /// Content padding for a widget of [size], from [insets].
  ///
  /// [minimum] is the app's own built-in padding, used when the dashboard has
  /// not configured an inner box for this product — never smaller than that, so
  /// an unconfigured design still looks the way it always did.
  EdgeInsets padding(Size size, EdgeInsets minimum) {
    final box = insets;
    if (box == null) return minimum;
    return EdgeInsets.only(
      left: box.l * size.width,
      top: box.t * size.height,
      right: box.r * size.width,
      bottom: box.b * size.height,
    );
  }

  /// The 9-slice centre in SOURCE-IMAGE pixels, which is what
  /// [DecorationImage.centerSlice] expects. Needs the artwork's intrinsic size;
  /// returns null when no slice is configured, and the caller then uses
  /// [BoxFit.fill] as before.
  Rect? centerSlice(Size imageSize) {
    final box = slice;
    if (box == null) return null;
    final l = box.l * imageSize.width;
    final t = box.t * imageSize.height;
    final r = imageSize.width - box.r * imageSize.width;
    final b = imageSize.height - box.b * imageSize.height;
    // A degenerate rect throws inside the engine, so refuse it here.
    if (r <= l || b <= t) return null;
    return Rect.fromLTRB(l, t, r, b);
  }
}

/// Four fractional sides, clamped to a range that always leaves an inner box.
@immutable
class _Box {
  const _Box(this.l, this.t, this.r, this.b);

  final double l;
  final double t;
  final double r;
  final double b;

  static _Box? parse(dynamic raw) {
    if (raw is! Map) return null;
    double side(dynamic v) {
      final d = v is num ? v.toDouble() : double.tryParse('$v');
      if (d == null || d.isNaN) return 0;
      return d.clamp(0.0, 0.49).toDouble();
    }

    final box = _Box(side(raw['l']), side(raw['t']), side(raw['r']), side(raw['b']));
    if (box.l == 0 && box.t == 0 && box.r == 0 && box.b == 0) return null;
    return box;
  }
}
