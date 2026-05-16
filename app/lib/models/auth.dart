import 'package:json_annotation/json_annotation.dart';
import 'user.dart';

part 'auth.g.dart';

@JsonSerializable()
class AuthResponse {
  final String accessToken;
  final String refreshToken;
  final User user;
  final String? message;

  AuthResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
    this.message,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) =>
      _$AuthResponseFromJson(json);
  Map<String, dynamic> toJson() => _$AuthResponseToJson(this);
}

@JsonSerializable()
class LoginRequest {
  final String email;
  final String password;

  LoginRequest({
    required this.email,
    required this.password,
  });

  factory LoginRequest.fromJson(Map<String, dynamic> json) =>
      _$LoginRequestFromJson(json);
  Map<String, dynamic> toJson() => _$LoginRequestToJson(this);
}

// ADD THIS TO: lib/models/auth.dart
// REPLACE the RegisterRequest class with this updated version

@JsonSerializable()
class RegisterRequest {
  final String name;
  final String email;
  final String password;
  final String? gender;        // NEW: "male", "female", "other"
  final String? countryCode;   // NEW: ISO country code (e.g., "EG", "SA")
  final String? country;       // NEW: Country name (e.g., "Egypt")

  RegisterRequest({
    required this.name,
    required this.email,
    required this.password,
    this.gender,
    this.countryCode,
    this.country,
  });

  factory RegisterRequest.fromJson(Map<String, dynamic> json) =>
      _$RegisterRequestFromJson(json);
  Map<String, dynamic> toJson() => _$RegisterRequestToJson(this);
}


@JsonSerializable()
class GuestLoginRequest {
  final String deviceId;

  GuestLoginRequest({required this.deviceId});

  factory GuestLoginRequest.fromJson(Map<String, dynamic> json) =>
      _$GuestLoginRequestFromJson(json);
  Map<String, dynamic> toJson() => _$GuestLoginRequestToJson(this);
}

@JsonSerializable()
class GuestLoginResponse {
  final String accessToken;
  final String refreshToken;
  final User user;

  GuestLoginResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  factory GuestLoginResponse.fromJson(Map<String, dynamic> json) =>
      _$GuestLoginResponseFromJson(json);
  Map<String, dynamic> toJson() => _$GuestLoginResponseToJson(this);
}

class FacebookLoginRequest {
  final String facebookToken;

  FacebookLoginRequest({required this.facebookToken});

  Map<String, dynamic> toJson() => {
    'facebookToken': facebookToken,
  };
}

@JsonSerializable()
class GoogleLoginRequest {
  final String idToken;

  GoogleLoginRequest({required this.idToken});

  factory GoogleLoginRequest.fromJson(Map<String, dynamic> json) =>
      _$GoogleLoginRequestFromJson(json);
  Map<String, dynamic> toJson() => _$GoogleLoginRequestToJson(this);
}
