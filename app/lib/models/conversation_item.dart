class ConversationItem {
  final int conversationId;
  final int partnerId;
  final String partnerName;
  final String? partnerAvatar;
  final bool partnerOnline;
  int get id => conversationId;
  final String? lastMessage;
  final String? lastMessageTime; // ISO string
  final int unreadCount;

  ConversationItem({
    required this.conversationId,
    required this.partnerId,
    required this.partnerName,
    required this.partnerAvatar,
    required this.partnerOnline,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.unreadCount,
  });

  factory ConversationItem.fromJson(Map<String, dynamic> j) {
    return ConversationItem(
      conversationId: (j['conversationId'] ?? j['id'] ?? 0) as int,
      partnerId: (j['partnerId'] ?? 0) as int,
      partnerName: (j['partnerName'] ?? 'Unknown') as String,
      partnerAvatar: j['partnerAvatar'] as String?,
      partnerOnline: (j['partnerOnline'] ?? false) as bool,
      lastMessage: j['lastMessage'] as String?,
      lastMessageTime: j['lastMessageAt'] as String? ?? j['lastMessageTime'] as String?,
      unreadCount: (j['unreadCount'] ?? 0) as int,
    );
  }
}
extension ConversationItemCopy on ConversationItem {
  ConversationItem copyWith({
    String? lastMessage,
    String? lastMessageTime,
    int? unreadCount,
    bool? partnerOnline,
    String? partnerName,
    String? partnerAvatar,
  }) {
    return ConversationItem(
      conversationId: conversationId,
      partnerId: partnerId,
      partnerName: partnerName ?? this.partnerName,
      partnerAvatar: partnerAvatar ?? this.partnerAvatar,
      partnerOnline: partnerOnline ?? this.partnerOnline,
      unreadCount: unreadCount ?? this.unreadCount,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      // include any other fields you have in constructor (muted, etc.)
    );
  }
}