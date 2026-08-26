import 'dart:async';

import 'package:flutter/widgets.dart';

/// Intrinsic pixel size of a network image, cached per URL.
///
/// Needed because [DecorationImage.centerSlice] is expressed in the SOURCE
/// image's own pixels, while لوحة التحكم stores a product's inner box as
/// FRACTIONS (so the numbers survive any upload resolution). Turning one into
/// the other requires knowing how big the artwork actually is.
///
/// Before this existed the callers passed the BUNDLED artwork's size (148x36
/// for the chat bubble, 226x46 for the entry bar) for every image, including
/// uploaded ones — so a 900x260 bubble was sliced as though it were 148x36 and
/// its decoration was cut in the wrong place entirely.
///
/// Resolution is asynchronous and happens once per URL. Until it lands,
/// [peek] returns null and the caller keeps its previous look (a plain
/// `BoxFit.fill` stretch), so nothing ever renders worse than it did before.
class ImageIntrinsicSize {
  ImageIntrinsicSize._();

  static final Map<String, Size> _sizes = {};
  static final Map<String, Future<Size?>> _inFlight = {};

  /// URLs that failed to load. Remembered so a broken product does not queue a
  /// fresh decode attempt on every single rebuild of the list it is in.
  static final Set<String> _failed = <String>{};

  /// The size if it is already known, otherwise null. Never does any work.
  static Size? peek(String url) => _sizes[url];

  /// Resolve (once) and cache the size of [url].
  ///
  /// Returns the cached value immediately when there is one, so a caller may
  /// await this in a build without queueing a second decode.
  static Future<Size?> resolve(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return Future<Size?>.value(null);

    final cached = _sizes[trimmed];
    if (cached != null) return Future<Size?>.value(cached);
    if (_failed.contains(trimmed)) return Future<Size?>.value(null);

    return _inFlight[trimmed] ??= _resolve(trimmed).whenComplete(() {
      _inFlight.remove(trimmed);
    });
  }

  static Future<Size?> _resolve(String url) {
    final completer = Completer<Size?>();
    final stream = NetworkImage(url).resolve(ImageConfiguration.empty);

    late final ImageStreamListener listener;
    void finish(Size? size) {
      stream.removeListener(listener);
      if (size != null) {
        _sizes[url] = size;
      } else {
        _failed.add(url);
      }
      if (!completer.isCompleted) completer.complete(size);
    }

    listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        final size = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
        // The frame is owned by the image cache; this only reads its metrics.
        finish(size.isEmpty ? null : size);
      },
      // A 404 or an unreachable host must not leave the future hanging: the
      // caller falls back to its built-in look.
      onError: (Object _, StackTrace? __) => finish(null),
    );

    stream.addListener(listener);
    return completer.future;
  }
}
