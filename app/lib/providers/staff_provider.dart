import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/socket_service.dart';
import '../services/staff_service.dart';
import 'auth_provider.dart';

final staffServiceProvider = Provider<StaffService>((ref) => StaffService());

// Compatibility for the legacy main-navigation warmup. It must do no work.
final staffMeProvider = FutureProvider.autoDispose<StaffAccess?>((ref) async => null);

/// Watched only by settings and staff routes; disposed when they close.
final staffPanelAccessProvider = FutureProvider.autoDispose<StaffAccess?>((ref) async {
  final userId = ref.watch(authStateProvider.select((s) => s.user?.id));
  if (userId == null) return null;
  final observer = _StaffLifecycle(ref.invalidateSelf);
  WidgetsBinding.instance.addObserver(observer);
  final socket = SocketService();
  // The server sends this only to the account's own room.
  final changes = socket.staffAccessChangedStream.listen((_) => ref.invalidateSelf());
  final reconnect = socket.reconnectStream.listen((_) => ref.invalidateSelf());
  Timer? expiry;
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    WidgetsBinding.instance.removeObserver(observer);
    changes.cancel();
    reconnect.cancel();
    expiry?.cancel();
  });
  final access = await ref.read(staffServiceProvider).me();
  if (disposed) return access;
  final remaining = access.expiresAt?.difference(DateTime.now());
  // One expiry deadline while the panel is observed; no periodic polling.
  if (remaining != null && remaining > Duration.zero && remaining < const Duration(days: 1)) {
    expiry = Timer(remaining, ref.invalidateSelf);
  }
  return access;
});

class _StaffLifecycle extends WidgetsBindingObserver {
  _StaffLifecycle(this.refresh);
  final void Function() refresh;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }
}
