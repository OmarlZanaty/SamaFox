enum LocalMsgStatus { sending, sent, failed }

class DirectMessage {
  final int id; // server id (or temp negative)
  final String clientId; // stable local id for optimistic/retry
  final int conversationId;
  final int senderId;

  final String text;
  final String type; // text | image | voice | system
  final String createdAt; // ISO

  final String? deliveredAt;
  final String? readAt;

  // ✅ NEW production features
  final Map<String, int> reactions; // emoji -> count
  final String? myReaction;         // my selected emoji (if backend returns)
  final String? audioUrl;           // for voice message
  final String? pinnedAt;           // for pinned messages

  final LocalMsgStatus localStatus;

  const DirectMessage({
    required this.id,
    required this.clientId,
    required this.conversationId,
    required this.senderId,
    required this.text,
    required this.type,
    required this.createdAt,
    required this.deliveredAt,
    required this.readAt,
    required this.reactions,
    required this.myReaction,
    required this.audioUrl,
    required this.pinnedAt,
    required this.localStatus,
  });

  DirectMessage copyWith({
    int? id,
    String? clientId,
    int? conversationId,
    int? senderId,
    String? text,
    String? type,
    String? createdAt,
    String? deliveredAt,
    String? readAt,
    Map<String, int>? reactions,
    String? myReaction,
    String? audioUrl,
    String? pinnedAt,
    LocalMsgStatus? localStatus,
  }) {
    return DirectMessage(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      readAt: readAt ?? this.readAt,
      reactions: reactions ?? this.reactions,
      myReaction: myReaction ?? this.myReaction,
      audioUrl: audioUrl ?? this.audioUrl,
      pinnedAt: pinnedAt ?? this.pinnedAt,
      localStatus: localStatus ?? this.localStatus,
    );
  }

  factory DirectMessage.fromJson(Map<String, dynamic> j) {
    int _i(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('$v') ?? 0;
    }

    final rawReactions = j['reactions'];
    final Map<String, int> reactions = (rawReactions is Map)
        ? rawReactions.map((k, v) => MapEntry('$k', (v is num) ? v.toInt() : int.tryParse('$v') ?? 0))
        : <String, int>{};

    final id = _i(j['id'] ?? j['messageId']);
    final clientId = (j['clientId'] ?? 'srv_$id').toString();

    return DirectMessage(
      id: id,
      clientId: clientId,
      conversationId: _i(j['conversationId']),
      senderId: _i(j['senderId']),
      text: (j['text'] ?? j['content'] ?? '') as String,
      type: (j['type'] ?? 'text') as String,
      createdAt: (j['createdAt'] ?? DateTime.now().toIso8601String()) as String,
      deliveredAt: j['deliveredAt'] as String?,
      readAt: j['readAt'] as String?,
      reactions: reactions,
      myReaction: j['myReaction'] as String?,
      audioUrl: j['audioUrl'] as String? ?? j['voiceUrl'] as String?,
      pinnedAt: j['pinnedAt'] as String?,
      localStatus: LocalMsgStatus.sent, // server messages already sent
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'clientId': clientId,
    'conversationId': conversationId,
    'senderId': senderId,
    'text': text,
    'type': type,
    'createdAt': createdAt,
    'deliveredAt': deliveredAt,
    'readAt': readAt,
    'reactions': reactions,
    'myReaction': myReaction,
    'audioUrl': audioUrl,
    'pinnedAt': pinnedAt,
  };
}