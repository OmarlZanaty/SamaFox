import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/room_controller_provider.dart';

class RoomActivityPanel extends ConsumerStatefulWidget {
  final int roomId;

  const RoomActivityPanel({
    super.key,
    required this.roomId,
  });

  @override
  ConsumerState<RoomActivityPanel> createState() =>
      _RoomActivityPanelState();
}

class _RoomActivityPanelState
    extends ConsumerState<RoomActivityPanel> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state =
    ref.watch(roomControllerProvider(widget.roomId));
    final events = state.events;

    // ✅ النزول تلقائياً لآخر نشاط
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        children: [
          // ===== العنوان =====
          Row(
            children: const [
              Icon(Icons.notifications_active_outlined,
                  color: Colors.white70, size: 18),
              SizedBox(width: 6),
              Text(
                'النشاط',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // ===== قائمة الأحداث =====
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              itemCount: events.length,
              itemBuilder: (_, i) {
                final e = events[events.length - 1 - i];
                final hh = e.at.hour.toString().padLeft(2, '0');
                final mm = e.at.minute.toString().padLeft(2, '0');

                return Padding(
                  padding:
                  const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Icon(
                        e.icon,
                        size: 16,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 8),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.text,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              '$hh:$mm',
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (events.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text(
                'لا يوجد نشاط مباشر حالياً',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
