import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
    final balanceAsync = ref.watch(agencyBalanceProvider);
    final chargingAsync = ref.watch(chargingAgenciesProvider);
    final hostingAsync = ref.watch(hostingAgenciesProvider);
    final myAsync = ref.watch(myAgenciesProvider);

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
              // ================== Balance Card ==================
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6B4CE6), Color(0xFF4A2FB8)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6B4CE6).withOpacity(0.5),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Text(
                      'رصيدك الحالي',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const _CoinIcon(size: 32),
                        const SizedBox(width: 12),

                        // ✅ real balance from DB
                        balanceAsync.when(
                          data: (b) => Text(
                            '$b',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          loading: () => const SizedBox(
                            height: 26,
                            width: 26,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          ),
                          error: (_, __) => const Text(
                            '--',
                            style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 860;
                  final chargingSection = _AgencySidePanel(
                    title: 'قسم وكالات الشحن',
                    subtitle: 'طلبات الإنشاء، الموافقات، وإدارة رصيد الوكالة.',
                    children: [
                      _CreateAgencyButton(
                        onTap: () => _handleCreateAgencyRequest(context, ref),
                      ),
                      const SizedBox(height: 12),
                      const _FeatureLine('طلب إنشاء وكالة جديدة باسم وصورة.'),
                      const _FeatureLine('يظهر الطلب داخل لوحة تحكم الأدمن للمراجعة والقبول.'),
                      const _FeatureLine('بعد القبول، صاحب الوكالة يطلب كوينز من الأدمن.'),
                      const _FeatureLine('الأدمن يرسل الكوينز للوكالة من لوحة التحكم.'),
                      const _FeatureLine('شاشة الوكالة (للأدمن فقط) ترسل كوينز لأي مستخدم.'),
                      const _FeatureLine('بيانات التواصل متاحة لأي مستخدم يريد شحن كوينز.'),
                      const SizedBox(height: 14),
                      const Text(
                        'طلباتك',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.right,
                      ),
                      const SizedBox(height: 8),
                      myAsync.when(
                        data: (items) {
                          if (items.isEmpty) {
                            return Text(
                              'لا توجد طلبات حتى الآن',
                              textAlign: TextAlign.right,
                              style: TextStyle(color: Colors.white.withOpacity(0.7)),
                            );
                          }
                          return Column(children: items.map((a) => _MyAgencyTile(a)).toList());
                        },
                        loading: () => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        error: (e, _) => Text(
                          'خطأ في تحميل طلباتك: $e',
                          textAlign: TextAlign.right,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'وكالات الشحن المعتمدة',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.right,
                      ),
                      const SizedBox(height: 10),
                      chargingAsync.when(
                        data: (items) {
                          if (items.isEmpty) {
                            return Text(
                              'لا توجد وكالات معتمدة حالياً',
                              textAlign: TextAlign.right,
                              style: TextStyle(color: Colors.white.withOpacity(0.7)),
                            );
                          }
                          return _AgencyGrid(items: items);
                        },
                        loading: () => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        error: (e, _) => Text(
                          'خطأ في تحميل وكالات الشحن: $e',
                          textAlign: TextAlign.right,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    ],
                  );

                  final hostingSection = _AgencySidePanel(
                    title: 'قسم وكالات الاستضافة',
                    subtitle: 'نظام الوكالات الاستضافية بالتفعيل والدعوات والتارجت.',
                    children: [
                      const _FeatureLine('اسم و شعار و صورة'),
                      const _FeatureLine('التفعيل بالموافقة'),
                      const _FeatureLine('دعوة انضمام للوكالة'),
                      const _FeatureLine('اسم الوكالة تحت بياناته'),
                      const _FeatureLine('صاحب الوكالة بشوف الكوينز اللى خادها من الناس'),
                      const _FeatureLine('نظام التارجت'),
                      const _FeatureLine('فى الصفحة الشخصية يظهر اللى اشتريته و التارجت و اللى جالى'),
                      const SizedBox(height: 14),
                      const Text(
                        'وكالات الاستضافة',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.right,
                      ),
                      const SizedBox(height: 10),
                      hostingAsync.when(
                        data: (items) {
                          if (items.isEmpty) {
                            return Text(
                              'لا توجد وكالات استضافة حالياً',
                              textAlign: TextAlign.right,
                              style: TextStyle(color: Colors.white.withOpacity(0.7)),
                            );
                          }
                          return _AgencyGrid(items: items);
                        },
                        loading: () => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        error: (e, _) => Text(
                          'خطأ في تحميل وكالات الاستضافة: $e',
                          textAlign: TextAlign.right,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    ],
                  );

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: chargingSection),
                        const SizedBox(width: 14),
                        Expanded(child: hostingSection),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      chargingSection,
                      const SizedBox(height: 14),
                      hostingSection,
                    ],
                  );
                },
              ),

              const SizedBox(height: 30),

              // ================== Packages ==================
              const Text(
                'باقات الشحن',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 16),

              ...chargingPackages.map((package) => _PackageCard(package: package)),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _handleCreateAgencyRequest(BuildContext context, WidgetRef ref) async {
  final result = await showDialog<CreateChargingAgencyPayload?>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const _CreateChargingAgencyDialog(),
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

class _AgencySidePanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _AgencySidePanel({
    required this.title,
    required this.subtitle,
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
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.right,
            style: TextStyle(color: Colors.white.withOpacity(0.7)),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _FeatureLine extends StatelessWidget {
  final String text;
  const _FeatureLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              text,
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.check_circle, size: 16, color: Color(0xFF9D88FF)),
        ],
      ),
    );
  }
}

class _AgencyGrid extends StatelessWidget {
  final List<ChargingAgency> items;
  const _AgencyGrid({required this.items});

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
      itemBuilder: (_, i) => _AgencyGridCard(items[i]),
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
  const _CreateAgencyButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      width: MediaQuery.of(context).size.width * 0.82,
      child: ElevatedButton.icon(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6B4CE6),
          foregroundColor: Colors.white,
          elevation: 10,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        icon: const Icon(Icons.add_business_rounded),
        label: const Text('إنشاء وكالة شحن', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// ========================== Dialog ==========================
class _CreateChargingAgencyDialog extends StatefulWidget {
  const _CreateChargingAgencyDialog();

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
                        const Text(
                          'إنشاء وكالة شحن',
                          textAlign: TextAlign.right,
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
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
  final String agencyName;
  final String phoneNumber;
  final String agencyImagePath;
  final String idFrontPath;
  final String idBackPath;

  CreateChargingAgencyPayload({
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
    );
  }
}

class _AgencyGridCard extends StatelessWidget {
  final ChargingAgency a;
  const _AgencyGridCard(this.a);

  @override
  Widget build(BuildContext context) {
    return Container(
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
          ],
        ),
      ),
    );
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
  final resp = await dio.get('/agencies/charging');
  final list = (resp.data['data'] as List? ?? const []).cast<Map<String, dynamic>>();
  return list.map((e) => ChargingAgency.fromJson(e)).toList();
});

final hostingAgenciesProvider = FutureProvider<List<ChargingAgency>>((ref) async {
  final dio = DioClient.dio;
  final resp = await dio.get('/agencies/hosting');
  final list = (resp.data['data'] as List? ?? const []).cast<Map<String, dynamic>>();
  return list.map((e) => ChargingAgency.fromJson(e)).toList();
});

final myAgenciesProvider = FutureProvider<List<ChargingAgency>>((ref) async {
  final dio = DioClient.dio;
  final resp = await dio.get('/agencies/my-agency');
  final data = (resp.data['data'] is Map<String, dynamic>) ? (resp.data['data'] as Map<String, dynamic>) : null;
  if (data == null || data.isEmpty) return [];
  return [ChargingAgency.fromJson(data)];
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
        'type': 'CHARGING',
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
