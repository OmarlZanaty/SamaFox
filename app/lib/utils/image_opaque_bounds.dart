import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

/// The part of an image that actually has paint in it, cached per URL.
///
/// Frame artwork is uploaded with whatever transparent margin the artist left
/// around it. Drawing such a file into the seat box with `BoxFit.contain` sizes
/// the FILE, not the ring — so a wreath with a 40% margin renders a ring that is
/// visibly smaller than the avatar it is supposed to surround, sitting off
/// centre when the margin is uneven. That is the client's
/// *"الايطار اصغر من المايك والصوره وكمان نازل تحت"*.
///
/// [ProductLayout] stays the source of truth for where a frame's *hole* is —
/// only لوحة التحكم knows that. This measures something different and purely
/// mechanical: which pixels of the file are not transparent, so the caller can
/// scale the artwork until its visible content fills the box it was given.
///
/// Resolution is asynchronous and happens once per URL, off a 128px-wide decode
/// (≈16k pixels to scan, precise to under 1% of the artwork). Until it lands
/// [peek] returns null and the caller keeps its previous look, so nothing ever
/// renders worse than it did before.
@immutable
class OpaqueBounds {
  const OpaqueBounds({required this.rect, required this.aspect});

  /// Bounding box of the non-transparent pixels, as fractions (0..1) of the
  /// artwork — so the numbers survive any upload resolution.
  final Rect rect;

  /// The artwork's own width / height, needed to work out where `BoxFit.contain`
  /// puts it inside a square box.
  final double aspect;

  /// Nothing to correct: the paint already reaches every edge.
  bool get isFull => rect.left <= 0.001 && rect.top <= 0.001 && rect.right >= 0.999 && rect.bottom >= 0.999;
}

class ImageOpaqueBounds {
  ImageOpaqueBounds._();

  static final Map<String, OpaqueBounds> _bounds = {};
  static final Map<String, Future<OpaqueBounds?>> _inFlight = {};

  /// URLs that failed to load or decode. Remembered so a broken product does
  /// not queue a fresh decode on every rebuild of the list it is in.
  static final Set<String> _failed = <String>{};

  /// Width the artwork is decoded at for measuring. Small on purpose: this is
  /// a bounding box, not a render.
  static const int _sampleWidth = 128;

  /// Alpha at or below this is treated as empty, so the soft edge of an
  /// anti-aliased PNG does not count as paint.
  static const int _alphaFloor = 8;

  /// The bounds if they are already known, otherwise null. Never does any work.
  static OpaqueBounds? peek(String url) => _bounds[url.trim()];

  /// Resolve (once) and cache the opaque bounds of [url].
  static Future<OpaqueBounds?> resolve(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return Future<OpaqueBounds?>.value(null);

    final cached = _bounds[trimmed];
    if (cached != null) return Future<OpaqueBounds?>.value(cached);
    if (_failed.contains(trimmed)) return Future<OpaqueBounds?>.value(null);

    return _inFlight[trimmed] ??= _resolve(trimmed).whenComplete(() {
      _inFlight.remove(trimmed);
    });
  }

  static Future<OpaqueBounds?> _resolve(String url) {
    final completer = Completer<OpaqueBounds?>();
    // Same provider the frame itself is drawn with, so measuring costs a cache
    // read rather than a second download of the artwork.
    final provider = ResizeImage(
      CachedNetworkImageProvider(url),
      width: _sampleWidth,
      allowUpscaling: false,
    );
    final stream = provider.resolve(ImageConfiguration.empty);

    late final ImageStreamListener listener;
    var settled = false;

    void finish(OpaqueBounds? value) {
      if (settled) return;
      settled = true;
      stream.removeListener(listener);
      if (value != null) {
        _bounds[url] = value;
      } else {
        _failed.add(url);
      }
      if (!completer.isCompleted) completer.complete(value);
    }

    listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        // The frame is owned by the image cache; this only reads its pixels.
        _measure(info.image).then(finish).catchError((Object _) => finish(null));
      },
      // A 404 or an unreachable host must not leave the future hanging: the
      // caller falls back to its built-in look.
      onError: (Object _, StackTrace? __) => finish(null),
    );

    stream.addListener(listener);
    return completer.future;
  }

  static Future<OpaqueBounds?> _measure(ui.Image image) async {
    final w = image.width;
    final h = image.height;
    if (w <= 0 || h <= 0) return null;

    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    final pixels = data.buffer.asUint8List();
    if (pixels.length < w * h * 4) return null;

    int minX = w, minY = h, maxX = -1, maxY = -1;
    for (int y = 0; y < h; y++) {
      final rowStart = y * w * 4;
      for (int x = 0; x < w; x++) {
        if (pixels[rowStart + x * 4 + 3] <= _alphaFloor) continue;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }

    // A fully transparent file has nothing to fit; the caller keeps its own
    // geometry rather than scaling emptiness up to fill the seat.
    if (maxX < minX || maxY < minY) return null;

    return OpaqueBounds(
      rect: Rect.fromLTRB(
        minX / w,
        minY / h,
        (maxX + 1) / w,
        (maxY + 1) / h,
      ),
      aspect: w / h,
    );
  }
}
