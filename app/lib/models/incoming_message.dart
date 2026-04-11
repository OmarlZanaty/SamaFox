class IncomingMessage {
  final int id; // ✅ NEW
  final int conversationId;
  final int senderId;
  final String text;
  final String type; // text | image | voice
  final String createdAt;
  final String? audioUrl; // ✅ for voice
  final Map<String, dynamic>? sender;

  IncomingMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.text,
    required this.type,
    required this.createdAt,
    this.audioUrl,
    this.sender,
  });

  factory IncomingMessage.fromJson(Map<String, dynamic> json) {
    int _i(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('$v') ?? 0;
    }

    return IncomingMessage(
      id: _i(json['id'] ?? json['messageId']),
      conversationId: _i(json['conversationId'] ?? json['cid']),
      senderId: _i(json['senderId'] ?? json['userId']),
      text: (json['text'] ?? json['content'] ?? '') as String,
      type: (json['type'] ?? 'text') as String,
      createdAt: (json['createdAt'] ?? DateTime.now().toIso8601String()) as String,
      audioUrl: json['audioUrl'] as String? ?? json['voiceUrl'] as String?,
      sender: json['sender'] is Map<String, dynamic> ? (json['sender'] as Map<String, dynamic>) : null,
    );
  }
}