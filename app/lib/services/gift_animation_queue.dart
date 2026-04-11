import 'dart:async';
import 'dart:collection';
import '../models/gift_event.dart';

class GiftAnimationQueue {
  GiftAnimationQueue._();
  static final GiftAnimationQueue I = GiftAnimationQueue._();

  final _queue = Queue<GiftEvent>();
  final _controller = StreamController<GiftEvent>.broadcast();
  Stream<GiftEvent> get stream => _controller.stream;

  bool _playing = false;

  void enqueue(GiftEvent gift) {
    _queue.add(gift);
    _tryPlayNext();
  }

  void _tryPlayNext() {
    if (_playing) return;
    if (_queue.isEmpty) return;

    _playing = true;
    final gift = _queue.removeFirst();
    _controller.add(gift);

    // auto-finish after duration
    Future.delayed(const Duration(seconds: 3), () {
      _playing = false;
      _tryPlayNext();
    });
  }

  void dispose() {
    _controller.close();
  }
}
