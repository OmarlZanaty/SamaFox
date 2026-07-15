import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/message_providers.dart';
import '../providers/locale_provider.dart';
import '../providers/auth_provider.dart';
import '../services/socket_service.dart';
import '../theme/app_theme.dart';
import '../models/conversation_item.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';

final unreadCountProvider = Provider<int>((ref) {
  final async = ref.watch(conversationsControllerProvider);

  return async.maybeWhen(
    data: (list) => list.fold(0, (sum, c) => sum + c.unreadCount),
    orElse: () => 0,
  );
});

class MessagesScreen extends ConsumerStatefulWidget {
  final Function(ConversationItem)? onOpenChat; // 👈 ADD
  const MessagesScreen({super.key, this.onOpenChat});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  final _searchCtrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    SocketService().messageStream.listen((_) {
      ref.read(conversationsControllerProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final myUserId = ref.watch(authStateProvider).user?.id ?? 0;

    final asyncList = ref.watch(conversationsControllerProvider);

    return Material(
        color: Colors.transparent,
        child: SafeArea(
            child: Stack(
        children: [
          Column(
            children: [

              // ===== HEADER (replaces AppBar) =====
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.message, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      strings.messages,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.more_horiz, color: Colors.white),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),

              // ===== BODY =====
              Expanded(
                child: asyncList.when(
                  data: (list) {
                    final filtered = _q.isEmpty
                        ? list
                        : list.where((c) => c.partnerName.toLowerCase().contains(_q.toLowerCase())).toList();

                    return Column(
                      children: [
                        // 🔍 search
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                            ),
                            child: TextField(
                              controller: _searchCtrl,
                              onChanged: (v) => setState(() => _q = v.trim()),
                              decoration: InputDecoration(
                                prefixIcon: Icon(Icons.search, color: isDark ? Colors.white54 : Colors.black45),
                                hintText: strings.search,
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                        ),

                        Expanded(
                          child: filtered.isEmpty
                              ? _EmptyState(isDark: isDark, strings: strings)
                              : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final c = filtered[i];
                              return _ConversationTile(
                                conversation: c,
                                strings: strings,
                                isDark: isDark,
                                myUserId: myUserId,
                                onOpenChat: widget.onOpenChat, // 👈 ADD THIS
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                ),
              ),
            ],
          ),

          // ===== FLOATING BUTTON (instead of Scaffold FAB) =====
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              onPressed: () {},
              child: const Icon(Icons.edit),
            ),
          ),
        ],
      ),
    ));
  }
}

class _EmptyState extends StatelessWidget {
  final bool isDark;
  final dynamic strings;
  const _EmptyState({required this.isDark, required this.strings});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.message_outlined, size: 80, color: isDark ? Colors.white24 : Colors.black12),
          const SizedBox(height: 24),
          Text(
            strings.noConversationsYet,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            strings.noMessages,
            style: TextStyle(fontSize: 14, color: isDark ? Colors.white38 : Colors.black38),
          ),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final ConversationItem conversation;
  final dynamic strings;
  final bool isDark;
  final int myUserId;
  final Function(ConversationItem)? onOpenChat; // 👈 ADD

  const _ConversationTile({
    required this.conversation,
    required this.strings,
    required this.isDark,
    required this.myUserId,
    this.onOpenChat, // 👈 ADD

  });

  @override
  Widget build(BuildContext context) {
    final hasUnread = conversation.unreadCount > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (onOpenChat != null) {
            // ✅ Bottom sheet mode
            onOpenChat!(conversation);
          } else {
            // ✅ Full screen mode → navigate normally
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  partnerId: conversation.partnerId,
                  partnerName: conversation.partnerName,
                  partnerAvatarUrl: conversation.partnerAvatar,
                  partnerOnline: conversation.partnerOnline,
                ),
              ),
            );
          }
        },

        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // #29/#37: tapping the avatar specifically opens the profile;
              // tapping the rest of the row still opens the chat.
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(userId: conversation.partnerId),
                  ),
                ),
                child: Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: hasUnread
                          ? LinearGradient(
                        colors: [
                          isDark ? AppTheme.accentGold : AppTheme.lightPrimary,
                          isDark ? AppTheme.accentGold.withOpacity(0.5) : AppTheme.lightPrimary.withOpacity(0.5),
                        ],
                      )
                          : null,
                    ),
                    child: CircleAvatar(
                      radius: 28,
                      backgroundColor: isDark ? Colors.white10 : Colors.black12,
                      child: conversation.partnerAvatar != null
                          ? ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: conversation.partnerAvatar!,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          errorWidget: (_, __, ___) => _initialAvatar(),
                        ),
                      )
                          : _initialAvatar(),
                    ),
                  ),
                  if (conversation.partnerOnline)
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: AppTheme.accentGreen,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.partnerName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: hasUnread ? FontWeight.w800 : FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                        if (conversation.lastMessageTime != null)
                          Text(
                            _formatTime(conversation.lastMessageTime!, strings),
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black45),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.lastMessage ?? strings.noMessages,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
                              color: hasUnread
                                  ? (isDark ? Colors.white : Colors.black87)
                                  : (isDark ? Colors.white54 : Colors.black54),
                            ),
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 10),
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: isDark ? AppTheme.accentGold : AppTheme.lightPrimary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _initialAvatar() => Text(
    conversation.partnerName.isNotEmpty ? conversation.partnerName[0].toUpperCase() : '?',
    style: TextStyle(
      fontSize: 22,
      color: isDark ? AppTheme.accentGold : AppTheme.lightPrimary,
      fontWeight: FontWeight.bold,
    ),
  );

  String _formatTime(String timestamp, dynamic strings) {
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final diff = now.difference(dateTime);

      if (diff.inDays > 0) return '${diff.inDays}d';
      if (diff.inHours > 0) return '${diff.inHours}h';
      if (diff.inMinutes > 0) return '${diff.inMinutes}m';
      return strings.justNow;
    } catch (_) {
      return '';
    }
  }
}