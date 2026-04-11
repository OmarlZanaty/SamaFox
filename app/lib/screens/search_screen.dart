import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/dio_client.dart';
import '../models/user.dart';
import 'user_profile_screen.dart';

/// Search Screen - Search users by ID
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  User? _searchedUser;
  bool _isSearching = false;
  String? _errorMessage;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Search for user by ID
  Future<void> _searchUserById() async {
    final searchText = _searchController.text.trim();

    if (searchText.isEmpty) {
      setState(() {
        _errorMessage = 'الرجاء إدخال معرف المستخدم';
      });
      return;
    }

    final userId = int.tryParse(searchText);
    if (userId == null) {
      setState(() {
        _errorMessage = 'معرف المستخدم يجب أن يكون رقماً';
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _searchedUser = null;
    });

    try {
      final response = await DioClient.dio.get('/users/$userId');

      if (response.statusCode == 200) {
        setState(() {
          _searchedUser = User.fromJson(response.data);
          _isSearching = false;
        });
      }
    } catch (e) {
      setState(() {
        _isSearching = false;
        if (e.toString().contains('404')) {
          _errorMessage = 'المستخدم غير موجود';
        } else {
          _errorMessage = 'حدث خطأ أثناء البحث';
        }
      });
    }
  }

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
              _buildAppBar(),

              // Search content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),

                      // Search icon
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A1A5E),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF4ECDC4),
                            width: 3,
                          ),
                        ),
                        child: const Icon(
                          Icons.search,
                          size: 50,
                          color: Color(0xFF4ECDC4),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Title
                      const Text(
                        'البحث عن مستخدم',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Subtitle
                      Text(
                        'ابحث عن المستخدمين باستخدام معرفهم',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 16,
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Search field
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A1A5E).withOpacity(0.6),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: const Color(0xFF5E35B1).withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: TextField(
                          controller: _searchController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white, fontSize: 18),
                          decoration: InputDecoration(
                            hintText: 'أدخل معرف المستخدم (ID)',
                            hintStyle: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                            ),
                            prefixIcon: const Icon(
                              Icons.person_search,
                              color: Color(0xFF4ECDC4),
                            ),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.white),
                              onPressed: () {
                                setState(() {
                                  _searchController.clear();
                                  _searchedUser = null;
                                  _errorMessage = null;
                                });
                              },
                            )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.all(20),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _errorMessage = null;
                            });
                          },
                          onSubmitted: (value) => _searchUserById(),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Search button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isSearching ? null : _searchUserById,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4ECDC4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            elevation: 5,
                          ),
                          child: _isSearching
                              ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                              : const Text(
                            'بحث',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Error message
                      if (_errorMessage != null)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red, width: 1),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // User result card
                      if (_searchedUser != null) _buildUserCard(_searchedUser!),
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

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const Expanded(
            child: Text(
              'بحث',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 48), // Balance the back button
        ],
      ),
    );
  }

  Widget _buildUserCard(User user) {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF8E24AA),
            const Color(0xFFD81B60),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8E24AA).withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          // Avatar
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 48,
              backgroundImage: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                  ? NetworkImage(user.avatarUrl!)
                  : null,
              child: user.avatarUrl == null || user.avatarUrl!.isEmpty
                  ? const Icon(Icons.person, size: 50, color: Colors.white)
                  : null,
            ),
          ),

          const SizedBox(height: 16),

          // Name
          Text(
            user.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          // ID
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '#${user.publicDisplayId}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('Level', '${user.userLevel ?? 1}'),
              _buildStatItem('VIP', '${user.vipLevel ?? 0}'),
              _buildStatItem('Coins', '${user.coinsBalance ?? 0}'),
            ],
          ),

          const SizedBox(height: 20),

          // View Profile button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () {
                // Navigate to user profile
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserProfileScreen(userId: user.id ?? 0),
                  ),
                );
              },
              icon: const Icon(Icons.person),
              label: const Text('عرض الملف الشخصي'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF8E24AA),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
