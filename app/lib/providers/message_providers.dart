import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/message_events.dart';
import '../repositories/message_repository.dart';
import '../models/conversation_item.dart';
import '../models/direct_message.dart';
import '../models/incoming_message.dart';
import '../services/socket_service.dart';
import 'auth_provider.dart';

final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  return MessageRepository();
});

/// ✅ KEEP (still useful for one-time fetch / pull to refresh)
final conversationsProvider = FutureProvider<List<ConversationItem>>((ref) async {
  final repo = ref.read(messageRepositoryProvider);
  return repo.getConversations();
});

final typingProvider = StreamProvider.autoDispose<TypingEvent>((ref) {
  return SocketService().typingStream; // you must expose this stream
});

final activeChatProvider = StateProvider<ConversationItem?>((ref) => null);

final receiptProvider = StreamProvider.autoDispose<ReceiptEvent>((ref) {
  return SocketService().receiptStream; // you must expose this stream
});

/// ✅ NEW: StreamProvider for incoming DM messages (from SocketService)
final incomingDmProvider = StreamProvider.autoDispose<IncomingMessage>((ref) {
  return SocketService().incomingMessageStream;
});

/// ✅ NEW: realtime conversations list controller
final conversationsControllerProvider = StateNotifierProvider.autoDispose<
    ConversationsController, AsyncValue<List<ConversationItem>>>((ref) {
  final repo = ref.read(messageRepositoryProvider);
  final myUserId = ref.read(authStateProvider).user?.id ?? 0;

  final controller = ConversationsController(repo: repo, myUserId: myUserId);
  controller.load();

  // 🔥 patch list on every incoming DM
  ref.listen(incomingDmProvider, (prev, next) {
    next.whenData(controller.onIncomingMessage);
  });

  // ✅ fallback polling (safe) if backend doesn’t always emit events
  Timer? t;
  t = Timer.periodic(const Duration(seconds: 12), (_) => controller.silentRefresh());
  ref.onDispose(() => t?.cancel());

  return controller;
});

class ConversationsController extends StateNotifier<AsyncValue<List<ConversationItem>>> {
  final MessageRepository repo;
  final int myUserId;

  ConversationsController({required this.repo, required this.myUserId})
      : super(const AsyncValue.loading());

  Future<void> load() async {
    try {
      final list = await repo.getConversations();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> silentRefresh() async {
    try {
      final list = await repo.getConversations();
      state = AsyncValue.data(list);
    } catch (_) {
      // ignore silent errors
    }
  }

  Future<void> markAsRead(int conversationId) async {
    final current = state.value;
    if (current == null) return;

    final updated = current.map((c) {
      if (c.conversationId == conversationId) {
        return c.copyWith(unreadCount: 0);
      }
      return c;
    }).toList();

    state = AsyncValue.data(updated);
  }

  void onIncomingMessage(IncomingMessage m) {
    final current = state.value;
    if (current == null) return;

    final idx = current.indexWhere((c) => c.conversationId == m.conversationId);

    // if conversation not found, refresh once
    if (idx == -1) {
      silentRefresh();
      return;
    }

    final old = current[idx];
    final isMine = m.senderId == myUserId;

    // ✅ You need copyWith in ConversationItem (see section D)
    final updated = old.copyWith(
      lastMessage: m.type == 'image' ? '📷 Photo' : m.text,
      lastMessageTime: m.createdAt,
      unreadCount: isMine ? old.unreadCount : (old.unreadCount + 1),
    );

    // ✅ move to top like Messenger
    final newList = [...current]..removeAt(idx);
    newList.insert(0, updated);

    state = AsyncValue.data(newList);
  }

  /// Optional: call when opening chat
  void markConversationReadLocal(int conversationId) {
    final current = state.value;
    if (current == null) return;
    final idx = current.indexWhere((c) => c.conversationId == conversationId);
    if (idx == -1) return;

    final old = current[idx];
    final updated = old.copyWith(unreadCount: 0);

    final newList = [...current];
    newList[idx] = updated;
    state = AsyncValue.data(newList);
  }
}

/// ✅ param = partnerId (NOT conversationId)
final chatControllerProvider =
StateNotifierProvider.family<ChatController, ChatState, int>((ref, partnerId) {
  final repo = ref.read(messageRepositoryProvider);
  return ChatController(repo, partnerId);
});

class ChatState {
  final bool loading;
  final bool sending;

  final bool loadingMore;
  final bool hasMore;

  final bool partnerTyping;

  final List<DirectMessage> messages;
  final String? error;

  final int partnerId;
  final int? conversationId;

  // Cursor for pagination (oldest message date/id)
  final int? oldestMessageId;
  const ChatState({
    required this.loading,
    required this.sending,
    required this.loadingMore,
    required this.hasMore,
    required this.partnerTyping,
    required this.messages,
    required this.error,
    required this.partnerId,
    required this.conversationId,
    required this.oldestMessageId,  });

  factory ChatState.initial(int partnerId) => ChatState(
    loading: true,
    sending: false,
    loadingMore: false,
    hasMore: true,
    partnerTyping: false,
    messages: const [],
    error: null,
    partnerId: partnerId,
    conversationId: null,
    oldestMessageId: null,
  );

  ChatState copyWith({
    bool? loading,
    bool? sending,
    bool? loadingMore,
    bool? hasMore,
    bool? partnerTyping,
    List<DirectMessage>? messages,
    String? error,
    int? conversationId,
    int? oldestMessageId,
  }) {
    return ChatState(
      loading: loading ?? this.loading,
      sending: sending ?? this.sending,
      loadingMore: loadingMore ?? this.loadingMore,
      hasMore: hasMore ?? this.hasMore,
      partnerTyping: partnerTyping ?? this.partnerTyping,
      messages: messages ?? this.messages,
      error: error,
      partnerId: partnerId,
      conversationId: conversationId ?? this.conversationId,
      oldestMessageId: oldestMessageId ?? this.oldestMessageId,
    );
  }
}

class ChatController extends StateNotifier<ChatState> {
  final MessageRepository _repo;
  final int partnerId;

  StreamSubscription? _incomingSub;
  StreamSubscription? _typingSub;
  StreamSubscription? _receiptSub;

  ChatController(this._repo, this.partnerId) : super(ChatState.initial(partnerId)) {
    load();
    _bindRealtime();
  }

  void _bindRealtime() {
    // Incoming messages
    _incomingSub = SocketService().incomingMessageStream.listen((m) async {
      final cid = state.conversationId;
      if (cid == null) return;
      if (m.conversationId != cid) return;



      final dm = DirectMessage(
        id: m.id, // ✅ use socket message id
        clientId: 'srv_${m.id}',
        conversationId: m.conversationId,
        senderId: m.senderId,
        text: m.text,
        type: m.type,
        createdAt: m.createdAt,
        deliveredAt: null,
        readAt: null,

        // ✅ required new fields (safe defaults)
        reactions: const {},
        myReaction: null,
        audioUrl: m.audioUrl,
        pinnedAt: null,

        localStatus: LocalMsgStatus.sent,
      );

// de-dupe by createdAt + senderId + text
      final exists = state.messages.any((x) =>
      x.senderId == dm.senderId &&
          x.createdAt == dm.createdAt &&
          x.text == dm.text &&
          x.conversationId == dm.conversationId
      );
      if (exists) return;

      state = state.copyWith(
        messages: [...state.messages, dm],
        error: null,
      );

      // ✅ if chat is open, instantly mark read (production behavior)
      await _repo.markConversationRead(cid);
    });

    // Typing
    _typingSub = SocketService().typingStream.listen((e) {
      final cid = state.conversationId;
      if (cid == null) return;
      if (e.conversationId != cid) return;

      state = state.copyWith(partnerTyping: e.isTyping);
    });

    // Receipts (delivered/read)
    _receiptSub = SocketService().receiptStream.listen((r) {
      final cid = state.conversationId;
      if (cid == null) return;
      if (r.conversationId != cid) return;

      final updated = state.messages.map((m) {
        if (m.id != r.messageId) return m;
        if (r.type == 'delivered') return m.copyWith(deliveredAt: r.at);
        if (r.type == 'read') return m.copyWith(readAt: r.at);
        return m;
      }).toList();

      state = state.copyWith(messages: updated);
    });
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    _typingSub?.cancel();
    _receiptSub?.cancel();
    super.dispose();
  }

  // inside ChatController

  Future<void> react({
    required int messageId,
    required String emoji,
    required int myUserId,
  }) async {
    // 1) optimistic update UI
    final updated = state.messages.map((m) {
      if (m.id != messageId) return m;

      final nextReactions = Map<String, int>.from(m.reactions);
      nextReactions[emoji] = (nextReactions[emoji] ?? 0) + 1;

      return m.copyWith(
        reactions: nextReactions,
        myReaction: emoji,
      );
    }).toList();

    state = state.copyWith(messages: updated);

    // 2) call backend (repo)
    try {
      await _repo.reactToMessage(messageId: messageId, emoji: emoji);
    } catch (e) {
      // optional: rollback (simple)
      // For now just ignore to keep UI responsive
    }
  }

  Future<void> deleteMessage(int messageId) async {
    // optimistic remove
    final before = state.messages;
    state = state.copyWith(
      messages: state.messages.where((m) => m.id != messageId).toList(),
    );

    try {
      await _repo.deleteMessage(messageId);
    } catch (e) {
      // rollback on failure
      state = state.copyWith(messages: before);
    }
  }

  Future<void> sendVoice(String filePath) async {
    final cid = state.conversationId;
    if (cid == null) throw Exception('Conversation not ready');

    // 1) upload audio -> get url (you already have uploadVoiceNote)
    final audioUrl = await _repo.uploadVoiceNote(filePath);

    // 2) send voice message using the method that supports audioUrl
    final sent = await _repo.sendVoiceMessage(
      conversationId: cid,
      audioUrl: audioUrl,
    );

    // 3) append message
    state = state.copyWith(messages: [...state.messages, sent]);
  }

  Future<void> load() async {
    try {
      state = state.copyWith(loading: true, error: null);

      final convo = await _repo.getOrCreateConversation(partnerId);
      final cid = convo.conversationId;

      final msgs = await _repo.getMessages(cid);

      final oldestId = msgs.isNotEmpty ? msgs.first.id : null;

      state = state.copyWith(
        loading: false,
        messages: msgs.map((m) => m.copyWith(localStatus: LocalMsgStatus.sent)).toList(),
        conversationId: cid,
        oldestMessageId: oldestId,
        hasMore: msgs.length >= 20,
      );

      await _repo.markConversationRead(cid);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// ✅ Pull to refresh (re-fetch latest)
  Future<void> refresh() async {
    final cid = state.conversationId;
    if (cid == null) return;
    try {
      final msgs = await _repo.getMessages(cid);
      final oldestId = msgs.isNotEmpty ? msgs.first.id : null;
      state = state.copyWith(
        messages: msgs,
        oldestMessageId: oldestId,
        hasMore: msgs.length >= 20,
        error: null,
      );
      await _repo.markConversationRead(cid);
    } catch (_) {}
  }

  /// ✅ Pagination (older messages)
  Future<void> loadMore() async {
    final cid = state.conversationId;
    if (cid == null) return;
    if (state.loadingMore || !state.hasMore) return;

    try {
      state = state.copyWith(loadingMore: true);

      final beforeId = state.oldestMessageId;
      if (beforeId == null || beforeId <= 0) {
        state = state.copyWith(loadingMore: false, hasMore: false);
        return;
      }

      final older = await _repo.getMessagesBefore(
        conversationId: cid,
        beforeId: beforeId,
        limit: 20,
      );

      if (older.isEmpty) {
        state = state.copyWith(loadingMore: false, hasMore: false);
        return;
      }

      // De-dupe by id to avoid duplicates
      final existingIds = state.messages.map((m) => m.id).toSet();
      final filteredOlder = older.where((m) => !existingIds.contains(m.id)).toList();

      final merged = [...filteredOlder, ...state.messages];

      state = state.copyWith(
        loadingMore: false,
        messages: merged,
        oldestMessageId: merged.isNotEmpty ? merged.first.id : beforeId,
        hasMore: older.length >= 20,
      );
    } catch (e) {
      state = state.copyWith(loadingMore: false, error: e.toString());
    }
  }

  /// ✅ Send typing (throttle on UI side)
  Future<void> setTyping(bool typing, {required int myUserId}) async {
    final cid = state.conversationId;
    if (cid == null) return;
    await _repo.sendTyping(conversationId: cid, isTyping: typing);
  }

  Future<void> send(String text, {required int myUserId}) async {
    final clean = text.trim();
    if (clean.isEmpty || state.sending) return;

    final cid = state.conversationId;
    if (cid == null) {
      state = state.copyWith(error: 'Conversation not ready yet. Try again.');
      return;
    }

    final clientId = 'c_${DateTime.now().microsecondsSinceEpoch}';

    final tempId = -DateTime.now().millisecondsSinceEpoch;

    final optimistic = DirectMessage(
      id: tempId,
      clientId: clientId,
      conversationId: cid,
      senderId: myUserId,
      text: clean,
      type: 'text',
      createdAt: DateTime.now().toIso8601String(),
      deliveredAt: null,
      readAt: null,

      // ✅ required new fields (safe defaults)
      reactions: const {},
      myReaction: null,
      audioUrl: null,
      pinnedAt: null,

      localStatus: LocalMsgStatus.sending,
    );

    state = state.copyWith(
      sending: true,
      messages: [...state.messages, optimistic],
      error: null,
    );

    try {
      final created = await _repo.sendMessage(
        conversationId: cid,
        text: clean,
        clientId: clientId, // optional: backend can store it for de-dupe
      );

      final updated = state.messages.map((m) {
        if (m.clientId != clientId) return m;
        return created.copyWith(clientId: clientId, localStatus: LocalMsgStatus.sent);
      }).toList();

      state = state.copyWith(sending: false, messages: updated);
    } catch (e) {
      final updated = state.messages.map((m) {
        if (m.clientId != clientId) return m;
        return m.copyWith(localStatus: LocalMsgStatus.failed);
      }).toList();

      state = state.copyWith(sending: false, messages: updated, error: e.toString());
    }
  }

  /// ✅ Retry failed message
  Future<void> retrySend(String clientId, {required int myUserId}) async {
    final m = state.messages.where((x) => x.clientId == clientId).toList();
    if (m.isEmpty) return;

    final msg = m.first;
    if (msg.localStatus != LocalMsgStatus.failed) return;

    // mark sending
    state = state.copyWith(
      messages: state.messages.map((x) {
        if (x.clientId != clientId) return x;
        return x.copyWith(localStatus: LocalMsgStatus.sending);
      }).toList(),
      error: null,
    );

    try {
      final cid = state.conversationId;
      if (cid == null) throw Exception('Conversation not ready');

      final created = await _repo.sendMessage(
        conversationId: cid,
        text: msg.text,
        clientId: clientId,
      );

      state = state.copyWith(
        messages: state.messages.map((x) {
          if (x.clientId != clientId) return x;
          return created.copyWith(clientId: clientId, localStatus: LocalMsgStatus.sent);
        }).toList(),
      );
    } catch (e) {
      state = state.copyWith(
        messages: state.messages.map((x) {
          if (x.clientId != clientId) return x;
          return x.copyWith(localStatus: LocalMsgStatus.failed);
        }).toList(),
        error: e.toString(),
      );
    }
  }
}