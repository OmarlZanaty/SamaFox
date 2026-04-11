import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/room_controller_provider.dart';

class FloatingChatOverlay extends ConsumerStatefulWidget {
  final int roomId;

  const FloatingChatOverlay({required this.roomId});

  @override
  FloatingChatOverlayState createState() => FloatingChatOverlayState();
}

class FloatingChatOverlayState extends ConsumerState<FloatingChatOverlay> {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey();
  final List<String> _messageKeys = [];
  late Timer _timer;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(roomControllerProvider(widget.roomId));
    final messages = state.messages;

    // Limit the messages to show the latest 5 messages
    final visible = messages.length > 5
        ? messages.sublist(messages.length - 5)
        : messages;

    return AnimatedList(
      key: _listKey,
      initialItemCount: visible.length,
      itemBuilder: (context, index, animation) {
        final message = visible[index];

        // Add timer to remove message after 5 seconds
        if (!_messageKeys.contains(message.message)) {
          _messageKeys.add(message.message);

          // Automatically remove message after 5 seconds
          _timer = Timer(const Duration(seconds: 5), () {
            if (mounted) {
              setState(() {
                _messageKeys.remove(message.message);
              });
              _listKey.currentState?.removeItem(
                index,
                    (context, animation) => FadeTransition(opacity: animation),
              );
            }
          });
        }

        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(animation),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.45),
                borderRadius: BorderRadius.circular(10),
              ),
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '${message.username}: ',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    TextSpan(
                      text: message.message,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
}