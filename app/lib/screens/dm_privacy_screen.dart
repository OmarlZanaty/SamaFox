import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../services/dio_client.dart';
import '../l10n/tr.dart';

/// قفل الرسائل الخاصة — who may open a DM with me.
///
/// Client spec: *"المستخدم يسيبها عامة أو يقفل الرسايل للأصدقاء فقط أو يفعل
/// لها عدد كوينز معين للرسالة لكن الكوينزات دي هتروح للبرنامج وليس للمستخدم
/// اللي قافل الرسايل"*. Saved through PUT /users/me/dm-privacy; the server is
/// the one that enforces it (dmAccess.service).
class DmPrivacyScreen extends StatefulWidget {
  const DmPrivacyScreen({super.key});

  @override
  State<DmPrivacyScreen> createState() => _DmPrivacyScreenState();
}

const List<int> _kPricePresets = [10, 50, 100, 500, 1000];

class _DmPrivacyScreenState extends State<DmPrivacyScreen> {
  String _privacy = 'public';
  int _price = 100;
  bool _loading = true;
  bool _saving = false;
  final _customCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await DioClient.dio.get('/users/me');
      final u = (res.data is Map ? res.data['user'] : null) as Map?;
      if (u != null && mounted) {
        setState(() {
          _privacy = (u['dmPrivacy'] ?? 'public').toString();
          final p = (u['dmPriceCoins'] as num?)?.toInt() ?? 0;
          if (p > 0) _price = p;
          if (!_kPricePresets.contains(_price)) _customCtrl.text = '$_price';
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await DioClient.dio.put('/users/me/dm-privacy', data: {
        'dmPrivacy': _privacy,
        if (_privacy == 'paid') 'dmPriceCoins': _price,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('تم الحفظ ✅', 'Saved ✅'))));
      Navigator.of(context).pop(true);
    } on DioException catch (e) {
      final msg = (e.response?.data is Map ? e.response!.data['message'] : null)?.toString();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg ?? tr('تعذّر الحفظ', 'Unable to save'))));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('تعذّر الحفظ', 'Unable to save'))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(tr('قفل الرسائل الخاصة', 'Lock private messages'))),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    tr('مين يقدر يبعتلك رسالة خاصة؟', 'Who can send you private messages?'),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  _option(
                    value: 'public',
                    icon: Icons.public,
                    title: tr('عامة', 'Public'),
                    subtitle: tr('أي حد يقدر يبعتلك', 'Anyone can message you'),
                  ),
                  _option(
                    value: 'friends',
                    icon: Icons.people_outline,
                    title: tr('الأصدقاء فقط', 'Friends only'),
                    subtitle: tr('اللي بينك وبينهم متابعة متبادلة', 'People you follow who also follow you'),
                  ),
                  _option(
                    value: 'paid',
                    icon: Icons.lock_outline,
                    title: tr('بكوينز', 'Paid with coins'),
                    subtitle: tr('غير الأصدقاء يدفعوا مرة واحدة عشان يفتحوا محادثة معاك. الكوينز بتروح للبرنامج مش ليك.', 'Non-friends pay once to open a conversation with you. The coins go to the app, not to you.'),
                  ),
                  if (_privacy == 'paid') ...[
                    const SizedBox(height: 16),
                    Text(tr('سعر فتح المحادثة', 'Conversation unlock price'), style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final p in _kPricePresets)
                          ChoiceChip(
                            label: Text('$p 🪙'),
                            selected: _price == p,
                            onSelected: (_) => setState(() {
                              _price = p;
                              _customCtrl.clear();
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _customCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: tr('أو سعر آخر (1 – 100000)', 'Or another price (1 – 100000)'),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) {
                        final n = int.tryParse(v.trim());
                        if (n != null && n >= 1 && n <= 100000) setState(() => _price = n);
                      },
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    tr('ملاحظة: لو الشخص رد عليك مرة، المحادثة بتفضل مفتوحة بينكم من غير قفل. الأدمن مش بيتقفل عليه.', 'Note: once someone replies to you, the conversation stays open. Admins are exempt from locks.'),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(tr('حفظ', 'Save')),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _option({required String value, required IconData icon, required String title, required String subtitle}) {
    final selected = _privacy == value;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? const Color(0xFFFFB300) : Colors.transparent, width: 1.5),
      ),
      child: RadioListTile<String>(
        value: value,
        groupValue: _privacy,
        onChanged: (v) => setState(() => _privacy = v ?? 'public'),
        secondary: Icon(icon, color: const Color(0xFFFFB300)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        controlAffinity: ListTileControlAffinity.trailing,
      ),
    );
  }
}
