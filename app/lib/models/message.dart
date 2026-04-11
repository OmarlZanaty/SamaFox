import 'package:json_annotation/json_annotation.dart';

part 'message.g.dart';

@JsonSerializable()
class Message {
  final int id;
  @JsonKey(name: 'sender_id')
  final int senderId;
  @JsonKey(name: 'receiver_id')
  final int receiverId;
  final String content;
  final String type;
  @JsonKey(name: 'is_read')
  final bool isRead;
  @JsonKey(name: 'created_at')
  final String? createdAt;
  @JsonKey(name: 'sender_name')
  final String? senderName;
  @JsonKey(name: 'sender_avatar')
  final String? senderAvatar;

  Message({
    this.id = 0,
    required this.senderId,
    required this.receiverId,
    required this.content,
    this.type = 'text',
    this.isRead = false,
    this.createdAt,
    this.senderName,
    this.senderAvatar,
  });

  factory Message.fromJson(Map<String, dynamic> json) =>
      _$MessageFromJson(json);
  Map<String, dynamic> toJson() => _$MessageToJson(this);
}

@JsonSerializable()
class RoomMessage {
  final int id;
  @JsonKey(name: 'room_id')
  final int roomId;
  @JsonKey(name: 'user_id')
  final int userId;
  final String username;
  final String content;
  final int? timestamp;
  final String? avatar;
  @JsonKey(name: 'created_at')
  final String? createdAt;

  RoomMessage({
    this.id = 0,
    required this.roomId,
    required this.userId,
    required this.username,
    required this.content,
    this.timestamp,
    this.avatar,
    this.createdAt,
  });

  factory RoomMessage.fromJson(Map<String, dynamic> json) =>
      _$RoomMessageFromJson(json);
  Map<String, dynamic> toJson() => _$RoomMessageToJson(this);
}

@JsonSerializable()
class ConversationItem {
  final int id;
  @JsonKey(name: 'partner_id')
  final int partnerId;
  @JsonKey(name: 'partner_name')
  final String partnerName;
  @JsonKey(name: 'partner_avatar')
  final String? partnerAvatar;
  @JsonKey(name: 'partner_online')
  final bool partnerOnline;
  @JsonKey(name: 'last_message')
  final String? lastMessage;
  @JsonKey(name: 'last_message_sender_id')
  final int? lastMessageSenderId;
  @JsonKey(name: 'last_message_time')
  final String? lastMessageTime;
  @JsonKey(name: 'unread_count')
  final int unreadCount;

  ConversationItem({
    required this.id,
    required this.partnerId,
    required this.partnerName,
    this.partnerAvatar,
    this.partnerOnline = false,
    this.lastMessage,
    this.lastMessageSenderId,
    this.lastMessageTime,
    this.unreadCount = 0,
  });

  factory ConversationItem.fromJson(Map<String, dynamic> json) =>
      _$ConversationItemFromJson(json);
  Map<String, dynamic> toJson() => _$ConversationItemToJson(this);
}

@JsonSerializable()
class SendMessageRequest {
  final int receiverId;
  final String content;
  final String type;

  SendMessageRequest({
    required this.receiverId,
    required this.content,
    this.type = 'text',
  });

  factory SendMessageRequest.fromJson(Map<String, dynamic> json) =>
      _$SendMessageRequestFromJson(json);
  Map<String, dynamic> toJson() => _$SendMessageRequestToJson(this);
}
