// lib/providers/pip_state.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PipState {
  final bool isActive;
  final int? roomId;
  final String? roomName;
  final String? roomImageUrl;

  const PipState({
    this.isActive = false,
    this.roomId,
    this.roomName,
    this.roomImageUrl,
  });

  PipState copyWith({
    bool? isActive,
    int? roomId,
    String? roomName,
    String? roomImageUrl,
  }) => PipState(
    isActive: isActive ?? this.isActive,
    roomId: roomId ?? this.roomId,
    roomName: roomName ?? this.roomName,
    roomImageUrl: roomImageUrl ?? this.roomImageUrl,
  );
}

class PipNotifier extends StateNotifier<PipState> {
  PipNotifier() : super(const PipState());

  void activate({required int roomId, String? roomName, String? roomImageUrl}) {
    state = PipState(
      isActive: true,
      roomId: roomId,
      roomName: roomName,
      roomImageUrl: roomImageUrl,
    );
  }

  void deactivate() => state = const PipState();
}

final pipProvider = StateNotifierProvider<PipNotifier, PipState>(
      (ref) => PipNotifier(),
);