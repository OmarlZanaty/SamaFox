import 'package:json_annotation/json_annotation.dart';

import 'room.dart';
import 'gift.dart';
import 'message.dart';
import 'user.dart';

part 'api_response.g.dart';

@JsonSerializable()
class RoomsResponse {
  final List<Room> rooms;
  final Pagination? pagination;

  RoomsResponse({
    required this.rooms,
    this.pagination,
  });

  factory RoomsResponse.fromJson(Map<String, dynamic> json) =>
      _$RoomsResponseFromJson(json);

  Map<String, dynamic> toJson() => _$RoomsResponseToJson(this);
}

@JsonSerializable()
class Pagination {
  @JsonKey(defaultValue: 1)
  final int page;

  @JsonKey(defaultValue: 20)
  final int limit;

  @JsonKey(defaultValue: 0)
  final int total;

  @JsonKey(defaultValue: 0)
  final int totalPages;

  Pagination({
    this.page = 1,
    this.limit = 20,
    this.total = 0,
    this.totalPages = 0,
  });

  factory Pagination.fromJson(Map<String, dynamic> json) =>
      _$PaginationFromJson(json);

  Map<String, dynamic> toJson() => _$PaginationToJson(this);
}

@JsonSerializable()
class GiftsResponse {
  final List<Gift> gifts;

  /// backend may omit total
  @JsonKey(defaultValue: 0)
  final int total;

  GiftsResponse({
    required this.gifts,
    this.total = 0,
  });

  int get safeTotal => total == 0 ? gifts.length : total;

  factory GiftsResponse.fromJson(Map<String, dynamic> json) =>
      _$GiftsResponseFromJson(json);

  Map<String, dynamic> toJson() => _$GiftsResponseToJson(this);
}

@JsonSerializable()
class ConversationsResponse {
  final List<ConversationItem> conversations;

  ConversationsResponse({required this.conversations});

  factory ConversationsResponse.fromJson(Map<String, dynamic> json) =>
      _$ConversationsResponseFromJson(json);

  Map<String, dynamic> toJson() => _$ConversationsResponseToJson(this);
}

@JsonSerializable()
class MessagesResponse {
  final List<Message> messages;

  MessagesResponse({required this.messages});

  factory MessagesResponse.fromJson(Map<String, dynamic> json) =>
      _$MessagesResponseFromJson(json);

  Map<String, dynamic> toJson() => _$MessagesResponseToJson(this);
}

@JsonSerializable()
class RoomMessagesResponse {
  final List<RoomMessage> messages;

  RoomMessagesResponse({required this.messages});

  factory RoomMessagesResponse.fromJson(Map<String, dynamic> json) =>
      _$RoomMessagesResponseFromJson(json);

  Map<String, dynamic> toJson() => _$RoomMessagesResponseToJson(this);
}

@JsonSerializable()
class UsersListResponse {
  final List<User> users;

  UsersListResponse({required this.users});

  factory UsersListResponse.fromJson(Map<String, dynamic> json) =>
      _$UsersListResponseFromJson(json);

  Map<String, dynamic> toJson() => _$UsersListResponseToJson(this);
}

@JsonSerializable()
class MessageResponse {
  final String message;

  /// backend may omit success
  @JsonKey(defaultValue: true)
  final bool success;

  MessageResponse({
    required this.message,
    this.success = true,
  });

  factory MessageResponse.fromJson(Map<String, dynamic> json) =>
      _$MessageResponseFromJson(json);

  Map<String, dynamic> toJson() => _$MessageResponseToJson(this);
}
