import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../config/app_config.dart';

class ImageUploadService {
  final Dio _dio;

  ImageUploadService({Dio? dio}) : _dio = dio ?? Dio();

  /// Upload an image file to the server (web-compatible via bytes)
  Future<String> uploadImageBytes(Uint8List bytes, String token, {String filename = 'image.jpg'}) async {
    try {
      final formData = FormData.fromMap({
        'image': MultipartFile.fromBytes(bytes, filename: filename),
      });

      final response = await _dio.post(
        '${AppConfig.apiBaseUrl}upload/image',
        data: formData,
        options: Options(headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'multipart/form-data',
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = response.data;
        if (responseData is Map) {
          final imageUrl = responseData['url'] as String? ?? responseData['imageUrl'] as String?;
          if (imageUrl != null) return imageUrl;
        }
        if (responseData is String) return responseData;
        throw Exception('No URL in response');
      }
      throw Exception('Upload failed: ${response.statusCode}');
    } catch (e) {
      debugPrint('🔴 uploadImageBytes error: $e');
      rethrow;
    }
  }

  /// Upload an image file to the server
  /// Returns the URL of the uploaded image
  Future<String> uploadImage(File imageFile, String token) async {
    try {
      // Create form data
      final formData = FormData.fromMap({
        'image': await MultipartFile.fromFile(
          imageFile.path,
          filename: imageFile.path.split('/').last,
        ),
      });

      debugPrint('🔵 Uploading image to: ${AppConfig.apiBaseUrl}upload/image');

      // Upload the image
      final response = await _dio.post(
        '${AppConfig.apiBaseUrl}upload/image',
        data: formData,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'multipart/form-data',
          },
        ),
      );

      debugPrint('🔵 Upload response status: ${response.statusCode}');
      debugPrint('🔵 Upload response data type: ${response.data.runtimeType}');
      debugPrint('🔵 Upload response data: ${response.data}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Extract image URL from response
        final responseData = response.data;

        // Handle both Map and String responses
        if (responseData is Map) {
          final imageUrl = responseData['url'] as String? ??
              responseData['imageUrl'] as String?;

          debugPrint('🔵 Extracted imageUrl: $imageUrl');

          if (imageUrl != null && imageUrl.isNotEmpty) {
            return imageUrl;
          } else {
            debugPrint('❌ Response data keys: ${responseData.keys}');
            throw Exception('Image URL not found in response');
          }
        } else {
          throw Exception('Invalid response format: ${responseData.runtimeType}');
        }
      } else {
        throw Exception('Failed to upload image: ${response.statusCode}');
      }
    } on DioException catch (e) {
      debugPrint('❌ DioException: ${e.message}');
      debugPrint('❌ Response: ${e.response?.data}');
      if (e.response != null) {
        throw Exception('Upload failed: ${e.response?.data['error'] ?? e.message}');
      } else {
        throw Exception('Network error: ${e.message}');
      }
    } catch (e) {
      debugPrint('❌ Unexpected error: $e');
      throw Exception('Unexpected error: $e');
    }
  }

  /// Upload room cover image (web-compatible)
  Future<String> uploadRoomCoverImageBytes(Uint8List bytes, String token) async {
    return uploadImageBytes(bytes, token, filename: 'room_cover.jpg');
  }

  /// Upload room cover image
  Future<String> uploadRoomCoverImage(File imageFile, String token) async {
    return uploadImage(imageFile, token);
  }

  /// Upload profile picture
  Future<String> uploadProfilePicture(File imageFile, String token) async {
    return uploadImage(imageFile, token);
  }
}
