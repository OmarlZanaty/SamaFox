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
  static const Duration _visibleDuration = Duration(seconds: 12);

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
              child: Material(
                color: Colors.transparent,
                child: GestureDetector(
                      onTap: () {
                        final route = event.routeName;
                        if (route != null && route.isNotEmpty) {
                          Navigator.pushNamed(context, route);
                        }
                      },
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Container(
                          width: double.infinity,
                          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xEE2A255B), Color(0xEE1A2A4F)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white30),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x66000000),
                                blurRadius: 12,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.notifications_active_rounded, color: Colors.amber, size: 24),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      event.title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      event.message,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        height: 1.25,
                                        decoration: TextDecoration.none,
                                      ),
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
      ),
      )
    );
  }
}
