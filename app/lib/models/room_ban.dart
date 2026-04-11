import 'package:json_annotation/json_annotation.dart';
import 'user.dart';

part 'room_ban.g.dart';

@JsonSerializable(explicitToJson: true)
class RoomBan {
  final int id;
  final int roomId;
  final int userId;
  final int bannedBy;
  final String? reason;
  final String bannedAt;
  final String? expiresAt;
  final User? user;
  final User? banner;

  RoomBan({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.bannedBy,
    this.reason,
    required this.bannedAt,
    this.expiresAt,
    this.user,
    this.banner,
  });

  factory RoomBan.fromJson(Map<String, dynamic> json) => _$RoomBanFromJson(json);
  Map<String, dynamic> toJson() => _$RoomBanToJson(this);
}
