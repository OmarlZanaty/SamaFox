import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'dart:math';
import '../../services/api_service.dart';
import '../../services/dio_client.dart';
import '../../utils/storage_service.dart';

class DiceGameScreen extends ConsumerStatefulWidget {
  const DiceGameScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<DiceGameScreen> createState() => _DiceGameScreenState();
}

class _DiceGameScreenState extends ConsumerState<DiceGameScreen> {
  int _diceNumber = 1;
  bool _isRolling = false;
  int _totalXP = 0;
  String _message = '';

  void _rollDice() async {
    if (_isRolling) return;

    setState(() {
      _isRolling = true;
      _message = '';
    });

    try {
      // Animate dice roll
      await Future.delayed(const Duration(milliseconds: 500));

      setState(() {
        _diceNumber = Random().nextInt(6) + 1;
      });

      // Use the existing DioClient which already has the token interceptor
      final apiService = ApiService(DioClient.dio);

      // Call API to record the dice roll
      final response = await apiService.playDice();

      setState(() {
        _totalXP += response.xpEarned;
        _message = 'You rolled a ${response.diceResult}! +${response.xpEarned} XP';
        _isRolling = false;
      });
    } catch (e) {
      setState(() {
        _message = 'Error: $e';
        _isRolling = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🎲 Greedy Dice Game'),
        backgroundColor: const Color(0xFF6B4CE6),
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF2A1A5E),
              const Color(0xFF1A0E3E),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // Dice display (as number instead of image)
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  color: const Color(0xFF6B4CE6),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6B4CE6).withOpacity(0.5),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    _diceNumber.toString(),
                    style: const TextStyle(
                      fontSize: 80,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),

              // Total XP display
              Text(
                'Total XP: $_totalXP',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),

              // Message display
              if (_message.isNotEmpty)
                Text(
                  _message,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF4ECDC4),
                  ),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 40),

              // Roll button
              ElevatedButton(
                onPressed: _isRolling ? null : _rollDice,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _isRolling ? 'Rolling...' : 'Roll Dice',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
