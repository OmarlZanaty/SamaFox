import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/InventoryItem.dart';

class StoreService {
  final String baseUrl = "http://54.254.79.239:3000/api/v1";

  Future<List<InventoryItem>> getInventory(String token) async {
    final res = await http.get(
      Uri.parse("$baseUrl/store/inventory"),
      headers: {
        "Authorization": "Bearer $token",
      },
    );

    final body = jsonDecode(res.body);

    print("FULL BODY: $body");


    print("STORE BODY: $body");

    final list = body['data'] ?? body['products'] ?? [];

    return List.from(list)
        .map((e) => InventoryItem.fromJson(e))
        .toList();
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
        "inventoryId": inventoryId,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception("Frame activation failed");
    }
  }
}
