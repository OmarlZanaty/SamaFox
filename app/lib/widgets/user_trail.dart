import 'package:flutter/material.dart';

import '../screens/profile_screen.dart';
import '../screens/room_screen.dart';
import '../services/dio_client.dart';

/// Shared behaviour for every user picture in the app:
///
/// * tapping the picture opens that user's profile;
/// * the small "مسار" badge beside it drops you into whatever room they are
///   in right now.
///
/// Both live here so the two gestures behave the same on room seats, chat
/// lines, search results, follower lists and message threads instead of each
/// screen inventing its own.

/// Opens a user's profile page.
void openUserProfile(BuildContext context, int userId) {
  if (userId <= 0) return;
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId)),
  );
}

/// Resolves where a user currently is and enters that room.
///
/// Pass [knownRoomId] when the caller already has it (follower lists and
/// profiles ship `liveRoomId` with their payload) to skip the lookup.
Future<void> followUserTrail(
  BuildContext context,
  int userId, {
  int? knownRoomId,
}) async {
  if (userId <= 0) return;

  int? roomId = knownRoomId;
  if (roomId == null) {
    try {
      final res = await DioClient.dio.get('/users/$userId');
      final body = res.data;
      final user = (body is Map ? body['user'] : null);
      final raw = (user is Map) ? user['liveRoomId'] : null;
      roomId = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
    } catch (_) {
      roomId = null;
    }
  }

  if (!context.mounted) return;

  if (roomId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('هذا المستخدم ليس في أي غرفة حالياً')),
    );
    return;
  }

  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => RoomScreen(roomId: roomId!)),
  );
}

/// The "مسار" badge — a small footprint chip that sits beside an avatar.
class UserTrailButton extends StatefulWidget {
  const UserTrailButton({
    super.key,
    required this.userId,
    this.liveRoomId,
    this.size = 22,
  });

  final int userId;

  /// Known current room, when the caller already has it. When null the room is
  /// resolved on tap.
  final int? liveRoomId;
  final double size;

  @override
  State<UserTrailButton> createState() => _UserTrailButtonState();
}

class _UserTrailButtonState extends State<UserTrailButton> {
  bool _busy = false;

  Future<void> _go() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await followUserTrail(context, widget.userId,
          knownRoomId: widget.liveRoomId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // A known live room gets the brighter treatment; otherwise the badge is
    // still tappable and resolves on demand.
    final live = widget.liveRoomId != null;
    return Tooltip(
      message: 'مسار',
      child: GestureDetector(
        onTap: _go,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: live ? const Color(0xFF00C853) : const Color(0xFF3A2A6E),
            border: Border.all(color: Colors.white.withOpacity(0.85), width: 1.4),
            boxShadow: [
              BoxShadow(
                color: (live ? const Color(0xFF00C853) : Colors.black)
                    .withOpacity(0.45),
                blurRadius: 5,
              ),
            ],
          ),
          child: _busy
              ? Padding(
                  padding: EdgeInsets.all(widget.size * 0.24),
                  child: const CircularProgressIndicator(
                    strokeWidth: 1.6,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : Icon(
                  Icons.follow_the_signs,
                  size: widget.size * 0.62,
                  color: Colors.white,
                ),
        ),
      ),
    );
  }
}

/// Wraps any avatar widget with the two shared gestures: tap the picture for
/// the profile, tap the corner badge to follow the user's مسار into their room.
class TappableAvatar extends StatelessWidget {
  const TappableAvatar({
    super.key,
    required this.userId,
    required this.child,
    this.liveRoomId,
    this.showTrail = true,
    this.trailSize = 22,
    this.trailAlignment = Alignment.bottomLeft,
  });

  final int userId;
  final Widget child;
  final int? liveRoomId;
  final bool showTrail;
  final double trailSize;
  final Alignment trailAlignment;

  @override
  Widget build(BuildContext context) {
    // Not a real user (a room row, a placeholder): stay out of the way
    // entirely rather than swallowing the parent's tap.
    if (userId <= 0) return child;

    final avatar = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openUserProfile(context, userId),
      child: child,
    );

    if (!showTrail) return avatar;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned.fill(
          child: Align(
            alignment: trailAlignment,
            child: UserTrailButton(
              userId: userId,
              liveRoomId: liveRoomId,
              size: trailSize,
            ),
          ),
        ),
      ],
    );
  }
}
