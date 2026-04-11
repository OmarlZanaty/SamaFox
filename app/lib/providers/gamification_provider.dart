import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../repositories/gamification_repository.dart';
import '../models/achievement.dart';
import '../models/quest.dart';
import '../providers/auth_provider.dart';

// Repository provider
final gamificationRepositoryProvider = Provider<GamificationRepository>((ref) {
  final dio = Dio();
  return GamificationRepository(dio);
});

// Achievements provider
final achievementsProvider = FutureProvider<List<Achievement>>((ref) async {
  final repository = ref.read(gamificationRepositoryProvider);
  return repository.getAllAchievements();
});

// User achievements provider
final userAchievementsProvider = FutureProvider.family<List<UserAchievement>, int>((ref, userId) async {
  final repository = ref.read(gamificationRepositoryProvider);
  return repository.getUserAchievements(userId);
});

// Daily quests provider
final dailyQuestsProvider = FutureProvider<List<QuestWithProgress>>((ref) async {
  final authState = ref.watch(authStateProvider);

  if (!authState.isAuthenticated || authState.user == null) {
    return [];
  }

  final repository = ref.read(gamificationRepositoryProvider);
  return repository.getDailyQuests();
});

// Room level provider
final roomLevelProvider = FutureProvider.family<Map<String, dynamic>, int>((ref, roomId) async {
  final repository = ref.read(gamificationRepositoryProvider);
  return repository.getRoomLevel(roomId);
});

// Streak info provider
final streakInfoProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final authState = ref.watch(authStateProvider);

  if (!authState.isAuthenticated || authState.user == null) {
    return {};
  }

  final repository = ref.read(gamificationRepositoryProvider);
  return repository.getStreakInfo();
});

// Quest completion notifier
class QuestNotifier extends StateNotifier<AsyncValue<Map<String, dynamic>>> {
  final GamificationRepository repository;

  QuestNotifier(this.repository) : super(const AsyncValue.data({}));

  Future<void> completeQuest(String questId) async {
    state = const AsyncValue.loading();
    try {
      final result = await repository.completeQuest(questId);
      state = AsyncValue.data(result);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }
}

final questNotifierProvider = StateNotifierProvider<QuestNotifier, AsyncValue<Map<String, dynamic>>>((ref) {
  final repository = ref.read(gamificationRepositoryProvider);
  return QuestNotifier(repository);
});
