import 'dart:io';

import '../models/conversation_item.dart';
import '../models/direct_message.dart';
import '../services/dio_client.dart';
import 'package:dio/dio.dart';

class MessageRepository {
  final _dio = DioClient.dio;

  // ✅ baseUrl already contains /api/v1
  static const _base = '/messages';


  Future<List<ConversationItem>> getConversations() async {
    final res = await _dio.get('$_base/conversations');
    final data = res.data;

    final list = (data is Map && data['data'] is List)
        ? (data['data'] as List)
        : (data is List ? data : <dynamic>[]);

    return list.map((e) => ConversationItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ConversationItem> getOrCreateConversation(int partnerId) async {
    final res = await _dio.post('$_base/conversation', data: {'partnerId': partnerId});
    final data = (res.data as Map).cast<String, dynamic>();
    return ConversationItem.fromJson(data);
  }

  Future<void> reactToMessage({
    required int messageId,
    required String emoji, // ❤️😂🔥
  }) async {
    await _dio.post('$_base/messages/$messageId/react', data: {'emoji': emoji});
  }


  Future<List<DirectMessage>> getMessages(
      int conversationId, {
        int limit = 50,
        int? beforeId,
      }) async {
    final res = await _dio.get(
      '$_base/conversations/$conversationId/messages',
      queryParameters: {'limit': limit, if (beforeId != null) 'beforeId': beforeId},
    );

    final data = res.data;
    final list = (data is Map && data['data'] is List)
        ? (data['data'] as List)
        : (data is List ? data : <dynamic>[]);

    return list.map((e) => DirectMessage.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// ✅ unified sendMessage (supports text + image + clientId for retry)
  Future<DirectMessage> sendMessage({
    required int conversationId,
    required String text,
    String type = 'text',
    String? imageUrl,
    String? clientId,
  }) async {
    final res = await _dio.post('$_base/send', data: {
      'conversationId': conversationId,
      'text': text,
      'type': type,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (clientId != null) 'clientId': clientId,
    });

    final data = (res.data as Map).cast<String, dynamic>();
    return DirectMessage.fromJson(data);
  }

  Future<void> markConversationRead(int conversationId) async {
    await _dio.post('$_base/conversations/$conversationId/read');
  }

  Future<String> uploadVoiceNote(String filePath) async {
    // multipart upload
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: 'voice.m4a'),
    });

    final res = await _dio.post('$_base/upload-audio', data: form);
    final data = (res.data as Map).cast<String, dynamic>();
    return (data['audioUrl'] ?? data['url'] ?? '') as String;
  }

  Future<void> pinMessage(int messageId) async {
    await _dio.post('$_base/messages/$messageId/pin');
  }
  Future<void> unpinMessage(int messageId) async {
    await _dio.post('$_base/messages/$messageId/unpin');
  }

  Future<List<DirectMessage>> getPinnedMessages(int conversationId) async {
    final res = await _dio.get('$_base/conversations/$conversationId/pins');
    final data = res.data;
    final list = (data is Map && data['data'] is List) ? (data['data'] as List) : (data as List? ?? []);
    return list.map((e) => DirectMessage.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<List<DirectMessage>> searchMessages({
    required int conversationId,
    required String q,
    int limit = 30,
  }) async {
    final res = await _dio.get('$_base/conversations/$conversationId/search', queryParameters: {'q': q, 'limit': limit});
    final data = res.data;
    final list = (data is Map && data['data'] is List) ? (data['data'] as List) : (data as List? ?? []);
    return list.map((e) => DirectMessage.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<DirectMessage> sendVoiceMessage({
    required int conversationId,
    required String audioUrl,
    String? clientId,
  }) async {
    final res = await _dio.post('$_base/send', data: {
      'conversationId': conversationId,
      'type': 'voice',
      'audioUrl': audioUrl,
      if (clientId != null) 'clientId': clientId,
    });
    final data = (res.data as Map).cast<String, dynamic>();
    return DirectMessage.fromJson(data);
  }

  /// ✅ Pagination using your backend style (beforeId exists already)
  /// We'll use beforeId instead of beforeCreatedAt to avoid backend changes.
  Future<List<DirectMessage>> getMessagesBefore({
    required int conversationId,
    required int beforeId,
    int limit = 20,
  }) async {
    return getMessages(conversationId, limit: limit, beforeId: beforeId);
  }

  /// ✅ DM typing event (HTTP fallback if needed)
  /// If your backend expects socket-only typing, you can remove this and emit via SocketService instead.
  Future<void> sendTyping({
    required int conversationId,
    required bool isTyping,
  }) async {
    await _dio.post('$_base/conversations/$conversationId/typing', data: {
      'isTyping': isTyping,
    });
  }

  Future<void> deleteMessage(int messageId) async {
    await _dio.delete('$_base/messages/$messageId');
  }

}