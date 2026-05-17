import 'dart:async';
import 'dart:collection';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/gift.dart';
import '../services/gift_socket_service.dart';

/// Lanes:
///  - LEGENDARY: 1 active, serialized queue (no cap, but each plays animationMs+200ms grace)
///  - LARGE:     1 active, queue capped at 5
///  - MEDIUM:    2 active concurrent slots, queue capped at 8
///  - SMALL:     ambient stream, no queue, cap 20 visible
@immutable
class GiftAnimationState {
  final GiftSendEvent? activeLegendary;
  final GiftSendEvent? activeLarge;
  final List<GiftSendEvent?> activeMediumSlots; // length 2
  final List<SmallGiftItem> smallStream;
  final bool fireworksActive;
  final List<Color> fireworksPalette;
  final int legendaryQueueDepth;

  const GiftAnimationState({
    this.activeLegendary,
    this.activeLarge,
    this.activeMediumSlots = const [null, null],
    this.smallStream = const [],
    this.fireworksActive = false,
    this.fireworksPalette = const [],
    this.legendaryQueueDepth = 0,
  });

  GiftAnimationState copyWith({
    GiftSendEvent? activeLegendary,
    bool resetLegendary = false,
    GiftSendEvent? activeLarge,
    bool resetLarge = false,
    List<GiftSendEvent?>? activeMediumSlots,
    List<SmallGiftItem>? smallStream,
    bool? fireworksActive,
    List<Color>? fireworksPalette,
    int? legendaryQueueDepth,
  }) {
    return GiftAnimationState(
      activeLegendary: resetLegendary ? null : (activeLegendary ?? this.activeLegendary),
      activeLarge: resetLarge ? null : (activeLarge ?? this.activeLarge),
      activeMediumSlots: activeMediumSlots ?? this.activeMediumSlots,
      smallStream: smallStream ?? this.smallStream,
      fireworksActive: fireworksActive ?? this.fireworksActive,
      fireworksPalette: fireworksPalette ?? this.fireworksPalette,
      legendaryQueueDepth: legendaryQueueDepth ?? this.legendaryQueueDepth,
    );
  }
}

const _defaultFireworksPalette = [
  Color(0xFFFFD700),
  Color(0xFFFF6B9D),
  Color(0xFFFFFFFF),
  Color(0xFF00E5FF),
  Color(0xFFE040FB),
];

class GiftAnimationController extends StateNotifier<GiftAnimationState> {
  GiftAnimationController() : super(const GiftAnimationState());

  GiftSocketService? _socket;
  StreamSubscription? _sentSub;
  StreamSubscription? _legendarySub;

  final Queue<GiftSendEvent> _legendaryQueue = Queue();
  final Queue<GiftSendEvent> _largeQueue = Queue();
  final Queue<GiftSendEvent> _mediumQueue = Queue();

  static const int _largeQueueCap = 5;
  static const int _mediumQueueCap = 8;
  static const int _smallStreamCap = 20;

  /// Bind to a socket service. Safe to call multiple times.
  void bindSocket(GiftSocketService socket) {
    if (identical(socket, _socket)) return;
    _socket?.unbind();
    _socket = socket;
    socket.bind();
    _sentSub?.cancel();
    _legendarySub?.cancel();
    _sentSub = socket.sentStream.listen(ingest);
    _legendarySub = socket.legendaryIncomingStream.listen((_) {
      // Pre-warm hook — actual playback waits for gift_sent.
    });
  }

  /// External entry point: any gift event from any source.
  void ingest(GiftSendEvent event) {
    switch (event.gift.tier) {
      case GiftTier.legendary:
        _enqueueLegendary(event);
        break;
      case GiftTier.large:
        _enqueueLarge(event);
        break;
      case GiftTier.medium:
        _enqueueMedium(event);
        break;
      case GiftTier.small:
        _appendSmall(event);
        break;
    }
  }

  // ---------- LEGENDARY ----------

  void _enqueueLegendary(GiftSendEvent event) {
    _legendaryQueue.add(event);
    state = state.copyWith(legendaryQueueDepth: _legendaryQueue.length);
    if (state.activeLegendary == null) _playNextLegendary();
  }

  void _playNextLegendary() {
    if (_legendaryQueue.isEmpty) return;
    final next = _legendaryQueue.removeFirst();
    final fireworks = next.gift.fireworksEnabled;
    state = state.copyWith(
      activeLegendary: next,
      legendaryQueueDepth: _legendaryQueue.length,
      fireworksActive: fireworks,
      fireworksPalette: fireworks
          ? (next.gift.fireworksColors.isEmpty
              ? _defaultFireworksPalette
              : next.gift.fireworksColors
                  .map((hex) => _parseHex(hex) ?? const Color(0xFFFFD700))
                  .toList())
          : const [],
    );
  }

  void onLegendaryComplete() {
    state = state.copyWith(
      resetLegendary: true,
      fireworksActive: false,
      fireworksPalette: const [],
    );
    // 200ms grace before next legendary
    Future.delayed(const Duration(milliseconds: 200), _playNextLegendary);
  }

  // ---------- LARGE ----------

  void _enqueueLarge(GiftSendEvent event) {
    if (state.activeLarge == null) {
      state = state.copyWith(activeLarge: event);
      return;
    }
    if (_largeQueue.length >= _largeQueueCap) {
      _largeQueue.removeFirst();
    }
    _largeQueue.add(event);
  }

  void onLargeComplete() {
    if (_largeQueue.isEmpty) {
      state = state.copyWith(resetLarge: true);
      return;
    }
    state = state.copyWith(activeLarge: _largeQueue.removeFirst());
  }

  // ---------- MEDIUM ----------

  void _enqueueMedium(GiftSendEvent event) {
    final slots = List<GiftSendEvent?>.from(state.activeMediumSlots);
    final free = slots.indexWhere((s) => s == null);
    if (free >= 0) {
      slots[free] = event;
      state = state.copyWith(activeMediumSlots: slots);
      return;
    }
    if (_mediumQueue.length >= _mediumQueueCap) {
      _mediumQueue.removeFirst();
    }
    _mediumQueue.add(event);
  }

  void onMediumComplete(int slotIndex) {
    final slots = List<GiftSendEvent?>.from(state.activeMediumSlots);
    if (slotIndex < 0 || slotIndex >= slots.length) return;
    if (_mediumQueue.isNotEmpty) {
      slots[slotIndex] = _mediumQueue.removeFirst();
    } else {
      slots[slotIndex] = null;
    }
    state = state.copyWith(activeMediumSlots: slots);
  }

  // ---------- SMALL ----------

  void _appendSmall(GiftSendEvent event) {
    final item = SmallGiftItem(
      id: event.transactionId,
      gift: event.gift,
      sender: event.sender,
      addedAt: DateTime.now(),
    );
    final stream = List<SmallGiftItem>.from(state.smallStream)..add(item);
    while (stream.length > _smallStreamCap) {
      stream.removeAt(0);
    }
    state = state.copyWith(smallStream: stream);
    Future.delayed(
      Duration(milliseconds: event.gift.animationMs + 500),
      () => _retireSmall(item.id),
    );
  }

  void _retireSmall(String id) {
    final stream = state.smallStream.where((s) => s.id != id).toList();
    if (stream.length != state.smallStream.length) {
      state = state.copyWith(smallStream: stream);
    }
  }

  static Color? _parseHex(String hex) {
    var v = hex.trim();
    if (v.startsWith('#')) v = v.substring(1);
    if (v.length == 6) v = 'FF$v';
    if (v.length != 8) return null;
    final n = int.tryParse(v, radix: 16);
    return n == null ? null : Color(n);
  }

  @override
  void dispose() {
    _sentSub?.cancel();
    _legendarySub?.cancel();
    super.dispose();
  }
}

final giftAnimationProvider =
    StateNotifierProvider<GiftAnimationController, GiftAnimationState>(
  (ref) => GiftAnimationController(),
);
