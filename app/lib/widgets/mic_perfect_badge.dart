import 'package:flutter/material.dart';

import '../services/socket_service.dart';

/// Step 5: small "perfect mic" badge shown for a seated user whose microphone
/// passed the self-test (live audio track with echo/noise/gain processing on).
/// Listens live to the socket mic-verified roster.
class MicPerfectBadge extends StatefulWidget {
  const MicPerfectBadge({super.key, required this.userId, this.compact = false});

  final int? userId;
  final bool compact;

  @override
  State<MicPerfectBadge> createState() => _MicPerfectBadgeState();
}

class _MicPerfectBadgeState extends State<MicPerfectBadge> {
  @override
  Widget build(BuildContext context) {
    final socket = SocketService();
    return StreamBuilder<Set<int>>(
      stream: socket.micVerifiedStream,
      builder: (context, _) {
        final verified =
            widget.userId != null && socket.isMicVerified(widget.userId!);
        if (!verified) return const SizedBox.shrink();
        if (widget.compact) {
          return const Icon(Icons.verified, size: 14, color: Color(0xFF2ECC71));
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0x222ECC71),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF2ECC71)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mic, size: 12, color: Color(0xFF2ECC71)),
              SizedBox(width: 4),
              Text('مايك ممتاز',
                  style: TextStyle(
                      color: Color(0xFF2ECC71),
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        );
      },
    );
  }
}
