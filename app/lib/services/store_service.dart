import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import '../models/InventoryItem.dart';
import 'dio_client.dart';

class StoreService {
  final String baseUrl = "http://54.254.79.239:3000/api/v1";

  Future<List<InventoryItem>> getInventory(String token) async {
    try {
      final res = await DioClient.dio.get(
        '/store/inventory',
        options: token.isNotEmpty
            ? Options(headers: {'Authorization': 'Bearer $token'})
            : null,
      );

      final body = res.data;
      final list = (body is Map)
          ? (body['data'] ?? body['products'] ?? const [])
          : const [];

      return List.from(list)
          .map((e) => InventoryItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      // Prevent unhandled exceptions from breaking room flow when network is flaky.
      print('StoreService.getInventory error: $e');
      return <InventoryItem>[];
    }
  }

  Future<void> buyProduct(String token, String productId) async {
    final res = await http.post(
      Uri.parse("$baseUrl/store/buy"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "productId": productId,
      }),
    );

    if (res.statusCode != 200) {
      final body = jsonDecode(res.body);
      throw Exception(body['message'] ?? "Buy failed");
    }
  }

  Future<void> activateItem(String token, String inventoryId) async {
    final res = await http.post(
      Uri.parse("$baseUrl/store/activate"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
        body: jsonEncode({
          "inventoryId": inventoryId,
        })
    );

    if (res.statusCode != 200) {
      throw Exception("Activation failed");
    }
  }

  Future<void> activateFrame(String token, String inventoryId) async {
    final res = await http.post(
      Uri.parse("$baseUrl/store/activate-frame"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "itemId": inventoryId,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception("Frame activation failed");
    }
  }

  Future<void> deactivateFrame(String token) async {
    final res = await http.post(
      Uri.parse("$baseUrl/store/deactivate-frame"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
    );

    if (res.statusCode != 200) {
      throw Exception("Frame deactivation failed");
    }
  }

  Future<List<Map<String, dynamic>>> getMyFrames(String token) async {
    final res = await http.get(
      Uri.parse("$baseUrl/store/my-frames"),
      headers: {
        "Authorization": "Bearer $token",
      },
    );

    if (res.statusCode != 200) {
      throw Exception("Failed to load frames");
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = (body['data'] as List?) ?? const [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}
