import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../services/dio_client.dart';
import '../utils/storage_service.dart';

/// وقت البث — the days-and-hours table the owner asked for.
///
/// Shows one row per calendar day a host was on a mic, newest first. Agents can
/// open it for any member of their own agency by passing [userId]; hosts see
/// their own by leaving it null.
class BroadcastTimeScreen extends StatefulWidget {
  const BroadcastTimeScreen({super.key, this.userId, this.title});

  final int? userId;
  final String? title;

  @override
  State<BroadcastTimeScreen> createState() => _BroadcastTimeScreenState();
}

class _BroadcastTimeScreenState extends State<BroadcastTimeScreen> {
  List<Map<String, dynamic>> _days = [];
  double _totalHours = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final token = await StorageService.getAccessToken();
      final res = await DioClient.dio.get(
        '/agencies/broadcast-time',
        queryParameters: widget.userId != null ? {'userId': widget.userId} : null,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = res.data is Map ? (res.data['data'] as Map?) : null;
      final days = (data?['days'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!mounted) return;
      setState(() {
        _days = days;
        _totalHours = ((data?['totalHours'] as num?) ?? 0).toDouble();
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.response?.data is Map
            ? e.response?.data['message']?.toString() ?? 'تعذّر تحميل وقت البث'
            : 'تعذّر تحميل وقت البث';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = 'تعذّر تحميل وقت البث'; _loading = false; });
    }
  }

  /// «2.5» reads badly in Arabic for time; show «2 س 30 د».
  String _fmtHours(num hours) {
    final totalMinutes = (hours * 60).round();
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (h == 0) return '$m د';
    if (m == 0) return '$h س';
    return '$h س $m د';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF150B33),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A0E3E),
        title: Text(widget.title ?? 'وقت البث',
            style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70)),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF5E35B1), Color(0xFF4A148C)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            const Text('إجمالي وقت البث',
                                style: TextStyle(color: Colors.white70, fontSize: 12)),
                            const SizedBox(height: 4),
                            Text(
                              _fmtHours(_totalHours),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text('${_days.length} يوم بث',
                                style: const TextStyle(color: Colors.white54, fontSize: 11)),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 22, vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text('اليوم',
                                  style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold)),
                            ),
                            Text('الساعات',
                                style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _days.isEmpty
                            ? ListView(
                                // Keeps pull-to-refresh working when empty.
                                children: const [
                                  SizedBox(height: 60),
                                  Center(
                                    child: Text('لا يوجد وقت بث مسجَّل بعد',
                                        style: TextStyle(color: Colors.white38)),
                                  ),
                                ],
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: _days.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(color: Colors.white10, height: 1),
                                itemBuilder: (_, i) {
                                  final d = _days[i];
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 6),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            (d['date'] ?? '').toString(),
                                            style: const TextStyle(
                                                color: Colors.white, fontSize: 14),
                                          ),
                                        ),
                                        Text(
                                          _fmtHours((d['hours'] as num?) ?? 0),
                                          style: const TextStyle(
                                            color: Color(0xFF4ECDC4),
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
