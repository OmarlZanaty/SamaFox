import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../providers/auth_provider.dart';
import '../repositories/user_repository.dart';
import '../services/dio_client.dart';
import '../services/image_upload_service.dart';
import '../utils/storage_service.dart';
import '../utils/result.dart';
import 'package:dio/dio.dart';

/// Charging Agent Screen - وكيل الشحن
class ChargingAgentScreen extends ConsumerWidget {
  const ChargingAgentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chargingAsync = ref.watch(chargingAgenciesProvider);
    final hostingAsync = ref.watch(hostingAgenciesProvider);
    final myAsync = ref.watch(myAgenciesProvider);
    final authState = ref.watch(authStateProvider);
    final isSystemAdmin = authState.user?.userIsAdmin ?? false;
    final myOwnedAgencyId = myAsync.maybeWhen(
      data: (items) => items.isNotEmpty ? items.first.id : null,
      orElse: () => null,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF1A0E3E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'وكيل الشحن',
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
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(agencyBalanceProvider);
            ref.invalidate(myAgenciesProvider);
            ref.invalidate(chargingAgenciesProvider);
            ref.invalidate(hostingAgenciesProvider);
          },
          child: ListView(
            padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 30),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _CreateAgencyButton(
                      label: 'إنشاء وكالة شحن',
                      onTap: () => _handleCreateAgencyRequest(context, ref, type: 'CHARGING'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CreateAgencyButton(
                      label: 'إنشاء وكالة استضافة',
                      onTap: () => _handleCreateAgencyRequest(context, ref, type: 'HOSTING'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _AgencySidePanel(
                title: 'وكالات الشحن',
                children: [
                  chargingAsync.when(
                    data: (items) => items.isEmpty
                        ? _emptyText('لا توجد وكالات شحن معتمدة حالياً')
                        : _AgencyGrid(
                            items: items,
                            onTap: (agency) => _onAgencyTap(
                              context,
                              ref,
                              agency,
                              isAgencyAdmin: isSystemAdmin || myOwnedAgencyId == agency.id,
                            ),
                          ),
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (_, __) => _emptyText('تعذر تحميل وكالات الشحن حالياً'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _AgencySidePanel(
                title: 'وكالات الاستضافة',
                children: [
                  hostingAsync.when(
                    data: (items) => items.isEmpty
                        ? _emptyText('لا توجد وكالات استضافة معتمدة حالياً')
                        : _AgencyGrid(
                            items: items,
                            onTap: (agency) => _onAgencyTap(
                              context,
                              ref,
                              agency,
                              isAgencyAdmin: isSystemAdmin || myOwnedAgencyId == agency.id,
                            ),
                          ),
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (_, __) => _emptyText('تعذر تحميل وكالات الاستضافة حالياً'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _emptyText(String text) => Text(
      text,
      textAlign: TextAlign.right,
      style: const TextStyle(color: Colors.white70),
    );

Future<void> _onAgencyTap(
  BuildContext context,
  WidgetRef ref,
  ChargingAgency agency, {
  required bool isAgencyAdmin,
}) async {
  if (agency.type == 'CHARGING') {
    await _showChargingActions(context, agency, isAgencyAdmin: isAgencyAdmin);
    return;
  }
  await _showHostingActions(context, agency, isAgencyAdmin: isAgencyAdmin);
}

Future<void> _handleCreateAgencyRequest(
  BuildContext context,
  WidgetRef ref, {
  required String type,
}) async {
  final result = await showDialog<CreateChargingAgencyPayload?>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _CreateChargingAgencyDialog(type: type),
  );

  if (result == null) return;

  final ok = await ref.read(createAgencyControllerProvider.notifier).submit(result);
  if (!context.mounted) return;

  if (ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ تم إرسال طلب إنشاء الوكالة (Pending)')),
    );
    ref.invalidate(myAgenciesProvider);
    ref.invalidate(chargingAgenciesProvider);
    ref.invalidate(hostingAgenciesProvider);
    ref.invalidate(agencyBalanceProvider);
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('❌ فشل إرسال الطلب، راجع السيرفر/الإنترنت')),
    );
  }
}

Future<void> _showChargingActions(
  BuildContext context,
  ChargingAgency agency, {
  required bool isAgencyAdmin,
}) async {
  await showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1F1247),
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(agency.agencyName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (isAgencyAdmin) ...[
              ListTile(
                textColor: Colors.white,
                iconColor: Colors.white,
                leading: const Icon(Icons.request_page),
                title: const Text('طلب كوينز من الأدمن'),
                onTap: () async {
                  Navigator.pop(context);
                  await _requestCoinsFromAdmin(context);
                },
              ),
              ListTile(
                textColor: Colors.white,
                iconColor: Colors.white,
                leading: const Icon(Icons.send),
                title: const Text('شحن مستخدم من رصيد الوكالة'),
                onTap: () async {
                  Navigator.pop(context);
                  await _sendAgencyCoinsToUser(context);
                },
              ),
            ] else ...[
              ListTile(
                textColor: Colors.white,
                iconColor: Colors.white70,
                leading: const Icon(Icons.phone),
                title: Text(agency.contactInfo.isEmpty ? 'لا يوجد رقم تواصل' : agency.contactInfo),
                subtitle: const Text('تواصل مع أدمن الوكالة للشحن', style: TextStyle(color: Colors.white70)),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

Future<void> _showHostingActions(
  BuildContext context,
  ChargingAgency agency, {
  required bool isAgencyAdmin,
}) async {
  await showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1F1247),
    isScrollControlled: true,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(agency.agencyName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (isAgencyAdmin) ...[
              Text('المستهدف: ${agency.targetCoins} | المحقق: ${agency.earnedCoins}',
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              ...agency.members.map(
                (m) => ListTile(
                  dense: true,
                  textColor: Colors.white,
                  leading: const Icon(Icons.person, color: Colors.white70),
                  title: Text((m['name'] ?? 'عضو').toString()),
                  subtitle: const Text('كوينز الغرف: -- | التارجت: --', style: TextStyle(color: Colors.white70)),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _openJoinRequestsManager(context);
                },
                child: const Text('طلبات الانضمام المعلقة'),
              ),
            ] else ...[
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  await _requestJoinHostingAgency(context, agency.id);
                },
                icon: const Icon(Icons.group_add),
                label: const Text('طلب انضمام للوكالة'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

Future<void> _requestCoinsFromAdmin(BuildContext context) async {
  final amountCtrl = TextEditingController();
  final receiptCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1F1247),
      title: const Text('طلب كوينز', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MiniField(controller: amountCtrl, label: 'الكمية'),
          const SizedBox(height: 8),
          _MiniField(controller: receiptCtrl, label: 'رابط الإيصال'),
          const SizedBox(height: 8),
          _MiniField(controller: noteCtrl, label: 'ملاحظة'),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('إرسال')),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await DioClient.dio.post('/charging-agencies/topup', data: {
      'amount': int.tryParse(amountCtrl.text.trim()) ?? 0,
      'receiptUrl': receiptCtrl.text.trim(),
      'note': noteCtrl.text.trim(),
    });
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال الطلب')));
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل إرسال الطلب')));
  }
}

Future<void> _sendAgencyCoinsToUser(BuildContext context) async {
  final userCtrl = TextEditingController();
  final amountCtrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1F1247),
      title: const Text('شحن مستخدم', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MiniField(controller: userCtrl, label: 'رقم المستخدم'),
          const SizedBox(height: 8),
          _MiniField(controller: amountCtrl, label: 'عدد الكوينز'),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('إرسال')),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await DioClient.dio.post('/agencies/send-coins', data: {
      'userId': int.tryParse(userCtrl.text.trim()) ?? 0,
      'amount': int.tryParse(amountCtrl.text.trim()) ?? 0,
    });
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الشحن بنجاح')));
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل الشحن')));
  }
}

Future<void> _requestJoinHostingAgency(BuildContext context, int agencyId) async {
  try {
    await DioClient.dio.post('/agencies/$agencyId/join-request');
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال طلب الانضمام')));
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يمكن إرسال الطلب حالياً')));
    }
  }
}

Future<void> _openJoinRequestsManager(BuildContext context) async {
  try {
    final resp = await DioClient.dio.get('/agencies/join-requests/my-agency');
    final rows = ((resp.data['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1F1247),
      builder: (_) => ListView(
        padding: const EdgeInsets.all(12),
        children: rows.map((r) {
          final requester = ((r['requester'] as Map?) ?? const {}).cast<String, dynamic>();
          return ListTile(
            textColor: Colors.white,
            title: Text((requester['name'] ?? 'مستخدم').toString()),
            subtitle: Text('ID: ${requester['displayId'] ?? requester['id'] ?? '-'}'),
            trailing: Wrap(
              spacing: 4,
              children: [
                TextButton(
                  onPressed: () async {
                    await DioClient.dio.patch('/agencies/join-requests/${r['id']}/review', data: {'action': 'accept'});
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('قبول'),
                ),
                TextButton(
                  onPressed: () async {
                    await DioClient.dio.patch('/agencies/join-requests/${r['id']}/review', data: {'action': 'reject'});
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('رفض'),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر تحميل الطلبات')));
  }
}

class _MiniField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  const _MiniField({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(color: Colors.white70)),
    );
  }
}

class _AgencySidePanel extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _AgencySidePanel({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1A5E).withOpacity(0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6B4CE6).withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _AgencyGrid extends StatelessWidget {
  final List<ChargingAgency> items;
  final void Function(ChargingAgency agency)? onTap;
  const _AgencyGrid({required this.items, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.92,
      ),
      itemBuilder: (_, i) => _AgencyGridCard(items[i], onTap: onTap),
    );
  }
}

// ========================== Coin Icon (SVG with fallback) ==========================
class _CoinIcon extends StatelessWidget {
  final double size;
  const _CoinIcon({required this.size});

  @override
  Widget build(BuildContext context) {
    // If you don't have the SVG in assets, this will fallback to icon without crashing.
    return SizedBox(
      width: size,
      height: size,
      child: SvgPicture.asset(
        'assets/icons/coin_egp.svg',
        width: size,
        height: size,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => Icon(Icons.monetization_on, color: const Color(0xFFFFD700), size: size),
      ),
    );
  }
}

// ========================== Create Agency Button ==========================
class _CreateAgencyButton extends StatelessWidget {
  final VoidCallback onTap;
  final String label;
  const _CreateAgencyButton({required this.onTap, required this.label});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6B4CE6),
          foregroundColor: Colors.white,
          elevation: 10,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        icon: const Icon(Icons.add_business_rounded),
        label: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// ========================== Dialog ==========================
class _CreateChargingAgencyDialog extends StatefulWidget {
  final String type;
  const _CreateChargingAgencyDialog({required this.type});

  @override
  State<_CreateChargingAgencyDialog> createState() => _CreateChargingAgencyDialogState();
}

class _CreateChargingAgencyDialogState extends State<_CreateChargingAgencyDialog> {
  final _formKey = GlobalKey<FormState>();
  final _agencyName = TextEditingController();
  final _phone = TextEditingController();

  final _picker = ImagePicker();

  XFile? _agencyImage;
  XFile? _idFront;
  XFile? _idBack;

  bool _submitting = false;

  @override
  void dispose() {
    _agencyName.dispose();
    _phone.dispose();
    super.dispose();
  }

  final agencyBalanceProvider = FutureProvider<int>((ref) async {
    final dio = DioClient.dio;
    try {
      final resp = await dio.get('/charging-agencies/my/balance');
      return (resp.data['balanceCoins'] ?? 0) as int;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return 0; // ✅ pending/not approved yet
      }
      rethrow;
    }
  });


  Future<XFile?> _pickImage() async {
    return _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
  }

  Future<void> _chooseAgencyImage() async {
    final img = await _pickImage();
    if (img != null) setState(() => _agencyImage = img);
  }

  Future<void> _chooseFront() async {
    final img = await _pickImage();
    if (img != null) setState(() => _idFront = img);
  }

  Future<void> _chooseBack() async {
    final img = await _pickImage();
    if (img != null) setState(() => _idBack = img);
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_agencyImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('من فضلك ارفع صورة الوكالة.')),
      );
      return;
    }

    setState(() => _submitting = true);

    final payload = CreateChargingAgencyPayload(
      type: widget.type,
        agencyName: _agencyName.text.trim(),
        phoneNumber: _phone.text.trim(),
        agencyImagePath: _agencyImage!.path,
        idFrontPath: _idFront?.path ?? '',
        idBackPath: _idBack?.path ?? '',
      );

    if (!mounted) return;
    Navigator.pop(context, payload);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxH = MediaQuery.of(context).size.height * 0.78;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(left: 14, right: 14, top: 18, bottom: 18 + bottomInset),
      child: Dialog(
        backgroundColor: const Color(0xFF1F1247),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        insetPadding: EdgeInsets.zero,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.all(18),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          widget.type == 'HOSTING' ? 'إنشاء وكالة استضافة' : 'إنشاء وكالة شحن',
                          textAlign: TextAlign.right,
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 14),

                        _Field(
                          controller: _agencyName,
                          label: 'اسم الوكالة',
                          icon: Icons.storefront,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'اكتب اسم الوكالة';
                            if (v.trim().length < 3) return 'اسم الوكالة قصير جدًا';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        _Field(
                          controller: _phone,
                          label: 'رقم الهاتف',
                          icon: Icons.phone,
                          keyboardType: TextInputType.phone,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'اكتب رقم الهاتف';
                            if (v.trim().length < 8) return 'رقم الهاتف غير صحيح';
                            return null;
                          },
                        ),

                        const SizedBox(height: 14),

                        _ImagePickTile(
                          title: 'صورة الوكالة / اللوجو',
                          file: _agencyImage,
                          onPick: _chooseAgencyImage,
                        ),
                        const SizedBox(height: 10),

                        Row(
                          children: [
                            Expanded(
                              child: _ImagePickTile(
                                title: 'البطاقة (الأمام)',
                                file: _idFront,
                                onPick: _chooseFront,
                                compact: true,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _ImagePickTile(
                                title: 'البطاقة (الخلف)',
                                file: _idBack,
                                onPick: _chooseBack,
                                compact: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _submitting ? null : () => Navigator.pop(context, null),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: BorderSide(color: Colors.white.withOpacity(0.25)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('إلغاء'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _submitting ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6B4CE6),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _submitting
                              ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                              : const Text('إرسال الطلب'),
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

// ========================== Field ==========================
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      textAlign: TextAlign.right,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.white70),
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
        filled: true,
        fillColor: const Color(0xFF2A1A5E).withOpacity(0.6),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF6B4CE6), width: 1.2),
        ),
      ),
    );
  }
}

// ========================== Image Pick Tile ==========================
class _ImagePickTile extends StatelessWidget {
  final String title;
  final XFile? file;
  final VoidCallback onPick;
  final bool compact;

  const _ImagePickTile({
    required this.title,
    required this.file,
    required this.onPick,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    final height = compact ? 120.0 : 140.0;

    return InkWell(
      onTap: onPick,
      borderRadius: radius,
      child: Container(
        height: height,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF2A1A5E).withOpacity(0.6),
          borderRadius: radius,
          border: Border.all(color: const Color(0xFF6B4CE6).withOpacity(0.28)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    file == null ? 'اضغط للرفع' : 'تم الرفع ✅',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: Colors.white.withOpacity(0.7)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _PreviewBox(file: file),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewBox extends StatelessWidget {
  final XFile? file;
  const _PreviewBox({required this.file});

  @override
  Widget build(BuildContext context) {
    if (file == null) {
      return Container(
        width: 72,
        height: 72,
        color: Colors.white.withOpacity(0.08),
        child: const Icon(Icons.cloud_upload_rounded, color: Colors.white70),
      );
    }

    return Image.file(
      File(file!.path),
      width: 72,
      height: 72,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        width: 72,
        height: 72,
        color: Colors.white.withOpacity(0.08),
        child: const Icon(Icons.broken_image, color: Colors.white70),
      ),
    );
  }
}

/// Returned from dialog
class CreateChargingAgencyPayload {
  final String type;
  final String agencyName;
  final String phoneNumber;
  final String agencyImagePath;
  final String idFrontPath;
  final String idBackPath;

  CreateChargingAgencyPayload({
    required this.type,
    required this.agencyName,
    required this.phoneNumber,
    required this.agencyImagePath,
    required this.idFrontPath,
    required this.idBackPath,
  });
}

// ========================== Packages ==========================
class _PackageCard extends StatelessWidget {
  final ChargingPackage package;

  const _PackageCard({required this.package});

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
                  package.price, // already "ج.م"
                  style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  package.description,
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Row(
            children: [
              const _CoinIcon(size: 28),
              const SizedBox(width: 8),
              Text(
                package.diamonds,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ChargingPackage {
  final String diamonds;
  final String price;
  final String description;

  ChargingPackage({
    required this.diamonds,
    required this.price,
    required this.description,
  });
}

final List<ChargingPackage> chargingPackages = [
  ChargingPackage(diamonds: '100', price: '9.99 ج.م', description: 'باقة المبتدئين'),
  ChargingPackage(diamonds: '500', price: '49.99 ج.م', description: 'باقة شائعة'),
  ChargingPackage(diamonds: '1,200', price: '99.99 ج.م', description: 'أفضل قيمة'),
  ChargingPackage(diamonds: '2,500', price: '199.99 ج.م', description: 'باقة VIP'),
  ChargingPackage(diamonds: '6,500', price: '499.99 ج.م', description: 'باقة النخبة'),
  ChargingPackage(diamonds: '13,000', price: '999.99 ج.م', description: 'باقة الملوك'),
];

// ========================== Agency UI ==========================
class ChargingAgency {
  final int id;
  final String agencyName;
  final String contactInfo;
  final String agencyImageUrl;
  final String type;
  final String status; // pending/approved/rejected
  final String targetCoins;
  final String earnedCoins;
  final String createdAt;
  final int memberCount;
  final List<Map<String, dynamic>> members;

  ChargingAgency({
    required this.id,
    required this.agencyName,
    required this.contactInfo,
    required this.agencyImageUrl,
    required this.type,
    required this.status,
    required this.targetCoins,
    required this.earnedCoins,
    required this.createdAt,
    required this.memberCount,
    required this.members,
  });

  factory ChargingAgency.fromJson(Map<String, dynamic> j) {
    final image = (j['agencyImageUrl'] ??
            j['imageUrl'] ??
            j['logoUrl'] ??
            '') as String;

    return ChargingAgency(
      id: (j['id'] ?? 0) as int,
      agencyName: (j['agencyName'] ?? '') as String,
      contactInfo: (j['contactInfo'] ?? j['phoneNumber'] ?? '') as String,
      agencyImageUrl: image,
      type: (j['type'] ?? 'CHARGING') as String,
      status: (j['status'] ?? 'pending') as String,
      targetCoins: '${j['targetCoins'] ?? '0'}',
      earnedCoins: '${j['earnedCoins'] ?? '0'}',
      createdAt: (j['createdAt'] ?? '') as String,
      memberCount: int.tryParse('${j['memberCount'] ?? 0}') ?? 0,
      members: ((j['members'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList(),
    );
  }
}

class _AgencyGridCard extends StatelessWidget {
  final ChargingAgency a;
  final void Function(ChargingAgency agency)? onTap;
  const _AgencyGridCard(this.a, {this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap == null ? null : () => onTap!(a),
      borderRadius: BorderRadius.circular(16),
      child: Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2A1A5E).withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6B4CE6).withOpacity(0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: a.agencyImageUrl.isEmpty
                    ? Container(
                  color: Colors.white.withOpacity(0.08),
                  child: const Center(child: Icon(Icons.store, color: Colors.white70)),
                )
                    : Image.network(
                  a.agencyImageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.white.withOpacity(0.08),
                    child: const Center(child: Icon(Icons.broken_image, color: Colors.white70)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              a.agencyName,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.phone, size: 16, color: Colors.white70),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    a.contactInfo.isEmpty ? '—' : a.contactInfo,
                    textAlign: TextAlign.right,
                    style: TextStyle(color: Colors.white.withOpacity(0.8)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (a.type == 'HOSTING') ...[
              const SizedBox(height: 6),
              Text(
                'الأعضاء: ${a.memberCount}',
                textAlign: TextAlign.right,
                style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    ));
  }
}

class _MyAgencyTile extends StatelessWidget {
  final ChargingAgency a;
  const _MyAgencyTile(this.a);

  Color _statusColor(String s) {
    switch (s) {
      case 'approved':
        return Colors.greenAccent;
      case 'rejected':
        return Colors.redAccent;
      default:
        return Colors.orangeAccent;
    }
  }

  String _statusText(String s) {
    switch (s) {
      case 'approved':
        return 'مقبول';
      case 'rejected':
        return 'مرفوض';
      default:
        return 'قيد المراجعة';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _statusColor(a.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1A5E).withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF6B4CE6).withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: c.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.withOpacity(0.55)),
            ),
            child: Text(
              _statusText(a.status),
              style: TextStyle(color: c, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  a.agencyName,
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  a.contactInfo.isEmpty ? '—' : a.contactInfo,
                  textAlign: TextAlign.right,
                  style: TextStyle(color: Colors.white.withOpacity(0.75)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ========================== Providers / Controllers ==========================

// ========================== Providers / Controllers ==========================

/// ✅ Agency wallet balance (ChargingAgency.balanceCoins)
final agencyBalanceProvider = FutureProvider<int>((ref) async {
  final dio = DioClient.dio;
  final resp = await dio.get('/agencies/my-agency');
  final data = (resp.data is Map<String, dynamic>) ? (resp.data['data'] ?? {}) as Map<String, dynamic> : <String, dynamic>{};
  final raw = data['balanceCoins'] ?? 0;
  return int.tryParse('$raw') ?? 0;
});

final chargingAgenciesProvider = FutureProvider<List<ChargingAgency>>((ref) async {
  final dio = DioClient.dio;
  try {
    final resp = await dio.get('/agencies/charging');
    final list = (resp.data['data'] as List? ?? const []).cast<Map<String, dynamic>>();
    return list.map((e) => ChargingAgency.fromJson(e)).toList();
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) return [];
    rethrow;
  }
});

final hostingAgenciesProvider = FutureProvider<List<ChargingAgency>>((ref) async {
  final dio = DioClient.dio;
  try {
    final resp = await dio.get('/agencies/hosting');
    final list = (resp.data['data'] as List? ?? const []).cast<Map<String, dynamic>>();
    return list.map((e) => ChargingAgency.fromJson(e)).toList();
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) return [];
    rethrow;
  }
});

final myAgenciesProvider = FutureProvider<List<ChargingAgency>>((ref) async {
  final dio = DioClient.dio;
  try {
    final resp = await dio.get('/agencies/my-agency');
    final data = (resp.data['data'] is Map<String, dynamic>) ? (resp.data['data'] as Map<String, dynamic>) : null;
    if (data == null || data.isEmpty) return [];
    return [ChargingAgency.fromJson(data)];
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) return [];
    rethrow;
  }
});

final createAgencyControllerProvider =
StateNotifierProvider<CreateAgencyController, bool>((ref) => CreateAgencyController(ref));

class CreateAgencyController extends StateNotifier<bool> {
  final Ref ref;
  CreateAgencyController(this.ref) : super(false);

  Future<bool> submit(CreateChargingAgencyPayload payload) async {
    if (state) return false;
    state = true;

    try {
      final token = await StorageService.getAccessToken();
      if (token == null || token.isEmpty) throw Exception('no token');

      // ✅ uploader instance + File()
      final uploader = ImageUploadService();

      final agencyUrl = await uploader.uploadImage(File(payload.agencyImagePath), token);
      if (agencyUrl == null) {
        throw Exception('upload failed');
      }

      final dio = DioClient.dio;
      await dio.post('/agencies/request', data: {
        'type': payload.type,
        'agencyName': payload.agencyName,
        'contactInfo': payload.phoneNumber,
        'imageUrl': agencyUrl,
      });

      // ✅ refresh UI after create
      ref.invalidate(myAgenciesProvider);
      ref.invalidate(chargingAgenciesProvider);
      ref.invalidate(hostingAgenciesProvider);
      ref.invalidate(agencyBalanceProvider);

      return true;
    } catch (e) {
      return false;
    } finally {
      state = false;
    }
  }
}
