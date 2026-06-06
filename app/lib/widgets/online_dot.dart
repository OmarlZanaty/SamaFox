import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/socket_service.dart';

/// Live set of online user ids, fed by the socket presence events.
class PresenceNotifier extends StateNotifier<Set<int>> {
  PresenceNotifier() : super(const <int>{}) {
    final socket = SocketService();
    state = socket.onlineUsers;
    _sub = socket.presenceStream.listen((s) => state = s);
    socket.requestOnlineUsers();
  }

  StreamSubscription<Set<int>>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final presenceProvider =
    StateNotifierProvider<PresenceNotifier, Set<int>>((ref) => PresenceNotifier());

/// True when [userId] is currently connected.
final isOnlineProvider = Provider.family<bool, int?>((ref, userId) {
  if (userId == null) return false;
  return ref.watch(presenceProvider).contains(userId);
});

/// A small green presence dot. Overlay it on any avatar via a Stack, or place
/// it inline. Shows nothing when the user is offline (unless [showOffline]).
class OnlineDot extends ConsumerWidget {
  const OnlineDot({
    super.key,
    required this.userId,
    this.size = 12,
    this.showOffline = false,
    this.borderColor = Colors.white,
  });

  final int? userId;
  final double size;
  final bool showOffline;
  final Color borderColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider(userId));
    if (!online && !showOffline) return const SizedBox.shrink();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: online ? const Color(0xFF2ECC71) : Colors.grey,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: size * 0.16),
        boxShadow: online
            ? [BoxShadow(color: const Color(0xFF2ECC71).withOpacity(0.7), blurRadius: size * 0.4)]
            : null,
      ),
    );
  }
}
