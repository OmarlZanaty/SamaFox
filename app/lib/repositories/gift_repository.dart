import '../models/gift_history.dart';
import '../services/api_service.dart';
import '../services/dio_client.dart';
import '../models/gift.dart';
import '../utils/result.dart';

class GiftRepository {
  late final ApiService _apiService;
  List<Gift>? _cache;

  GiftRepository() {
    _apiService = ApiService(DioClient.dio);
  }

  Future<Result<List<Gift>>> getGifts({String? category}) async {
    try {
      if (_cache != null && category == null) {
        return Result.success(_cache!);
      }

      final response = await _apiService.getGifts(category: category);
      final gifts = response.gifts;
      if (category == null) _cache = gifts;
      return Result.success(gifts);
    } catch (e) {
      return Result.error(e.toString());
    }
  }

  Future<List<GiftModel>> fetchGifts() async {
    final resp = await DioClient.dio.get('/gifts');
    return (resp.data['data'] as List).map((g) => GiftModel.fromJson(g as Map<String, dynamic>)).toList();
  }

  Future<Result<void>> sendGift(SendGiftRequest request) async {
    try {
      await _apiService.sendGift(request);
      return Result.success(null);
    } catch (e) {
      return Result.error(e.toString());
    }
  }

  Future<Result<GiftHistoryResponse>> getGiftHistory({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final response = await _apiService.getGiftHistory(page: page, limit: limit);
      return Result.success(response);
    } catch (e) {
      return Result.error(e.toString());
    }
  }
}

class GiftModel {
  final int id;
  final String nameAr;
  final String imageUrl;
  final String? animationUrl;
  final int coinsValue;

  GiftModel.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        nameAr = j['nameAr'] as String,
        imageUrl = j['imageUrl'] as String,
        animationUrl = j['animationUrl'] as String?,
        coinsValue = j['coinsValue'] as int;
}
