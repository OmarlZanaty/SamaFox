import 'dart:math';
import 'package:flutter/material.dart';

class FishShooterScreen extends StatefulWidget {
  const FishShooterScreen({super.key});

  @override
  State<FishShooterScreen> createState() => _FishShooterScreenState();
}

class _FishShooterScreenState extends State<FishShooterScreen> {
  final Random _random = Random();
  int _balance = 1000;
  int _ammo = 10;
  int _multiplier = 1;
  String _message = 'اضغط على سمكة للصيد';

  late List<_Fish> _fishes;

  @override
  void initState() {
    super.initState();
    _fishes = List.generate(9, (i) => _spawnFish(i));
  }

  _Fish _spawnFish(int id) {
    final rarityRoll = _random.nextInt(100);
    if (rarityRoll < 10) {
      return _Fish(id: id, emoji: '🐋', reward: 180, color: Colors.purpleAccent, dodgeChance: 0.65);
    }
    if (rarityRoll < 35) {
      return _Fish(id: id, emoji: '🦈', reward: 90, color: Colors.orangeAccent, dodgeChance: 0.45);
    }
    return _Fish(id: id, emoji: '🐟', reward: 35, color: Colors.lightBlueAccent, dodgeChance: 0.2);
  }

  void _shootFish(int index) {
    if (_ammo <= 0) {
      setState(() => _message = 'الذخيرة انتهت، أعد التعبئة');
      return;
    }

    final fish = _fishes[index];
    final hit = _random.nextDouble() > fish.dodgeChance / _multiplier;

    setState(() {
      _ammo -= 1;
      if (hit) {
        final gain = fish.reward * _multiplier;
        _balance += gain;
        _message = 'إصابة ممتازة! +$gain';
        _fishes[index] = _spawnFish(fish.id);
      } else {
        _message = 'اخفقت! ${fish.emoji} هربت';
      }
    });
  }

  void _reload() {
    if (_balance < 120) {
      setState(() => _message = 'لا يوجد رصيد كافٍ لإعادة التعبئة');
      return;
    }
    setState(() {
      _balance -= 120;
      _ammo = 10;
      _message = 'تمت إعادة التعبئة';
    });
  }

  void _upgradeGun() {
    final int cost = 200 * _multiplier;
    if (_balance < cost) {
      setState(() => _message = 'لا يوجد رصيد كافٍ للتطوير');
      return;
    }
    setState(() {
      _balance -= cost;
      _multiplier += 1;
      _message = 'تم رفع قوة السلاح إلى x$_multiplier';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('صيد السمك 🎣')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip(label: 'الرصيد', value: '$_balance'),
                  _InfoChip(label: 'الذخيرة', value: '$_ammo'),
                  _InfoChip(label: 'القوة', value: 'x$_multiplier'),
                ],
              ),
              const SizedBox(height: 8),
              Text(_message),
              const SizedBox(height: 8),
              Expanded(
                child: GridView.builder(
                  itemCount: _fishes.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1,
                  ),
                  itemBuilder: (context, index) {
                    final fish = _fishes[index];
                    return GestureDetector(
                      onTap: () => _shootFish(index),
                      child: Container(
                        decoration: BoxDecoration(
                          color: fish.color.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: fish.color),
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(fish.emoji, style: const TextStyle(fontSize: 34)),
                          const SizedBox(height: 4),
                          Text('+${fish.reward * _multiplier}'),
                        ]),
                      ),
                    );
                  },
                ),
              ),
              Row(
                children: [
                  Expanded(child: ElevatedButton(onPressed: _reload, child: const Text('إعادة تعبئة 120'))),
                  const SizedBox(width: 8),
                  Expanded(child: ElevatedButton(onPressed: _upgradeGun, child: const Text('تطوير السلاح'))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Fish {
  final int id;
  final String emoji;
  final int reward;
  final Color color;
  final double dodgeChance;

  _Fish({required this.id, required this.emoji, required this.reward, required this.color, required this.dodgeChance});
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(10)),
      child: Text('$label: $value', style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
