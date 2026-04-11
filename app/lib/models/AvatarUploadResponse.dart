import 'user.dart';

class AvatarUploadResponse {
  final String message;
  final String avatarUrl;
  final User user;

  AvatarUploadResponse({
    required this.message,
    required this.avatarUrl,
    required this.user,
  });

  factory AvatarUploadResponse.fromJson(Map<String, dynamic> json) {
    return AvatarUploadResponse(
      message: json['message'] as String? ?? 'Avatar uploaded',
      avatarUrl: json['avatarUrl'] as String? ?? json['url'] as String? ?? '',
      user: User.fromJson(json['user'] as Map<String, dynamic>? ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
    'message': message,
    'avatarUrl': avatarUrl,
    'user': user.toJson(),
  };
}
