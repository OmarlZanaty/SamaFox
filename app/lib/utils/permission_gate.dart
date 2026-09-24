import 'package:permission_handler/permission_handler.dart';

/// Serialises permission requests.
///
/// permission_handler throws `PlatformException(PermissionHandler.PermissionManager,
/// A request for permissions is already running ...)` whenever two callers
/// request while a system dialog is open. Several services (LiveKit engine,
/// WebRTC service, room screen, keep-alive) all ask for the microphone around
/// the same moment when a room opens, so they race. All of them now go
/// through here: the first caller opens the dialog, later callers await the
/// same Future and receive the same result.
class PermissionGate {
  PermissionGate._();

  static final Map<Permission, Future<PermissionStatus>> _inFlight = {};

  /// Returns the current status without prompting when already granted,
  /// otherwise prompts once and shares that prompt with concurrent callers.
  static Future<PermissionStatus> request(Permission permission) async {
    final current = await permission.status;
    if (current.isGranted) return current;

    final pending = _inFlight[permission];
    if (pending != null) return pending;

    final future = permission.request().whenComplete(() {
      _inFlight.remove(permission);
    });
    _inFlight[permission] = future;
    return future;
  }
}
