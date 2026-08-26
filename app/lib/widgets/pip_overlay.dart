// lib/widgets/pip_overlay.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/pip_state.dart';
import '../providers/room_controller_provider.dart';
import '../providers/auth_provider.dart';
import '../services/audio_controller.dart';
import '../services/socket_service.dart';
import '../services/room_audio_keepalive.dart';
import '../services/webrtc_audio_service.dart';
import '../main.dart';

class PipOverlay extends ConsumerStatefulWidget {
  const PipOverlay({super.key});

  @override
  ConsumerState<PipOverlay> createState() => _PipOverlayState();
}

class _PipOverlayState extends ConsumerState<PipOverlay> {
  Offset _offset = const Offset(20, 120);
  bool _showCloseOptions = false; // ✅ toggle close popup

  /// Tear down the audio session RoomScreen left running for the bubble.
  ///
  /// Only for actually LEAVING. Expanding back into the room deliberately does
  /// not call this: the room re-uses the very same session, and killing it here
  /// would put the "الصوت بيقطع" gap back in, just one screen later.
  void _endRoomAudio() {
    AudioController.instance.deactivate();
    WebRTCAudioService().disableVAD();
    WebRTCAudioService().dispose();
    RoomAudioKeepAlive.instance.stop();
  }

  @override
  Widget build(BuildContext context) {
    final pip = ref.watch(pipProvider);
    if (!pip.isActive || pip.roomId == null) return const SizedBox.shrink();

    final roomId = pip.roomId!;
    final state = ref.watch(roomControllerProvider(roomId));
    final userId = ref.watch(authStateProvider).user?.id;

    final onSeat = state.seats.values.any((s) => s.userId == userId);
    SeatData? mySeat;
    for (final s in state.seats.values) {
      if (s.userId == userId) { mySeat = s; break; }
    }
    final isMuted = mySeat?.isMuted ?? true;

    return Stack(
      children: [
        // ── close options popup (appears above pip) ──
        if (_showCloseOptions)
          Positioned(
            left: _offset.dx - 10,
            top: _offset.dy - 90,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1347),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 12,
                    )
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Leave room ──
                    GestureDetector(
                      onTap: () {
                        setState(() => _showCloseOptions = false);
                        // A23 — RoomScreen handed the live audio session over
                        // when it popped, so this is the only place that can
                        // end it. Order matters: stop the session first, then
                        // drop the bubble (deactivating unmounts this widget
                        // and, with it, the last watcher of the room
                        // controller, which is what sends `leave_room`).
                        _endRoomAudio();
                        ref.read(pipProvider.notifier).deactivate();
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.red.withOpacity(0.15),
                              border: Border.all(color: Colors.redAccent),
                            ),
                            child: const Icon(Icons.logout, color: Colors.redAccent, size: 20),
                          ),
                          const SizedBox(height: 4),
                          const Text('مغادرة', style: TextStyle(color: Colors.white70, fontSize: 10)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    // ── Cancel (keep pip) ──
                    GestureDetector(
                      onTap: () => setState(() => _showCloseOptions = false),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.08),
                              border: Border.all(color: Colors.white38),
                            ),
                            child: const Icon(Icons.close, color: Colors.white54, size: 20),
                          ),
                          const SizedBox(height: 4),
                          const Text('إلغاء', style: TextStyle(color: Colors.white70, fontSize: 10)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // ── main draggable pip bubble ──
        Positioned(
          left: _offset.dx,
          top: _offset.dy,
          child: GestureDetector(
            onPanUpdate: (d) => setState(() {
              _showCloseOptions = false;
              _offset += d.delta;
            }),
            child: Material(
              color: Colors.transparent,
              elevation: 10,
              child: Container(
                width: 90,
                height: 115,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2A1655), Color(0xFF6B4CE6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6B4CE6).withOpacity(0.5),
                      blurRadius: 18,
                      spreadRadius: 2,
                    )
                  ],
                  border: Border.all(
                    color: onSeat && !isMuted ? Colors.greenAccent : Colors.white.withOpacity(0.2),
                    width: onSeat && !isMuted ? 2 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [

                    // ── room image (tap to expand) ──
                    GestureDetector(
                      onTap: () {
                        setState(() => _showCloseOptions = false);
                        ref.read(pipProvider.notifier).deactivate();
                        // ✅ use root navigator to push on top of everything
                        navigatorKey.currentState?.pushNamed('/room', arguments: roomId);
                      },
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: onSeat && !isMuted ? Colors.greenAccent : Colors.white24,
                            width: onSeat && !isMuted ? 2.5 : 1,
                          ),
                          image: (pip.roomImageUrl ?? '').isNotEmpty
                              ? DecorationImage(
                            image: NetworkImage(pip.roomImageUrl!),
                            fit: BoxFit.cover,
                          )
                              : null,
                        ),
                        child: (pip.roomImageUrl ?? '').isEmpty
                            ? const Icon(Icons.mic, color: Colors.white, size: 20)
                            : null,
                      ),
                    ),

                    const SizedBox(height: 4),

                    // ── room name ──
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        pip.roomName ?? 'Room',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),

                    const SizedBox(height: 4),

                    // ── mic toggle (only if on seat) ──
                    if (onSeat)
                      GestureDetector(
                        onTap: () {
                          if (userId == null || mySeat == null) return;
                          ref.read(roomControllerProvider(roomId).notifier).toggleMute(
                            seatNumber: mySeat!.seatNumber,
                            isMuted: !isMuted,
                            targetUserId: userId,
                          );
                        },
                        child: Icon(
                          isMuted ? Icons.mic_off : Icons.mic,
                          color: isMuted ? Colors.redAccent : Colors.greenAccent,
                          size: 16,
                        ),
                      ),

                    const SizedBox(height: 4),

                    // ── expand + close row ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // expand → re-enter room
                        GestureDetector(
                          onTap: () {
                            setState(() => _showCloseOptions = false);
                            ref.read(pipProvider.notifier).deactivate();
                            navigatorKey.currentState?.pushNamed('/room', arguments: roomId); // ✅
                          },
                          child: const Icon(Icons.open_in_full, color: Colors.white70, size: 15),
                        ),
                        // close → show 2-option popup
                        GestureDetector(
                          onTap: () => setState(() => _showCloseOptions = !_showCloseOptions),
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.red.withOpacity(0.2),
                              border: Border.all(color: Colors.redAccent, width: 1.2),
                            ),
                            child: const Icon(Icons.close, color: Colors.redAccent, size: 14),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}