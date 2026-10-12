import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/socket_service.dart';
import '../services/staff_service.dart';
import 'auth_provider.dart';

final staffServiceProvider = Provider<StaffService>((ref) => StaffService());

/// What نظام الإدارة this account holds (GET /staff/me).
///
/// Loaded once when the app opens (main navigation reads it) and kept for the
/// session, so Settings shows the section at once instead of after a request.
/// It is refreshed on the `staff_access_changed` socket event, on reconnect and
/// on resume; a sign-out / account switch rebuilds it through authStateProvider.
/// Only an account that holds something is rechecked every minute — that is
/// what catches a permission's own expiry — so regular users cost one request.
final staffMeProvider = FutureProvider.autoDispose<StaffAccess?>((ref) async {
  final userId = ref.watch(authStateProvider.select((s) => s.user?.id));
  if (userId == null) return null;
  ref.keepAlive();
  final observer = _StaffLifecycle(ref.invalidateSelf);
  WidgetsBinding.instance.addObserver(observer);
  final socket = SocketService();
  // The server sends this only to the account's own room.
  final changes = socket.staffAccessChangedStream.listen((_) => ref.invalidateSelf());
  final reconnect = socket.reconnectStream.listen((_) => ref.invalidateSelf());
  Timer? poll;
  Timer? expiry;
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    WidgetsBinding.instance.removeObserver(observer);
    changes.cancel();
    reconnect.cancel();
    poll?.cancel();
    expiry?.cancel();
  });
  final access = await ref.read(staffServiceProvider).me();
  if (disposed) return access;
  if (access.rolePanel || access.ban) {
    poll = Timer(const Duration(seconds: 60), ref.invalidateSelf);
  }
  final remaining = access.expiresAt?.difference(DateTime.now());
  // Only arm the end-of-term timer when the end is near: a browser timer
  // longer than ~24.8 days overflows and fires at once, which would refetch in
  // a loop; anything further away is caught by the 60-second recheck.
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
