import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/tr.dart';

/// Host Screen - المضيف
class HostScreen extends ConsumerWidget {
  const HostScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A0E3E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          tr('المضيف', 'Host'),
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1A0E3E),
              Color(0xFF0D0620),
            ],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Host info card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF6B9D), Color(0xFFD81B60)],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF6B9D).withOpacity(0.5),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.mic_rounded,
                    color: Colors.white,
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    tr('كن مضيفًا', 'Become a host'),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr('ابدأ بإنشاء غرفتك الخاصة واستضف أصدقائك', 'Create your own room and host your friends'),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            // Host benefits
            Text(
              tr('مميزات المضيف', 'Host benefits'),
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 16),
            ..._hostBenefits.map((benefit) => _BenefitCard(
              icon: benefit['icon'] as IconData,
              title: benefit['title'] as String,
              description: benefit['description'] as String,
            )),
            const SizedBox(height: 30),
            // Create room button
            ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(tr('إنشاء غرفة جديدة...', 'Creating a new room...'))),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4ECDC4),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                tr('إنشاء غرفة جديدة', 'Create new room'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BenefitCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _BenefitCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1A5E).withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF6B4CE6).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.right,
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF4ECDC4).withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: const Color(0xFF4ECDC4),
              size: 32,
            ),
          ),
        ],
      ),
    );
  }
}

List<Map<String, dynamic>> get _hostBenefits => [
  {
    'icon': Icons.people,
    'title': tr('استضافة الأصدقاء', 'Host friends'),
    'description': tr('قم بدعوة أصدقائك وإنشاء مجتمعك الخاص', 'Invite friends and build your own community'),
  },
  {
    'icon': Icons.diamond,
    'title': tr('اكسب الماس', 'Earn diamonds'),
    'description': tr('احصل على مكافآت من الهدايا والتفاعلات', 'Get rewards from gifts and interactions'),
  },
  {
    'icon': Icons.star,
    'title': tr('كن مشهورًا', 'Become popular'),
    'description': tr('زد من شهرتك وعدد متابعينك', 'Grow your popularity and followers'),
  },
  {
    'icon': Icons.settings,
    'title': tr('تحكم كامل', 'Full control'),
    'description': tr('أدر غرفتك بالطريقة التي تريدها', 'Manage your room your way'),
  },
];
