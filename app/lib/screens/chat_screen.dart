import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_sound/public/flutter_sound_recorder.dart';
import '../services/socket_service.dart';
import '../widgets/chat/message_bubble.dart';
import '../widgets/chat/typing_indicator_bar.dart';
import '../widgets/chat/pinned_search_bar.dart';
import '../widgets/chat/voice_note_composer.dart';
import '../providers/message_providers.dart';
import '../theme/app_theme.dart';
import '../models/direct_message.dart';
import '../providers/auth_provider.dart';
import 'package:characters/characters.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final int partnerId;
  final String partnerName;
  final String? partnerAvatarUrl;
  final bool? partnerOnline;
  final VoidCallback? onBack;

  const ChatScreen({
    super.key,
    required this.partnerId,
    required this.partnerName,
    this.partnerAvatarUrl,
    this.partnerOnline,
    this.onBack,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  bool _didListen = false;
  // “Near bottom” threshold to decide if we auto-scroll
  static const double _bottomThresholdPx = 120;
  bool _showJumpToBottom = false;
  bool _isLoadingMore = false;
  // Voice note UI state (UI only for now)
  bool _isRecording = false;
  Duration _recordElapsed = Duration.zero;
  Timer? _recordTimer;
  final _recorder = FlutterSoundRecorder();
  String? _voicePath;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);

    // ✅ ADD THIS
    SocketService().messageStream.listen((event) {
      if (!mounted) return;

      final partnerId = widget.partnerId;
      final partnerName = widget.partnerName;
      final partnerAvatarUrl = widget.partnerAvatarUrl;
      final partnerOnline = widget.partnerOnline;

      if (partnerId > 0) {
        ref.read(chatControllerProvider(partnerId).notifier).refresh();
      }
    });

    _initRecorder();
  }

  Future<void> _initRecorder() async {
    await _recorder.openRecorder();
    await Permission.microphone.request();
  }

  void _cancelRecordingUI() {
    _recordTimer?.cancel();
    _recorder.stopRecorder(); // safe even if not recording
    setState(() {
      _isRecording = false;
      _recordElapsed = Duration.zero;
      _voicePath = null;
    });
  }

  Future<void> _startRecordingUI() async {
    final dir = await getTemporaryDirectory();
    _voicePath = '${dir.path}/vn_${DateTime.now().millisecondsSinceEpoch}.aac';

    await _recorder.startRecorder(
      toFile: _voicePath,
      codec: Codec.aacADTS,
    );

    setState(() {
      _isRecording = true;
      _recordElapsed = Duration.zero;
    });

    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _recordElapsed += const Duration(seconds: 1));
    });
  }

  Future<void> _stopRecordingUI() async {
    await _recorder.stopRecorder();
    _recordTimer?.cancel();
    setState(() => _isRecording = false);
  }

  Future<void> _sendVoiceUI() async {
    await _recorder.stopRecorder();
    _recordTimer?.cancel();

    final path = _voicePath;
    setState(() {
      _isRecording = false;
      _recordElapsed = Duration.zero;
    });

    if (path == null) return;

    final partnerId = widget.partnerId;
    final partnerName = widget.partnerName;
    final partnerAvatarUrl = widget.partnerAvatarUrl;
    final partnerOnline = widget.partnerOnline;

    if (partnerId <= 0) return;

    // ✅ controller must implement sendVoice(filePath)
    await ref.read(chatControllerProvider(partnerId).notifier).sendVoice(path);
  }

  @override
  void dispose() {
    _recorder.closeRecorder();
    _controller.dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _focus.dispose();
    _recordTimer?.cancel();
    super.dispose();
  }

  Future<void> _openMessageActionsSheet(
      BuildContext context, {
        required DirectMessage message,
        required bool isMe,
        required ChatController ctrl,
        required int myUserId,
      }) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).cardColor,
      builder: (_) {
        final emojis = ['❤️','😂','😮','😢','😡','👍'];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ✅ reactions row
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: emojis.map((e) {
                    return InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => Navigator.pop(context, 'react:$e'),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(e, style: const TextStyle(fontSize: 22)),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const Divider(height: 1),

              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy'),
                onTap: () => Navigator.pop(context, 'copy'),
              ),
              if (isMe)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Delete'),
                  onTap: () => Navigator.pop(context, 'delete'),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (!mounted || selected == null) return;

    if (selected.startsWith('react:')) {
      final emoji = selected.substring('react:'.length);
      await ctrl.react(messageId: message.id, emoji: emoji, myUserId: myUserId);
      return;
    }

    if (selected == 'copy') {
      await Clipboard.setData(ClipboardData(text: message.text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
      }
    } else if (selected == 'delete') {
      await ctrl.deleteMessage(message.id);
    }
  }



  void _onScroll() {
    if (!_scroll.hasClients) return;

    // Show jump button if user is not near bottom
    final distanceToBottom = _scroll.position.maxScrollExtent - _scroll.position.pixels;
    final shouldShow = distanceToBottom > 400;

    if (shouldShow != _showJumpToBottom) {
      setState(() => _showJumpToBottom = shouldShow);
    }

    // Load more when reaching top (older messages)
    if (_scroll.position.pixels <= 80 && !_isLoadingMore) {
      _tryLoadMore();
    }
  }

  bool _isNearBottom() {
    if (!_scroll.hasClients) return true;
    final distanceToBottom = _scroll.position.maxScrollExtent - _scroll.position.pixels;
    return distanceToBottom <= _bottomThresholdPx;
  }

  void _jumpToBottom({bool animated = true}) {
    if (!_scroll.hasClients) return;
    final target = _scroll.position.maxScrollExtent;
    if (!animated) {
      _scroll.jumpTo(target);
      return;
    }
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _tryLoadMore() async {
    // Controller method is optional, but recommended.
    final partnerId = widget.partnerId;
    if (partnerId <= 0) return;

    final ctrl = ref.read(chatControllerProvider(partnerId).notifier);

    setState(() => _isLoadingMore = true);
    try {
      // If you don’t have loadMore(), add it to your controller.
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      final dynamic dyn = ctrl;
      if (dyn.loadMore != null) {
        await dyn.loadMore();
      }
    } catch (_) {
      // swallow; error is already handled by chatState.error
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _refresh(int partnerId) async {
    final ctrl = ref.read(chatControllerProvider(partnerId).notifier);
    try {
      // If you don’t have refresh(), add it to your controller.
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      final dynamic dyn = ctrl;
      if (dyn.refresh != null) {
        await dyn.refresh();
      }
    } catch (e) { debugPrint("[chat_screen] swallowed: $e"); }
  }

  @override
  Widget build(BuildContext context) {

    final partnerId = widget.partnerId;
    final partnerName = widget.partnerName;
    final partnerAvatarUrl = widget.partnerAvatarUrl;
    final partnerOnline = widget.partnerOnline;

    final myUserId = ref.watch(authStateProvider).user?.id ?? 0;

    // ✅ If partnerId missing => stop early (prevents /messages/0)
    if (partnerId <= 0) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: const Center(child: Text('Chat error: missing partnerId')),
      );
    }

    final chatState = ref.watch(chatControllerProvider(partnerId));
    final chatCtrl = ref.read(chatControllerProvider(partnerId).notifier);

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ✅ Listen once: auto-scroll ONLY when new messages arrive AND user is near bottom
    if (!_didListen) {
      _didListen = true;

      ref.listen(chatControllerProvider(partnerId), (prev, next) {
        final prevLen = prev?.messages.length ?? 0;
        final nextLen = next.messages.length;

        // new message appended
        if (nextLen > prevLen) {
          // Only auto-scroll if user was already near bottom
          if (_isNearBottom()) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom(animated: true));
          } else {
            // user is reading older messages, show jump button
            if (mounted) setState(() => _showJumpToBottom = true);
          }
        }
      });
    }

    final canSend = _controller.text.trim().isNotEmpty && !chatState.sending;

// ✅ build timeline ONCE here (so "items" is defined)
    final timeline = _buildTimeline(chatState.messages);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,

        leading: widget.onBack != null
            ? IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        )
            : null,

        title: Row(
          children: [
            _AvatarCircle(
              name: partnerName,
              avatarUrl: partnerAvatarUrl,
              online: partnerOnline,
            ),
            const SizedBox(width: 10),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    partnerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  if (partnerOnline != null)
                    Text(
                      partnerOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                        fontSize: 12,
                        color: (partnerOnline ? Colors.green : Colors.grey),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: chatState.loading
                    ? Center(
                  child: CircularProgressIndicator(
                    color: isDark ? AppTheme.accentGold : AppTheme.lightPrimary,
                  ),
                )
                    : RefreshIndicator(
                  onRefresh: () => _refresh(partnerId),
                  child: CustomScrollView(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                          child: _TopLoaderHint(
                            isDark: isDark,
                            isLoadingMore: _isLoadingMore,
                            hasMessages: chatState.messages.isNotEmpty,
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                                (context, index) {
                              final item = timeline[index];

                              if (item is _DaySeparatorItem) {
                                return _DaySeparator(label: item.label, isDark: isDark);
                              }

                              final m = (item as _MessageItem).message;
                              final isMe = m.senderId == myUserId;

                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisAlignment:
                                  isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                                  children: [
                                    /// 👤 OTHER USER AVATAR (LEFT)
                                    if (!isMe) ...[
                                      _AvatarCircle(
                                        name: partnerName,
                                        avatarUrl: partnerAvatarUrl,
                                        online: null,
                                      ),
                                      const SizedBox(width: 8),
                                    ],

                                    /// 💬 MESSAGE BUBBLE
                                    Flexible(
                                      child: MessageBubble(
                                        m: m,
                                        isMe: isMe,
                                        isDark: isDark,

                                        onLongPress: () => _openMessageActionsSheet(
                                          context,
                                          message: m,
                                          isMe: isMe,
                                          ctrl: chatCtrl,
                                          myUserId: myUserId,
                                        ),

                                        onReact: (emoji) async {
                                          await chatCtrl.react(
                                            messageId: m.id,
                                            emoji: emoji,
                                            myUserId: myUserId,
                                          );
                                        },

                                        onRetry: () =>
                                            chatCtrl.retrySend(m.clientId, myUserId: myUserId),

                                        onPlayVoice: () {},
                                        onPin: () {},
                                        onUnpin: () {},
                                      ),
                                    ),

                                    /// 👤 MY AVATAR (RIGHT) — optional
                                    if (isMe) ...[
                                      const SizedBox(width: 8),

                                      CircleAvatar(
                                        radius: 16,
                                        backgroundColor: Colors.black.withOpacity(0.06),
                                        child: Text(
                                          'Me', // 👉 replace with your real avatar later
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                            childCount: timeline.length,
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 8)),
                    ],
                  ),
                ),
              ),

              if (chatState.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    chatState.error!,
                    style: TextStyle(color: Colors.red[400]),
                  ),
                ),

              TypingIndicatorBar(
                isTyping: chatState.partnerTyping,
                partnerName: partnerName,
                isDark: isDark,
              ),

              _ComposerBar(
                controller: _controller,
                focus: _focus,
                isDark: isDark,
                canSend: canSend,
                sending: chatState.sending,
                onChanged: (_) => setState(() {}),
                onSend: () => _send(chatCtrl, myUserId),
                onAttach: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Attachments: TODO')),
                  );
                },
                leadingExtra: VoiceNoteComposer(
                  isRecording: _isRecording,
                  elapsed: _recordElapsed,
                  onStart: _startRecordingUI,
                  onStop: _stopRecordingUI,
                  onCancel: _cancelRecordingUI,
                  onSend: _sendVoiceUI,
                ),
              ),
            ],
          ),

          if (_showJumpToBottom)
            Positioned(
              right: 14,
              bottom: MediaQuery.of(context).padding.bottom + 78,
              child: FloatingActionButton.small(
                heroTag: 'jump_bottom_$partnerId',
                onPressed: () {
                  _jumpToBottom(animated: true);
                  setState(() => _showJumpToBottom = false);
                },
                backgroundColor: isDark ? Colors.white12 : Colors.black.withOpacity(0.06),
                elevation: 0,
                child: Icon(
                  Icons.arrow_downward,
                  color: isDark ? AppTheme.accentGold : AppTheme.lightPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _send(ChatController ctrl, int myUserId) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    setState(() {}); // update send button state immediately

    // Optional: keep focus after sending (like WhatsApp)
    _focus.requestFocus();

    ctrl.send(text, myUserId: myUserId);
    // We don’t force scroll; the listener decides based on near-bottom.
  }


  Future<void> _onMessageLongPress(
      BuildContext context, {
        required DirectMessage message,
        required bool isMe,
        required ChatController ctrl,
      }) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).cardColor,
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy'),
                onTap: () => Navigator.pop(context, 'copy'),
              ),
              if (isMe)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Delete'),
                  onTap: () => Navigator.pop(context, 'delete'),
                ),
              const SizedBox(height: 8),
              PinnedSearchBar(
                pinnedCount: 0, // TODO later: load pinned count from repo
                onOpenPins: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Pinned messages: TODO')),
                  );
                },
                onSearch: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Search in chat: TODO')),
                  );
                },
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || selected == null) return;

    if (selected == 'copy') {
      await Clipboard.setData(ClipboardData(text: message.text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
      }
    } else if (selected == 'delete') {
      // If you don’t have deleteMessage(), add it to your controller.
      try {
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        final dynamic dyn = ctrl;
        if (dyn.deleteMessage != null) {
          await dyn.deleteMessage(message.id);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Delete not implemented yet')),
            );
          }
        }
      } catch (e) {
        debugPrint("[chat_screen] deleteMessage failed: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete message')),
          );
        }
      }
    }
  }
}

/* ----------------------------- Timeline helpers ---------------------------- */

List<_TimelineItem> _buildTimeline(List<DirectMessage> messages) {
  // Expect messages are already sorted ascending by time in your controller.
  final items = <_TimelineItem>[];
  DateTime? lastDay;

  for (final m in messages) {
    final dt = _messageTime(m);
    final day = DateTime(dt.year, dt.month, dt.day);

    if (lastDay == null || day.isAfter(lastDay!)) {
      items.add(_DaySeparatorItem(_dayLabel(day)));
      lastDay = day;
    }
    items.add(_MessageItem(m));
  }
  return items;
}

DateTime _messageTime(DirectMessage m) {
  // If your model has DateTime createdAt => use it.
  // If it's String => parse.
  // Otherwise fallback to now (won't crash).
  try {
    final dynamic dyn = m;
    final v = dyn.createdAt;
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
  } catch (e) { debugPrint("[chat_screen] swallowed: $e"); }
  return DateTime.now();
}

String _dayLabel(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));

  if (day == today) return 'Today';
  if (day == yesterday) return 'Yesterday';
  return '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
}

String _timeLabel(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

abstract class _TimelineItem {}

class _DaySeparatorItem extends _TimelineItem {
  final String label;
  _DaySeparatorItem(this.label);
}

class _MessageItem extends _TimelineItem {
  final DirectMessage message;
  _MessageItem(this.message);
}

/* ----------------------------- Message status ----------------------------- */

enum _MsgStatus { sending, sent, failed }

_MsgStatus _inferStatus(DirectMessage m, bool isMe, bool globalSendingFlag) {
  // Best-effort inference. For real production:
  // add fields like: localStatus / serverStatus / deliveredAt / readAt / failedReason
  // and map them here.

  if (!isMe) return _MsgStatus.sent;

  // If your DirectMessage has `failed == true`, use it
  try {
    final dynamic dyn = m;
    final failed = dyn.failed;
    if (failed is bool && failed) return _MsgStatus.failed;

    final sending = dyn.sending;
    if (sending is bool && sending) return _MsgStatus.sending;
  } catch (e) { debugPrint("[chat_screen] swallowed: $e"); }

  // fallback: if controller says sending, treat latest outgoing as sending (weak but ok)
  if (globalSendingFlag) return _MsgStatus.sending;

  return _MsgStatus.sent;
}

/* --------------------------------- Widgets -------------------------------- */

class _TopLoaderHint extends StatelessWidget {
  final bool isDark;
  final bool isLoadingMore;
  final bool hasMessages;

  const _TopLoaderHint({
    required this.isDark,
    required this.isLoadingMore,
    required this.hasMessages,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasMessages) return const SizedBox.shrink();

    if (isLoadingMore) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: isDark ? AppTheme.accentGold : AppTheme.lightPrimary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Loading older messages...',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
        ],
      );
    }

    return Center(
      child: Text(
        'Pull down to refresh • Scroll up for older',
        style: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.white54 : Colors.black45,
        ),
      ),
    );
  }
}

class _DaySeparator extends StatelessWidget {
  final String label;
  final bool isDark;

  const _DaySeparator({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(child: Divider(color: isDark ? Colors.white12 : Colors.black12)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
            ),
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: isDark ? Colors.white12 : Colors.black12)),
        ],
      ),
    );
  }
}

class _ComposerBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final bool isDark;
  final bool canSend;
  final bool sending;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  // ✅ extra widget (voice note)
  final Widget? leadingExtra;

  const _ComposerBar({
    required this.controller,
    required this.focus,
    required this.isDark,
    required this.canSend,
    required this.sending,
    required this.onChanged,
    required this.onSend,
    required this.onAttach,
    this.leadingExtra,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: isDark ? Colors.white10 : Colors.black.withOpacity(0.03),
          border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: sending ? null : onAttach,
              icon: Icon(Icons.add_circle_outline, color: isDark ? Colors.white70 : Colors.black54),
              tooltip: 'Attach',
            ),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focus,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onChanged: onChanged,
                onSubmitted: (_) => canSend ? onSend() : null,
                decoration: InputDecoration(
                  hintText: 'Message...',
                  filled: true,
                  fillColor: isDark ? Colors.white10 : Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                  ),
                ),
              ),
            ),

            // ✅ voice note button widget
            if (leadingExtra != null) ...[
              const SizedBox(width: 6),
              leadingExtra!,
            ],

            const SizedBox(width: 6),
            SizedBox(
              width: 44,
              height: 44,
              child: ElevatedButton(
                onPressed: canSend ? onSend : null,
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                  backgroundColor: isDark ? Colors.white12 : Colors.black.withOpacity(0.06),
                  elevation: 0,
                ),
                child: sending
                    ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: isDark ? AppTheme.accentGold : AppTheme.lightPrimary,
                  ),
                )
                    : Icon(
                  Icons.send,
                  color: isDark ? AppTheme.accentGold : AppTheme.lightPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarCircle extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final bool? online;

  const _AvatarCircle({
    required this.name,
    required this.avatarUrl,
    required this.online,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name.trim().characters.first.toUpperCase() : '?';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: Colors.black.withOpacity(0.06),
          child: CircleAvatar(
            radius: 17,
            backgroundColor: Colors.black.withOpacity(0.06),
            child: avatarUrl == null
                ? Text(initial, style: const TextStyle(fontWeight: FontWeight.w700))
                : ClipOval(
              child: Image.network(
                avatarUrl!,
                width: 34,
                height: 34,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Text(initial),
              ),
            ),
          ),
        ),
        if (online != null)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: online! ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  final DirectMessage message;
  final bool isMe;
  final bool isDark;
  final VoidCallback? onLongPress;
  final _MsgStatus status;

  const _Bubble({
    required this.message,
    required this.isMe,
    required this.isDark,
    required this.status,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isMe
        ? (isDark
        ? AppTheme.accentGold.withOpacity(0.22)
        : AppTheme.lightPrimary.withOpacity(0.14))
        : (isDark ? Colors.white10 : Colors.black.withOpacity(0.05));

    final align = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isMe ? 16 : 4),
      bottomRight: Radius.circular(isMe ? 4 : 16),
    );

    final dt = _messageTime(message);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: align,
        children: [
          GestureDetector(
            onLongPress: onLongPress,
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.80),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: radius,
                border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
              ),
              child: Text(
                message.text,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 15),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _timeLabel(dt),
                style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black45),
              ),
              if (isMe) ...[
                const SizedBox(width: 6),
                _StatusIcon(status: status, isDark: isDark),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final _MsgStatus status;
  final bool isDark;

  const _StatusIcon({required this.status, required this.isDark});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    switch (status) {
      case _MsgStatus.sending:
        icon = Icons.access_time;
        break;
      case _MsgStatus.failed:
        icon = Icons.error_outline;
        break;
      case _MsgStatus.sent:
      default:
        icon = Icons.check;
        break;
    }

    final color = status == _MsgStatus.failed
        ? Colors.redAccent
        : (isDark ? Colors.white54 : Colors.black45);

    return Icon(icon, size: 14, color: color);
  }
}