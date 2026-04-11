// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Message _$MessageFromJson(Map<String, dynamic> json) => Message(
      id: (json['id'] as num?)?.toInt() ?? 0,
      senderId: (json['sender_id'] as num).toInt(),
      receiverId: (json['receiver_id'] as num).toInt(),
      content: json['content'] as String,
      type: json['type'] as String? ?? 'text',
      isRead: json['is_read'] as bool? ?? false,
      createdAt: json['created_at'] as String?,
      senderName: json['sender_name'] as String?,
      senderAvatar: json['sender_avatar'] as String?,
    );

Map<String, dynamic> _$MessageToJson(Message instance) => <String, dynamic>{
      'id': instance.id,
      'sender_id': instance.senderId,
      'receiver_id': instance.receiverId,
      'content': instance.content,
      'type': instance.type,
      'is_read': instance.isRead,
      'created_at': instance.createdAt,
      'sender_name': instance.senderName,
      'sender_avatar': instance.senderAvatar,
    };

RoomMessage _$RoomMessageFromJson(Map<String, dynamic> json) => RoomMessage(
      id: (json['id'] as num?)?.toInt() ?? 0,
      roomId: (json['room_id'] as num).toInt(),
      userId: (json['user_id'] as num).toInt(),
      username: json['username'] as String,
      content: json['content'] as String,
      timestamp: (json['timestamp'] as num?)?.toInt(),
      avatar: json['avatar'] as String?,
      createdAt: json['created_at'] as String?,
    );

Map<String, dynamic> _$RoomMessageToJson(RoomMessage instance) =>
    <String, dynamic>{
      'id': instance.id,
      'room_id': instance.roomId,
      'user_id': instance.userId,
      'username': instance.username,
      'content': instance.content,
      'timestamp': instance.timestamp,
      'avatar': instance.avatar,
      'created_at': instance.createdAt,
    };

ConversationItem _$ConversationItemFromJson(Map<String, dynamic> json) =>
    ConversationItem(
      id: (json['id'] as num).toInt(),
      partnerId: (json['partner_id'] as num).toInt(),
      partnerName: json['partner_name'] as String,
      partnerAvatar: json['partner_avatar'] as String?,
      partnerOnline: json['partner_online'] as bool? ?? false,
      lastMessage: json['last_message'] as String?,
      lastMessageSenderId: (json['last_message_sender_id'] as num?)?.toInt(),
      lastMessageTime: json['last_message_time'] as String?,
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$ConversationItemToJson(ConversationItem instance) =>
    <String, dynamic>{
      'id': instance.id,
      'partner_id': instance.partnerId,
      'partner_name': instance.partnerName,
      'partner_avatar': instance.partnerAvatar,
      'partner_online': instance.partnerOnline,
      'last_message': instance.lastMessage,
      'last_message_sender_id': instance.lastMessageSenderId,
      'last_message_time': instance.lastMessageTime,
      'unread_count': instance.unreadCount,
    };

SendMessageRequest _$SendMessageRequestFromJson(Map<String, dynamic> json) =>
    SendMessageRequest(
      receiverId: (json['receiverId'] as num).toInt(),
      content: json['content'] as String,
      type: json['type'] as String? ?? 'text',
    );

Map<String, dynamic> _$SendMessageRequestToJson(SendMessageRequest instance) =>
    <String, dynamic>{
      'receiverId': instance.receiverId,
      'content': instance.content,
      'type': instance.type,
    };
