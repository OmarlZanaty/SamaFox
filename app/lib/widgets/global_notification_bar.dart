import 'dart:async';
import 'package:flutter/material.dart';
import '../services/global_notification_service.dart';

class GlobalNotificationBar extends StatefulWidget {
  const GlobalNotificationBar({super.key});

  @override
  State<GlobalNotificationBar> createState() => _GlobalNotificationBarState();
}

class _GlobalNotificationBarState extends State<GlobalNotificationBar> {
  StreamSubscription<GlobalNotificationEvent>? _sub;
  GlobalNotificationEvent? _current;
  Timer? _hideTimer;
  static const Duration _visibleDuration = Duration(seconds: 7);

  @override
  void initState() {
    super.initState();
    _sub = GlobalNotificationService.instance.stream.listen((event) {
      setState(() => _current = event);
      _hideTimer?.cancel();
      _hideTimer = Timer(_visibleDuration, () {
        if (!mounted) return;
        setState(() => _current = null);
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final event = _current;
    return IgnorePointer(
      ignoring: event == null,
      child: SafeArea(
        child: AnimatedSlide(
          offset: event == null ? const Offset(0, -1.2) : Offset.zero,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutBack,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 320),
            opacity: event == null ? 0 : 1,
            child: event == null
                ? const SizedBox.shrink()
                : Align(
                    alignment: Alignment.topCenter,
                    child: GestureDetector(
                      onTap: () {
                        final route = event.routeName;
                        if (route != null && route.isNotEmpty) {
                          Navigator.pushNamed(context, route);
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xCC1C1B34),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.notifications_active_rounded, color: Colors.amber),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    event.title,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                                  ),
                                  Text(
                                    event.message,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
