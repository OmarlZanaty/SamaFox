import 'dart:async';

import 'package:flutter/material.dart';

import '../services/dio_client.dart';

/// SPEC52 #37 — Settings → الحساب → ربط رقم الهاتف.
/// Number → OTP → verify → linked to THIS account (never a new account).
/// The server refuses a number that belongs to another account.
class LinkPhoneScreen extends StatefulWidget {
  const LinkPhoneScreen({super.key});

  @override
  State<LinkPhoneScreen> createState() => _LinkPhoneScreenState();
}

class _LinkPhoneScreenState extends State<LinkPhoneScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String? _linked;
  String? _sentTo;
  bool _busy = false;
  int _resendIn = 0;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _t?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await DioClient.dio.get('/auth/phone');
      final d = r.data is Map ? r.data['data'] : null;
      if (mounted) setState(() => _linked = d is Map ? d['phone']?.toString() : null);
    } catch (_) {}
  }

  String _err(Object e) {
    try {
      final d = (e as dynamic).response?.data;
      if (d is Map && d['message'] != null) return d['message'].toString();
    } catch (_) {}
    return 'تعذر إتمام العملية';
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _send() async {
    if (_phone.text.trim().isEmpty) return _snack('أدخل رقم الهاتف');
    setState(() => _busy = true);
    try {
      final r = await DioClient.dio.post('/auth/phone/send-otp', data: {'phone': _phone.text.trim()});
      final d = r.data['data'] as Map;
      setState(() {
        _sentTo = d['phone']?.toString();
        _resendIn = (d['resendInSec'] as num?)?.toInt() ?? 60;
      });
      _t?.cancel();
      _t = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        setState(() => _resendIn = (_resendIn - 1).clamp(0, 999));
        if (_resendIn == 0) t.cancel();
      });
      // Local/test servers return the code (no SMS provider); production never does.
      if (d['devCode'] != null) _code.text = d['devCode'].toString();
      _snack('تم إرسال رمز التحقق إلى $_sentTo');
    } catch (e) {
      _snack(_err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_code.text.trim().length < 4) return _snack('أدخل الرمز');
    setState(() => _busy = true);
    try {
      final r = await DioClient.dio.post('/auth/phone/verify', data: {'phone': _sentTo ?? _phone.text.trim(), 'code': _code.text.trim()});
      setState(() {
        _linked = (r.data['data'] as Map)['phone']?.toString();
        _sentTo = null;
      });
      _snack('تم ربط رقم الهاتف بحسابك ✅');
    } catch (e) {
      _snack(_err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('ربط رقم الهاتف')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_linked != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.verified, color: Colors.green),
                  title: const Text('الرقم المرتبط بحسابك'),
                  subtitle: Text(_linked!, textDirection: TextDirection.ltr),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'رقم الهاتف', hintText: '01xxxxxxxxx أو +20…', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _busy || _resendIn > 0 ? null : _send,
              child: Text(_resendIn > 0 ? 'إعادة الإرسال بعد $_resendIn ث' : (_sentTo == null ? 'إرسال رمز التحقق' : 'إعادة إرسال الرمز')),
            ),
            if (_sentTo != null) ...[
              const SizedBox(height: 20),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, letterSpacing: 8),
                decoration: const InputDecoration(labelText: 'رمز التحقق', border: OutlineInputBorder()),
              ),
              FilledButton(onPressed: _busy ? null : _verify, child: const Text('تأكيد وربط الرقم')),
            ],
          ],
        ),
      ),
    );
  }
}
