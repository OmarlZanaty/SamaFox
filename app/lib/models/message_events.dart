class TypingEvent {
  final int conversationId;
  final int userId;
  final bool isTyping;

  TypingEvent({
    required this.conversationId,
    required this.userId,
    required this.isTyping,
  });

  factory TypingEvent.fromJson(Map<String, dynamic> j) => TypingEvent(
    conversationId: (j['conversationId'] ?? 0) as int,
    userId: (j['userId'] ?? 0) as int,
    isTyping: (j['isTyping'] ?? false) as bool,
  );
}

class ReceiptEvent {
  final int conversationId;
  final int messageId;
  final String type; // delivered | read
  final String at; // ISO

  ReceiptEvent({
    required this.conversationId,
    required this.messageId,
    required this.type,
    required this.at,
  });

  factory ReceiptEvent.fromJson(Map<String, dynamic> j) => ReceiptEvent(
    conversationId: (j['conversationId'] ?? 0) as int,
    messageId: (j['messageId'] ?? 0) as int,
    type: (j['type'] ?? 'delivered') as String,
    at: (j['at'] ?? DateTime.now().toIso8601String()) as String,
  );
}