import 'dart:convert';

import 'package:retrofit/retrofit.dart';
import 'package:dio/dio.dart';

import '../models/InventoryItem.dart';
import '../models/auth.dart';
import '../models/gift_history.dart';
import '../models/room.dart';
import '../models/gift.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../models/api_response.dart';
import '../models/game.dart';

part 'api_service.g.dart';

@RestApi()
abstract class ApiService {
  factory ApiService(Dio dio, {String baseUrl}) = _ApiService;

  // ==================== AUTH ENDPOINTS ====================

  @POST('auth/guest')
  Future<GuestLoginResponse> guestLogin(@Body() GuestLoginRequest request);

  @POST('auth/register')
  Future<AuthResponse> register(@Body() RegisterRequest request);

  @POST('auth/login')
  Future<AuthResponse> login(@Body() LoginRequest request);

  @POST('auth/google/mobile')
  Future<AuthResponse> googleLogin(@Body() GoogleLoginRequest request);

  @POST("auth/facebook")
  Future<AuthResponse> facebookLogin(@Body() FacebookLoginRequest request);

  @GET('auth/user/{id}')
  Future<User> getUserProfile(@Path('id') int userId);

  @POST('auth/refresh')
  Future<AuthResponse> refreshToken(@Body() Map<String, dynamic> request);

  @GET('store/inventory')
  Future<dynamic> getInventory();

  @POST('store/activate')
  Future<dynamic> activateItem(
      @Body() Map<String, dynamic> body,
      );

  // ==================== ROOM ENDPOINTS ====================

  @GET('rooms')
  Future<RoomsResponse> getRooms({
    @Query('page') int page = 1,
    @Query('limit') int limit = 20,
  });

  @POST('room-admin/kick')
  Future<MessageResponse> kickUser(@Body() Map<String, dynamic> request);

  @GET('rooms/{id}')
  Future<Room> getRoomById(@Path('id') int roomId);

  @POST('rooms')
  Future<Room> createRoom(@Body() CreateRoomRequest request);

  @PUT('rooms/{id}')
  Future<MessageResponse> updateRoom(@Path('id') int roomId,
      @Body() UpdateRoomRequest request,);

  @DELETE('rooms/{id}')
  Future<MessageResponse> deleteRoom(@Path('id') int roomId);

  @POST('rooms/{id}/join')
  Future<MessageResponse> joinRoom(@Path('id') int roomId,
      @Body() Map<String, dynamic> request,);

  @POST('rooms/{id}/leave')
  Future<MessageResponse> leaveRoom(@Path('id') int roomId,
      @Body() Map<String, dynamic> request,);

  @GET('rooms/{id}/messages')
  Future<List<RoomMessage>> getRoomMessages(@Path('id') int roomId,
      {@Query('limit') int limit = 50,
        @Query('offset') int offset = 0});

  // ==================== MESSAGE ENDPOINTS ====================

  @GET('messages/conversations')
  Future<ConversationsResponse> getConversations();

  @GET('messages/{userId}')
  Future<MessagesResponse> getMessages(@Path('userId') int userId, {
    @Query('limit') int limit = 50,
    @Query('offset') int offset = 0,
  });

  @POST('messages')
  Future<MessageResponse> sendMessage(@Body() SendMessageRequest request);

  @PUT('messages/{messageId}/read')
  Future<MessageResponse> markMessageAsRead(@Path('messageId') int messageId);

  @DELETE('messages/{messageId}')
  Future<MessageResponse> deleteMessage(@Path('messageId') int messageId);

  // ==================== GIFT ENDPOINTS ====================

  @GET('gifts')
  Future<GiftsResponse> getGifts({@Query('category') String? category});

  @GET('gifts/history')
  Future<GiftHistoryResponse> getGiftHistory({
    @Query('page') int page = 1,
    @Query('limit') int limit = 20,
  });


  @POST('gifts/send')
  Future<MessageResponse> sendGift(@Body() SendGiftRequest request);

  // ==================== USER ENDPOINTS ====================

  @GET('users/me')
  Future<User> getCurrentUser();

  @GET('users/{userId}')
  Future<User> getUserById(@Path('userId') int userId);

  @PUT('users/profile')
  Future<User> updateProfile(@Body() Map<String, dynamic> request);

  @PUT('users/me')
  Future<User> updateProfileMe(@Body() Map<String, dynamic> request);

  @POST('users/{userId}/follow')
  Future<MessageResponse> followUser(@Path('userId') int userId);

  @DELETE('users/{userId}/follow')
  Future<MessageResponse> unfollowUser(@Path('userId') int userId);

  @GET('users/{userId}/followers')
  Future<UsersListResponse> getFollowers(@Path('userId') int userId);

  @GET('users/{userId}/following')
  Future<UsersListResponse> getFollowing(@Path('userId') int userId);

  @GET('users/search')
  Future<UsersListResponse> searchUsers(@Query('query') String query);

  @GET('users/country/{countryCode}')
  Future<UsersListResponse> getUsersByCountry(
      @Path('countryCode') String countryCode,
      );


  // ==================== GAME ENDPOINTS ====================

  @POST('games/dice/play')
  Future<DiceRollResponse> playDice();

  @GET('games/leaderboard')
  Future<LeaderboardResponse> getLeaderboard();

  @GET('games/stats/{userId}')
  Future<GameStats> getUserGameStats(@Path('userId') int userId);

  // ==================== ROOM ADMIN ENDPOINTS ====================

  @POST('room-admin/add-admin')
  Future<MessageResponse> addRoomAdmin(@Body() Map<String, dynamic> request);

  @POST('room-admin/remove-admin')
  Future<MessageResponse> removeRoomAdmin(@Body() Map<String, dynamic> request);

  @GET('room-admin/{roomId}/admins')
  Future<List<RoomMember>> getRoomAdmins(@Path('roomId') int roomId);

  @POST('room-admin/mute')
  Future<MessageResponse> muteUser(@Body() Map<String, dynamic> request);

  @POST('room-admin/ban')
  Future<MessageResponse> banUser(@Body() Map<String, dynamic> request);

  @POST('room-admin/unban')
  Future<MessageResponse> unbanUser(@Body() Map<String, dynamic> request);

  @GET('room-admin/{roomId}/bans')
  Future<dynamic> getBanList(@Path('roomId') int roomId);

  @POST('room-admin/lock')
  Future<MessageResponse> toggleRoomLock(@Body() Map<String, dynamic> request);

  @POST('room-admin/max-seats')
  Future<MessageResponse> updateMaxSeats(@Body() Map<String, dynamic> request);

  @POST('room-admin/background-music')
  Future<MessageResponse> setBackgroundMusic(@Body() Map<String, dynamic> request);

  @POST('room-admin/background-image')
  Future<MessageResponse> updateRoomBackground(@Body() Map<String, dynamic> request);

  @POST('room-admin/sound-settings')
  Future<MessageResponse> toggleSoundSettings(@Body() Map<String, dynamic> request);

  @POST('room-admin/clear-chat')
  Future<MessageResponse> clearChat(@Body() Map<String, dynamic> request);

}
