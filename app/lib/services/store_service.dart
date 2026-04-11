import 'package:dio/dio.dart';
import '../models/InventoryItem.dart';
import 'dio_client.dart';

class StoreService {
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
          ? (body['data'] ?? body['products'] ?? body['items'] ?? const [])
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
    try {
      final res = await DioClient.dio.post(
        '/store/buy',
        data: {'productId': productId},
        options: token.isNotEmpty
            ? Options(headers: {'Authorization': 'Bearer $token'})
            : null,
      );
      final body = res.data;
      final success = body is Map ? (body['success'] == true) : false;
      if (!success) {
        throw Exception(body is Map ? (body['message'] ?? 'Buy failed') : 'Buy failed');
      }
    } catch (e) {
      throw Exception('Buy failed: $e');
    }
  }

  Future<void> activateItem(String token, String inventoryId) async {
    await DioClient.dio.post(
      '/store/activate',
      data: {'inventoryId': inventoryId},
      options: token.isNotEmpty
          ? Options(headers: {'Authorization': 'Bearer $token'})
          : null,
    );
  }

  Future<void> activateFrame(String token, String inventoryId) async {
    await DioClient.dio.post(
      '/store/activate-frame',
      data: {'itemId': inventoryId},
      options: token.isNotEmpty
          ? Options(headers: {'Authorization': 'Bearer $token'})
          : null,
    );
  }

  Future<void> deactivateFrame(String token) async {
    await DioClient.dio.post(
      '/store/deactivate-frame',
      options: token.isNotEmpty
          ? Options(headers: {'Authorization': 'Bearer $token'})
          : null,
    );
  }

  Future<List<Map<String, dynamic>>> getMyFrames(String token) async {
    try {
      final res = await DioClient.dio.get(
        '/store/my-frames',
        options: token.isNotEmpty
            ? Options(headers: {'Authorization': 'Bearer $token'})
            : null,
      );
      final body = res.data;
      final raw = (body is Map)
          ? ((body['data'] as List?) ?? (body['frames'] as List?) ?? const [])
          : const [];
      return raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map((m) => <String, dynamic>{
                'id': m['id'] ?? m['itemId'],
                'name': m['name'] ?? m['title'],
                'imageUrl': m['imageUrl'] ?? m['assetUrl'] ?? m['file_url'],
                'isActive': m['isActive'] ?? m['is_active'] ?? false,
              })
          .toList();
    } on DioException catch (e) {
      // Older backend may not have /store/my-frames.
      if (e.response?.statusCode == 404) {
        final inv = await getInventory(token);
        return inv
            .where((i) => i.type == 'avatar_frame')
            .map((i) => <String, dynamic>{
                  'id': i.productId,
                  'name': i.name,
                  'imageUrl': i.fileUrl,
                  'isActive': i.isActive,
                })
            .toList();
      }
      print('StoreService.getMyFrames error: $e');
      return <Map<String, dynamic>>[];
    } catch (e) {
      print('StoreService.getMyFrames error: $e');
      return <Map<String, dynamic>>[];
    }
  }
}
