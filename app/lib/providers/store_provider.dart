import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:samafox/models/product.dart';
import '../services/dio_client.dart';

final storeProvider = FutureProvider<List<Product>>((ref) async {
  final res = await DioClient.dio.get('/store/products');
  final body = res.data;

  if (body is! Map<String, dynamic>) return [];
  final list = (body['data'] ?? body['products'] ?? body['items'] ?? []) as List;

  if (list.isEmpty) {
    return [];
  }
  return list.map((e) => Product.fromJson(e)).toList();
});
