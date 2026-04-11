// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AuthResponse _$AuthResponseFromJson(Map<String, dynamic> json) => AuthResponse(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      message: json['message'] as String?,
    );

Map<String, dynamic> _$AuthResponseToJson(AuthResponse instance) =>
    <String, dynamic>{
      'accessToken': instance.accessToken,
      'refreshToken': instance.refreshToken,
      'user': instance.user,
      'message': instance.message,
    };

LoginRequest _$LoginRequestFromJson(Map<String, dynamic> json) => LoginRequest(
      email: json['email'] as String,
      password: json['password'] as String,
    );

Map<String, dynamic> _$LoginRequestToJson(LoginRequest instance) =>
    <String, dynamic>{
      'email': instance.email,
      'password': instance.password,
    };

RegisterRequest _$RegisterRequestFromJson(Map<String, dynamic> json) =>
    RegisterRequest(
      name: json['name'] as String,
      email: json['email'] as String,
      password: json['password'] as String,
      gender: json['gender'] as String?,
      countryCode: json['countryCode'] as String?,
      country: json['country'] as String?,
    );

Map<String, dynamic> _$RegisterRequestToJson(RegisterRequest instance) =>
    <String, dynamic>{
      'name': instance.name,
      'email': instance.email,
      'password': instance.password,
      'gender': instance.gender,
      'countryCode': instance.countryCode,
      'country': instance.country,
    };

GuestLoginRequest _$GuestLoginRequestFromJson(Map<String, dynamic> json) =>
    GuestLoginRequest(
      deviceId: json['deviceId'] as String,
    );

Map<String, dynamic> _$GuestLoginRequestToJson(GuestLoginRequest instance) =>
    <String, dynamic>{
      'deviceId': instance.deviceId,
    };

GuestLoginResponse _$GuestLoginResponseFromJson(Map<String, dynamic> json) =>
    GuestLoginResponse(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      user: User.fromJson(json['user'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$GuestLoginResponseToJson(GuestLoginResponse instance) =>
    <String, dynamic>{
      'accessToken': instance.accessToken,
      'refreshToken': instance.refreshToken,
      'user': instance.user,
    };

GoogleLoginRequest _$GoogleLoginRequestFromJson(Map<String, dynamic> json) =>
    GoogleLoginRequest(
      idToken: json['idToken'] as String,
    );

Map<String, dynamic> _$GoogleLoginRequestToJson(GoogleLoginRequest instance) =>
    <String, dynamic>{
      'idToken': instance.idToken,
    };
