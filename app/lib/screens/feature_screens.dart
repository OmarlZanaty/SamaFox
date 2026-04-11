/*
import 'package:flutter/material.dart';

/// Generic Feature Screen Template
class FeatureScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final String description;

  const FeatureScreen({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A0E3E),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF2A1A5E),
              const Color(0xFF1A0E3E),
              const Color(0xFF0D0620),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // App bar
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48), // Balance the back button
                  ],
                ),
              ),

              // Content
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Icon
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.2),
                          shape: BoxShape.circle,
                          border: Border.all(color: color, width: 3),
                        ),
                        child: Icon(
                          icon,
                          size: 60,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Title
                      Text(
                        title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Description
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          description,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 16,
                            height: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),

                      // Coming Soon Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [color.withOpacity(0.8), color],
                          ),
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: const Text(
                          'قريباً - Coming Soon',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
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

/// Backpack Screen
class BackpackScreen extends StatelessWidget {
  const BackpackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeatureScreen(
      title: 'Backpack',
      icon: Icons.backpack,
      color: Color(0xFF00BCD4),
      description: 'Store and manage your items, gifts, and collectibles in your personal backpack.',
    );
  }
}

/// Wealth Level Screen
class WealthLevelScreen extends StatelessWidget {
  const WealthLevelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeatureScreen(
      title: 'Wealth Level',
      icon: Icons.emoji_events,
      color: Color(0xFFFFC107),
      description: 'Track your wealth level and unlock exclusive rewards as you progress.',
    );
  }
}

/// Charm Level Screen
class CharmLevelScreen extends StatelessWidget {
  const CharmLevelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeatureScreen(
      title: 'Charm Level',
      icon: Icons.favorite,
      color: Color(0xFF4CAF50),
      description: 'Increase your charm level by receiving gifts and interacting with others.',
    );
  }
}

/// Agency Center Screen
class AgencyCenterScreen extends StatelessWidget {
  const AgencyCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeatureScreen(
      title: 'Agency Center',
      icon: Icons.business,
      color: Color(0xFF9C27B0),
      description: 'Join or create an agency to collaborate with other users and earn rewards.',
    );
  }
}

/// Task Screen
class TaskScreen extends StatelessWidget {
  const TaskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeatureScreen(
      title: 'Task',
      icon: Icons.assignment,
      color: Color(0xFFFFC107),
      description: 'Complete daily tasks and challenges to earn coins and XP.',
    );
  }
}

/// Store Screen
class StoreScreen extends StatelessWidget {
  const StoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeatureScreen(
      title: 'Store',
      icon: Icons.store,
      color: Color(0xFFE91E63),
      description: 'Browse and purchase items, decorations, and special effects for your profile.',
    );
  }
}

/// Gift Gallery Screen
class GiftGalleryScreen extends StatelessWidget {
  const GiftGalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeatureScreen(
      title: 'Gift Gallery',
      icon: Icons.card_giftcard,
      color: Color(0xFFE91E63),
      description: 'View all the gifts you\'ve received and sent to others.',
    );
  }
}

/// Badge Screen
class BadgeScreen extends StatelessWidget {
  const BadgeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeatureScreen(
      title: 'Badge',
      icon: Icons.military_tech,
      color: Color(0xFFFFC107),
      description: 'Collect and display badges earned through achievements and activities.',
    );
  }
}

/// Contact Us Screen
class ContactUsScreen extends StatelessWidget {
  const ContactUsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeatureScreen(
      title: 'Contact Us',
      icon: Icons.chat,
      color: Color(0xFF4CAF50),
      description: 'Get in touch with our support team for help, feedback, or suggestions.',
    );
  }
}

/// Intimate Relationship Screen
class IntimateRelationshipScreen extends StatelessWidget {
  const IntimateRelationshipScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeatureScreen(
      title: 'Intimate Relationship',
      icon: Icons.people,
      color: Color(0xFF00BCD4),
      description: 'Build and manage your intimate relationships with other users.',
    );
  }
}

/// Event Center Screen
class EventCenterScreen extends StatelessWidget {
  const EventCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeatureScreen(
      title: 'Event Center',
      icon: Icons.flag,
      color: Color(0xFFFFC107),
      description: 'Participate in special events, competitions, and seasonal activities.',
    );
  }
}
*/
