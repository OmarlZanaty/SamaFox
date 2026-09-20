import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../services/dio_client.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحفظ ✅')));
      Navigator.of(context).pop(true);
    } on DioException catch (e) {
      final msg = (e.response?.data is Map ? e.response!.data['message'] : null)?.toString();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg ?? 'تعذّر الحفظ')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر الحفظ')));
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
        appBar: AppBar(title: const Text('قفل الرسائل الخاصة')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'مين يقدر يبعتلك رسالة خاصة؟',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  _option(
                    value: 'public',
                    icon: Icons.public,
                    title: 'عامة',
                    subtitle: 'أي حد يقدر يبعتلك',
                  ),
                  _option(
                    value: 'friends',
                    icon: Icons.people_outline,
                    title: 'الأصدقاء فقط',
                    subtitle: 'اللي بينك وبينهم متابعة متبادلة',
                  ),
                  _option(
                    value: 'paid',
                    icon: Icons.lock_outline,
                    title: 'بكوينز',
                    subtitle: 'غير الأصدقاء يدفعوا مرة واحدة عشان يفتحوا محادثة معاك. الكوينز بتروح للبرنامج مش ليك.',
                  ),
                  if (_privacy == 'paid') ...[
                    const SizedBox(height: 16),
                    Text('سعر فتح المحادثة', style: theme.textTheme.titleSmall),
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
                      decoration: const InputDecoration(
                        labelText: 'أو سعر آخر (1 – 100000)',
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
                    'ملاحظة: لو الشخص رد عليك مرة، المحادثة بتفضل مفتوحة بينكم من غير قفل. الأدمن مش بيتقفل عليه.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('حفظ'),
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
