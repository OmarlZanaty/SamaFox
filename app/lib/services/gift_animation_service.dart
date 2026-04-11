import 'dart:collection';
import 'package:flutter/material.dart';
import '../models/gift.dart';

/// Data class for gift animation information
class GiftAnimationData {

  final int giftId;
  final int senderId;

  final String giftName;
  final String giftImageUrl;

  final String senderName;
  final String receiverName;

  final int quantity;
  final DateTime timestamp;

  final Offset startOffset;   // NEW
  final Offset endOffset;     // NEW

  final int durationMs;

  final int comboCount;
  final bool isCombo;
  final GiftAnimationType animationType; // ✅ ADD

  // NEW
  final String? animationKey;
  final bool isMega;

  GiftAnimationData({
    required this.giftId,
    required this.senderId,
    required this.giftName,
    required this.giftImageUrl,
    required this.senderName,
    required this.receiverName,
    required this.startOffset,
    required this.endOffset,

    this.quantity = 1,
    required this.timestamp,
    this.durationMs = 4500,
    this.comboCount = 1,
    this.isCombo = false,
    required this.animationType, // ✅ ADD

    this.animationKey,
    this.isMega = false,
  });
}

/// Service to manage gift animation queue and state
class GiftAnimationService extends ChangeNotifier {
  final Queue<GiftAnimationData> _queue = Queue<GiftAnimationData>();

  final List<GiftAnimationData> _activeStack = [];
  List<GiftAnimationData> get activeStack => _activeStack;

  GiftAnimationData? _current;

  bool _playing = false;
  int _currentCombo = 1;

  GiftAnimationData? _lastGift;
  DateTime? _lastGiftTime;

  DateTime? _lastAnimationTime;

  static const Duration _animationCooldown = Duration(milliseconds: 250);
  static const Duration _burstWindow = Duration(milliseconds: 600);

  GiftAnimationData? currentGift;

  List<GiftAnimationData> get pendingQueue => List.unmodifiable(_queue);

  final Map<int, int> _comboCounter = {};

  /// Enqueue a gift animation
  void enqueueGift(GiftAnimationData gift) {
    final now = DateTime.now();

    if (_lastGift != null &&
        _lastGift!.senderId == gift.senderId &&
        _lastGift!.giftId == gift.giftId &&
        _lastGiftTime != null &&
        now.difference(_lastGiftTime!) < _burstWindow) {

      // Merge gifts
      _lastGift = GiftAnimationData(
        giftId: gift.giftId,
        senderId: gift.senderId,

        giftName: gift.giftName,
        giftImageUrl: gift.giftImageUrl,
        senderName: gift.senderName,
        receiverName: gift.receiverName,

        startOffset: gift.startOffset,   // ✅ ADD
        endOffset: gift.endOffset,       // ✅ ADD

        quantity: _lastGift!.quantity + gift.quantity,
        timestamp: now,
        durationMs: gift.durationMs,
        comboCount: _lastGift!.comboCount + 1,
        isCombo: true,
        animationType: gift.animationType,
        animationKey: gift.animationKey,
        isMega: gift.isMega,
      );

      updateCombo(_lastGift!.comboCount);
      notifyListeners();
    } else {
      _lastGift = gift;
      _queue.addLast(gift);
    }

    _lastGiftTime = now;

    _tryNext();
  }

  void updateCombo(int combo) {
    final current = _current;
    if (current == null) return;

    _current = GiftAnimationData(
      giftId: current.giftId,
      senderId: current.senderId,

      giftName: current.giftName,
      giftImageUrl: current.giftImageUrl,
      senderName: current.senderName,
      receiverName: current.receiverName,

      startOffset: current.startOffset,   // ✅ ADD
      endOffset: current.endOffset,       // ✅ ADD

      quantity: current.quantity,
      timestamp: current.timestamp,
      durationMs: current.durationMs,
      comboCount: combo,
      isCombo: combo > 1,
      animationType: current.animationType,
      animationKey: current.animationKey,
      isMega: current.isMega,
    );

    notifyListeners();
  }

  void _tryNext() {
    final now = DateTime.now();

    if (_playing) return;

    if (_lastAnimationTime != null &&
        now.difference(_lastAnimationTime!) < _animationCooldown) {
      return;
    }

    if (_queue.isEmpty) {
      currentGift = null;
      notifyListeners();
      return;
    }

    _playing = true;
    final next = _queue.removeFirst();
    currentGift = next;
    _activeStack.add(next);
    _currentCombo = next.comboCount;

    _lastAnimationTime = now;

    notifyListeners();
  }

  /// Call this from overlay when animation ends
  void completeAnimation() {
    _playing = false;

    if (_activeStack.isNotEmpty) {
      _activeStack.removeAt(0);
    }

    notifyListeners();
    _tryNext();
  }

  /// Clear everything
  void clear() {
    _queue.clear();
    _playing = false;
    currentGift = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _queue.clear();
    super.dispose();
  }
}
