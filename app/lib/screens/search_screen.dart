import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/dio_client.dart';

/// Search Screen - Search users and rooms by name or ID
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _isSearching = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    final q = _controller.text.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _errorMessage = null;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 400), () => _doSearch(q));
  }

  Future<void> _doSearch(String q) async {
    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    try {
      final resp = await DioClient.dio.get(
        '/search',
        queryParameters: {'q': q, 'type': 'all'},
      );

      final list = (resp.data['data'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (!mounted) return;
      setState(() {
        _results = list;
        _isSearching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _errorMessage = 'حدث خطأ أثناء البحث';
      });
    }
  }

  void _onTapResult(Map<String, dynamic> result) {
    final id = result['id'];
    final type = (result['type'] ?? '').toString();

    if (type == 'room') {
      Navigator.pushNamed(context, '/room', arguments: id);
      return;
    }

    if (type == 'user') {
      Navigator.pushNamed(context, '/user-profile', arguments: id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A0E3E),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF2A1A5E),
              Color(0xFF1A0E3E),
              Color(0xFF0D0620),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A1A5E).withOpacity(0.6),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: const Color(0xFF5E35B1).withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                    decoration: InputDecoration(
                      hintText: 'ابحث بالاسم أو الرقم...',
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Color(0xFF4ECDC4),
                      ),
                      suffixIcon: _controller.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.white),
                              onPressed: () {
                                setState(() {
                                  _controller.clear();
                                  _results = [];
                                  _errorMessage = null;
                                });
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(20),
                    ),
                  ),
                ),
              ),
              if (_isSearching)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: CircularProgressIndicator(color: Color(0xFF4ECDC4)),
                ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 16),
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  itemCount: _results.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final result = _results[index];
                    final type = (result['type'] ?? '').toString();
                    final isRoom = type == 'room';
                    final title =
                        (result['name'] ?? result['username'] ?? 'بدون اسم').toString();
                    final subtitle = isRoom
                        ? 'غرفة • #${result['id'] ?? ''}'
                        : 'مستخدم • #${result['id'] ?? ''}';

                    return Material(
                      color: const Color(0xFF2A1A5E).withOpacity(0.8),
                      borderRadius: BorderRadius.circular(14),
                      child: ListTile(
                        onTap: () => _onTapResult(result),
                        leading: CircleAvatar(
                          backgroundColor: isRoom
                              ? const Color(0xFFFFA726)
                              : const Color(0xFF4ECDC4),
                          child: Icon(
                            isRoom ? Icons.meeting_room : Icons.person,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          subtitle,
                          style: TextStyle(color: Colors.white.withOpacity(0.7)),
                        ),
                        trailing: const Icon(Icons.chevron_right, color: Colors.white70),
                      ),
                    );
                  },
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
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}
