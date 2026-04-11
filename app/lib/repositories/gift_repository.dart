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
      if (_cache != null) {
        return Result.success(_cache!);
      }

      final response = await _apiService.getGifts(category: category);
      final apiGifts = response.gifts;
      final localGifts = getMockGifts();

      _cache = [
        ...apiGifts,
        ...localGifts.where(
              (mock) => !apiGifts.any((api) => api.id == mock.id),
        ),
      ];
      return Result.success(_cache!);
    } catch (e) {
      return Result.error(e.toString());
    }
  }

  Future<Result<void>> sendGift(SendGiftRequest request) async {
    try {
      await _apiService.sendGift(request);
      return Result.success(null);
    } catch (e) {
      return Result.error(e.toString());
    }
  }

  Future<Result<GiftHistoryResponse>> getGiftHistory({int page = 1, int limit = 20}) async {
    try {
      final response = await _apiService.getGiftHistory(page: page, limit: limit);
      return Result.success(response);
    } catch (e) {
      return Result.error(e.toString());
    }
  }
  // Mock gifts for development (still available)
  List<Gift> getMockGifts() {
    return [
      Gift(
        id: 1,
        name: 'Red Rose',
        imageUrl: '',
        priceCoins: 10,
        category: 'common',
        isActive: true,
      ),

      Gift(
        id: 2,
        name: 'Diamond Ring',
        imageUrl: '',
        priceCoins: 100,
        category: 'rare',
        isActive: true,
      ),

      Gift(
        id: 3,
        name: 'Luxury Car',
        imageUrl: '',
        priceCoins: 500,
        category: 'legendary',
        isActive: true,
      ),

      Gift(
        id: 4,
        name: 'Fireworks',
        imageUrl: '',
        priceCoins: 250,
        category: 'rare',
        isActive: true,
      ),

      Gift(
        id: 5,
        name: 'Heart Balloon',
        imageUrl: '',
        priceCoins: 25,
        category: 'common',
        isActive: true,
      ),

      /// 🔥 MEGA GIFTS

      Gift(
        id: 6,
        name: 'Dragon',
        imageUrl: 'assets/mega/dragon.png',
        priceCoins: 5000,
        category: 'legendary',
        animationKey: "dragon_fly",
      ),

      Gift(
        id: 7,
        name: 'Rocket',
        imageUrl: 'assets/mega/rocket.png',
        priceCoins: 8000,
        category: 'legendary',
        animationKey: "rocket_launch",
      ),

      Gift(
        id: 8,
        name: 'Castle',
        imageUrl: 'assets/mega/castle.png',
        priceCoins: 12000,
        category: 'legendary',
        animationKey: "castle_explode",
      ),
    ];
  }
}
