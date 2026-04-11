import 'package:flutter_riverpod/flutter_riverpod.dart';

final walletProvider = StateNotifierProvider<WalletNotifier, int>((ref) {
  return WalletNotifier(initialCoins: 10000); // start coins
});

class WalletNotifier extends StateNotifier<int> {
  WalletNotifier({required int initialCoins}) : super(initialCoins);

  bool canBet(int amount) => state >= amount;

  void add(int amount) => state += amount;

  void subtract(int amount) => state = (state - amount).clamp(0, 1 << 30);
}
