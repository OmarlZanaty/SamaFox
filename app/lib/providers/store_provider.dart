import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:samafox/models/product.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

final storeProvider = FutureProvider<List<Product>>((ref) async {
  final res = await http.get(
    Uri.parse("http://54.254.79.239:3000/api/v1/store/products"),
  );

  final body = jsonDecode(res.body);

  print("STORE BODY: $body");

  final list = (body['data'] ?? body['products'] ?? []) as List;

  final raw = body['data'];

  if (raw == null || raw is! List) {
    return [];
  }
  return list.map((e) => Product.fromJson(e)).toList();
});