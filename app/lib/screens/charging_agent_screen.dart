import 'dart:io';
import 'dart:typed_data';

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
class ChargingAgentScreen extends ConsumerStatefulWidget {
  const ChargingAgentScreen({super.key});

  @override
  ConsumerState<ChargingAgentScreen> createState() => _ChargingAgentScreenState();
}

class _ChargingAgentScreenState extends ConsumerState<ChargingAgentScreen> {
  // #10: when a user owns/works BOTH a hosting and a charging agency, they
  // pick which interface to work in rather than seeing both stacked at once.
  // null = not chosen yet (only relevant when they actually have both).
  String? _activeInterface;

  @override
  Widget build(BuildContext context) {
    final chargingAsync = ref.watch(chargingAgenciesProvider);
    final hostingAsync = ref.watch(hostingAgenciesProvider);
    final membershipsAsync = ref.watch(myMembershipsProvider);
    final authState = ref.watch(authStateProvider);
    final isSystemAdmin = authState.user?.userIsAdmin ?? false;
    // agencyId -> role ('OWNER' | 'BRANCH' | other). Covers EVERY agency the
    // user owns or is a branch (فرع) of, not just the first one (#2-4, #8).
    final myRoles = membershipsAsync.maybeWhen(
      data: (items) => items,
      orElse: () => const <int, String>{},
    );

    final hasCharging = isSystemAdmin ||
        chargingAsync.maybeWhen(data: (items) => items.any((a) => myRoles.containsKey(a.id)), orElse: () => false);
    final hasHosting = isSystemAdmin ||
        hostingAsync.maybeWhen(data: (items) => items.any((a) => myRoles.containsKey(a.id)), orElse: () => false);
    final needsChoice = hasCharging && hasHosting;
    final showCharging = !needsChoice || _activeInterface == 'CHARGING';
    final showHosting = !needsChoice || _activeInterface == 'HOSTING';

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
            ref.invalidate(myMembershipsProvider);
            ref.invalidate(chargingAgenciesProvider);
            ref.invalidate(hostingAgenciesProvider);
          },
          child: needsChoice && _activeInterface == null
              ? _buildInterfaceChooser()
              : ListView(
                  padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 30),
                  children: [
                    if (needsChoice)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: TextButton.icon(
                          onPressed: () => setState(() => _activeInterface = null),
                          icon: const Icon(Icons.swap_horiz, color: Colors.white70, size: 18),
                          label: Text(
                            'تبديل الواجهة (حالياً: ${_activeInterface == 'CHARGING' ? 'الشحن' : 'الاستضافة'})',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: _CreateAgencyButton(
                            label: ' وكالة شحن',
                            onTap: () => _handleCreateAgencyRequest(context, ref, type: 'CHARGING'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _CreateAgencyButton(
                            label: 'وكالة استضافة',
                            onTap: () => _handleCreateAgencyRequest(context, ref, type: 'HOSTING'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (showCharging) ...[
                      _AgencySidePanel(
                        title: 'وكالات الشحن',
                        children: [
                          chargingAsync.when(
                            data: (items) => items.isEmpty
                                ? _emptyText('لا توجد وكالات شحن معتمدة حالياً')
                                : _buildAgencyGrid(
                                    items,
                                    onTap: (agency) => _onAgencyTap(
                                      context,
                                      ref,
                                      agency,
                                      isAgencyAdmin: isSystemAdmin || myRoles.containsKey(agency.id),
                                      isOwner: isSystemAdmin || myRoles[agency.id] == 'OWNER',
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
                    ],
                    if (showHosting)
                      _AgencySidePanel(
                        title: 'وكالات الاستضافة',
                        children: [
                          hostingAsync.when(
                            data: (items) => items.isEmpty
                                ? _emptyText('لا توجد وكالات استضافة معتمدة حالياً')
                                : _buildAgencyGrid(
                                    items,
                                    onTap: (agency) => _onAgencyTap(
                                      context,
                                      ref,
                                      agency,
                                      isAgencyAdmin: isSystemAdmin || myRoles.containsKey(agency.id),
                                      isOwner: isSystemAdmin || myRoles[agency.id] == 'OWNER',
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

  Widget _buildInterfaceChooser() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'تعمل كوكيل شحن ووكيل استضافة معاً — اختر الواجهة التي تريد العمل عليها الآن',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => setState(() => _activeInterface = 'CHARGING'),
                icon: const Icon(Icons.attach_money),
                label: const Text('العمل كوكيل شحن'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => setState(() => _activeInterface = 'HOSTING'),
                icon: const Icon(Icons.mic),
                label: const Text('العمل كوكيل استضافة'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
          ],
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
  required bool isOwner,
}) async {
  if (agency.type == 'CHARGING') {
    await _showChargingActions(context, agency, isAgencyAdmin: isAgencyAdmin, isOwner: isOwner);
    return;
  }
  await _showHostingActions(context, agency, isAgencyAdmin: isAgencyAdmin, isOwner: isOwner);
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
    ref.invalidate(myMembershipsProvider);
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
  required bool isOwner,
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
                title: const Text('إضافة كوينز لمستخدم'),
                onTap: () async {
                  Navigator.pop(context);
                  await _sendAgencyCoinsToUser(context);
                },
              ),
              // Branches (فرع) — same system access, no ownership (#2-4). Only
              // the owner manages who the branches are.
              if (isOwner) ...[
                ListTile(
                  textColor: Colors.white,
                  iconColor: Colors.white,
                  leading: const Icon(Icons.groups),
                  title: const Text('الفروع (حتى 3)'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _manageBranches(context, agency, agencyType: 'CHARGING');
                  },
                ),
                // #7: backend already supported this for CHARGING agencies —
                // it just wasn't exposed from this screen (only the hosting
                // panel had the button).
                ListTile(
                  textColor: Colors.white,
                  iconColor: Colors.white,
                  leading: const Icon(Icons.swap_horiz),
                  title: const Text('نقل ملكية الوكالة'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _transferAgencyOwnership(context, agencyType: 'CHARGING');
                  },
                ),
              ],
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
  required bool isOwner,
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
              // Branches (فرع) — same hosting-management access, no ownership.
              // Only the owner manages who the branches are (#2-4).
              if (isOwner) ...[
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _manageBranches(context, agency, agencyType: 'HOSTING');
                  },
                  icon: const Icon(Icons.groups),
                  label: const Text('الفروع (حتى 3)'),
                ),
              ],
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

// #5-7: "إضافة كوينز" flow — enter the person's ID, THEY APPEAR (name/avatar)
// so the agent confirms it's the right person, then a box for the coin count,
// then إرسال. Replaces the old raw userId+amount dialog with no confirmation.
Future<void> _sendAgencyCoinsToUser(BuildContext context) async {
  final idCtrl = TextEditingController();
  final amountCtrl = TextEditingController();
  Map<String, dynamic>? foundUser;
  bool searching = false;
  String? error;

  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        Future<void> doSearch() async {
          final q = idCtrl.text.trim();
          if (q.isEmpty) return;
          setState(() { searching = true; error = null; foundUser = null; });
          try {
            final resp = await DioClient.dio.get('/agencies/search-user', queryParameters: {'q': q});
            final list = (resp.data is Map) ? (resp.data['data'] as List? ?? const []) : const [];
            if (list.isNotEmpty) {
              setState(() { foundUser = Map<String, dynamic>.from(list.first as Map); searching = false; });
            } else {
              setState(() { error = 'لم يتم العثور على مستخدم بهذا الرقم'; searching = false; });
            }
          } catch (_) {
            setState(() { error = 'فشل البحث'; searching = false; });
          }
        }

        return AlertDialog(
          backgroundColor: const Color(0xFF1F1247),
          title: const Text('إضافة كوينز', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: _MiniField(controller: idCtrl, label: 'رقم المستخدم (ID)')),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: searching ? null : doSearch,
                    icon: const Icon(Icons.search, color: Colors.white),
                  ),
                ],
              ),
              if (searching) const Padding(
                padding: EdgeInsets.only(top: 8),
                child: CircularProgressIndicator(),
              ),
              if (error != null) Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!, style: const TextStyle(color: Colors.redAccent)),
              ),
              if (foundUser != null) ...[
                const SizedBox(height: 12),
                ListTile(
                  leading: CircleAvatar(
                    backgroundImage: (foundUser!['avatarUrl'] ?? '').toString().isNotEmpty
                        ? NetworkImage(foundUser!['avatarUrl'].toString())
                        : null,
                    child: (foundUser!['avatarUrl'] ?? '').toString().isEmpty
                        ? const Icon(Icons.person)
                        : null,
                  ),
                  title: Text((foundUser!['name'] ?? '').toString(), style: const TextStyle(color: Colors.white)),
                  subtitle: Text('#${foundUser!['displayId'] ?? foundUser!['id']}', style: const TextStyle(color: Colors.white70)),
                ),
                const SizedBox(height: 8),
                _MiniField(controller: amountCtrl, label: 'عدد الكوينز'),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: foundUser == null ? null : () => Navigator.pop(dialogContext, true),
              child: const Text('إرسال'),
            ),
          ],
        );
      },
    ),
  );
  if (ok != true || foundUser == null) return;
  try {
    await DioClient.dio.post('/agencies/send-coins', data: {
      'userId': foundUser!['id'],
      'amount': int.tryParse(amountCtrl.text.trim()) ?? 0,
    });
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الشحن بنجاح')));
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل الشحن')));
  }
}

// #7: same search-then-confirm pattern as _sendAgencyCoinsToUser — enter the
// new owner's ID, their name/photo appear so the owner confirms it's the
// right person, then transfer. agencyType disambiguates for a user who owns
// both a hosting and a charging agency (backend picks the wrong one without it).
Future<void> _transferAgencyOwnership(BuildContext context, {required String agencyType}) async {
  final idCtrl = TextEditingController();
  Map<String, dynamic>? foundUser;
  bool searching = false;
  String? error;

  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        Future<void> doSearch() async {
          final q = idCtrl.text.trim();
          if (q.isEmpty) return;
          setState(() { searching = true; error = null; foundUser = null; });
          try {
            final resp = await DioClient.dio.get('/agencies/search-user', queryParameters: {'q': q});
            final list = (resp.data is Map) ? (resp.data['data'] as List? ?? const []) : const [];
            if (list.isNotEmpty) {
              setState(() { foundUser = Map<String, dynamic>.from(list.first as Map); searching = false; });
            } else {
              setState(() { error = 'لم يتم العثور على مستخدم بهذا الرقم'; searching = false; });
            }
          } catch (_) {
            setState(() { error = 'فشل البحث'; searching = false; });
          }
        }

        return AlertDialog(
          backgroundColor: const Color(0xFF1F1247),
          title: const Text('نقل ملكية الوكالة', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'ستفقد صلاحيات الوكيل وتصبح مضيفاً في هذه الوكالة.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _MiniField(controller: idCtrl, label: 'رقم المستخدم الجديد (ID)')),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: searching ? null : doSearch,
                    icon: const Icon(Icons.search, color: Colors.white),
                  ),
                ],
              ),
              if (searching) const Padding(
                padding: EdgeInsets.only(top: 8),
                child: CircularProgressIndicator(),
              ),
              if (error != null) Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!, style: const TextStyle(color: Colors.redAccent)),
              ),
              if (foundUser != null) Padding(
                padding: const EdgeInsets.only(top: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: (foundUser!['avatarUrl'] ?? '').toString().isNotEmpty
                        ? NetworkImage(foundUser!['avatarUrl'].toString())
                        : null,
                    child: (foundUser!['avatarUrl'] ?? '').toString().isEmpty
                        ? const Icon(Icons.person)
                        : null,
                  ),
                  title: Text((foundUser!['name'] ?? '').toString(), style: const TextStyle(color: Colors.white)),
                  subtitle: Text('#${foundUser!['displayId'] ?? foundUser!['id']}', style: const TextStyle(color: Colors.white70)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: foundUser == null ? null : () => Navigator.pop(dialogContext, true),
              child: const Text('نقل'),
            ),
          ],
        );
      },
    ),
  );
  if (ok != true || foundUser == null) return;
  try {
    await DioClient.dio.post('/agencies/transfer-ownership', data: {
      'toUserId': foundUser!['id'],
      'agencyType': agencyType,
    });
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نقل الملكية بنجاح')));
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل نقل الملكية')));
  }
}

// #2-4: Branches (فرع) management — owner adds/removes up to 3 partners who
// get the same system access without owning the agency.
Future<void> _manageBranches(
  BuildContext context,
  ChargingAgency agency, {
  required String agencyType,
}) async {
  Future<List<Map<String, dynamic>>> load() async {
    final resp = await DioClient.dio.get('/agencies/branches', queryParameters: {'agencyType': agencyType});
    final list = (resp.data is Map) ? (resp.data['data'] as List? ?? const []) : const [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  await showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1F1247),
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setState) {
        final idCtrl = TextEditingController();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('فروع ${agency.agencyName}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('نفس النظام بدون امتلاك الوكالة — حتى 3 فروع', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _MiniField(controller: idCtrl, label: 'رقم المستخدم (ID)')),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        final id = int.tryParse(idCtrl.text.trim());
                        if (id == null) return;
                        try {
                          await DioClient.dio.post('/agencies/branches', data: {'userId': id, 'agencyType': agencyType});
                          idCtrl.clear();
                          setState(() {});
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت الإضافة كفرع')));
                          }
                        } catch (e) {
                          final msg = e is DioException ? (e.response?.data?['message'] ?? 'فشل الإضافة') : 'فشل الإضافة';
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg.toString())));
                          }
                        }
                      },
                      child: const Text('+ فرع'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: load(),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(),
                      );
                    }
                    final branches = snap.data!;
                    if (branches.isEmpty) {
                      return const Text('لا يوجد فروع حالياً', style: TextStyle(color: Colors.white70));
                    }
                    return Column(
                      children: branches.map((b) {
                        final u = (b['user'] as Map?) ?? const {};
                        return ListTile(
                          textColor: Colors.white,
                          leading: const Icon(Icons.person, color: Colors.white70),
                          title: Text((u['name'] ?? 'مستخدم').toString()),
                          subtitle: Text('#${u['displayId'] ?? b['userId']}', style: const TextStyle(color: Colors.white70)),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle, color: Colors.redAccent),
                            onPressed: () async {
                              try {
                                await DioClient.dio.delete(
                                  '/agencies/branches/${b['userId']}',
                                  queryParameters: {'agencyType': agencyType},
                                );
                                setState(() {});
                              } catch (_) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل الإزالة')));
                                }
                              }
                            },
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
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

Widget _buildAgencyGrid(
  List<ChargingAgency> items, {
  void Function(ChargingAgency agency)? onTap,
}) {
  return GridView.count(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    crossAxisCount: 2,
    mainAxisSpacing: 12,
    crossAxisSpacing: 12,
    childAspectRatio: 0.92,
    children: [
      for (final item in items) _AgencyGridCard(item, onTap: onTap),
    ],
  );
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

class _PreviewBox extends StatefulWidget {
  final XFile? file;
  const _PreviewBox({required this.file});

  @override
  State<_PreviewBox> createState() => _PreviewBoxState();
}

class _PreviewBoxState extends State<_PreviewBox> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _loadBytes();
  }

  @override
  void didUpdateWidget(_PreviewBox old) {
    super.didUpdateWidget(old);
    if (old.file?.path != widget.file?.path) _loadBytes();
  }

  Future<void> _loadBytes() async {
    if (widget.file == null) { setState(() => _bytes = null); return; }
    final b = await widget.file!.readAsBytes();
    if (mounted) setState(() => _bytes = b);
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes == null) {
      return Container(
        width: 72,
        height: 72,
        color: Colors.white.withOpacity(0.08),
        child: const Icon(Icons.cloud_upload_rounded, color: Colors.white70),
      );
    }

    return Image.memory(
      _bytes!,
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

// ========================== Providers / Controllers ==========================

/// ✅ Agency wallet balance (ChargingAgency.balanceCoins)
final agencyBalanceProvider = FutureProvider<int>((ref) async {
  final dio = DioClient.dio;
  final resp = await dio.get('/agencies/my-agency');
  final raw = resp.data is Map ? resp.data['data'] : null;
  // #8: /my-agency returns an array now. Coins live on the CHARGING (shipping)
  // agency, so report that one's balance; tolerate the old single-object shape.
  Map<String, dynamic>? charging;
  if (raw is List) {
    final maps = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    charging = maps.firstWhere(
      (m) => (m['type'] ?? '').toString().toUpperCase() == 'CHARGING',
      orElse: () => maps.isNotEmpty ? maps.first : <String, dynamic>{},
    );
  } else if (raw is Map) {
    charging = Map<String, dynamic>.from(raw);
  }
  final bal = charging?['balanceCoins'] ?? 0;
  return int.tryParse('$bal') ?? 0;
});

final chargingAgenciesProvider = FutureProvider<List<ChargingAgency>>((ref) async {
  final dio = DioClient.dio;
  try {
    final resp = await dio.get('/agencies/charging');
    final list = (resp.data['data'] as List? ?? const []).cast<Map<String, dynamic>>();
    return list.map((e) => ChargingAgency.fromJson(e)).toList();
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) {
      try {
        final resp = await dio.get('/charging-agencies', queryParameters: {'status': 'approved', 'type': 'CHARGING'});
        final list = (resp.data is List ? resp.data as List : (resp.data['data'] as List? ?? const []))
            .cast<Map<String, dynamic>>();
        return list.map((e) => ChargingAgency.fromJson(e)).toList();
      } on DioException {
        return [];
      }
    }
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
    if (e.response?.statusCode == 404) {
      try {
        final resp = await dio.get('/charging-agencies', queryParameters: {'status': 'approved', 'type': 'HOSTING'});
        final list = (resp.data is List ? resp.data as List : (resp.data['data'] as List? ?? const []))
            .cast<Map<String, dynamic>>();
        return list.map((e) => ChargingAgency.fromJson(e)).toList();
      } on DioException {
        return [];
      }
    }
    rethrow;
  }
});

// #2-4, #8: maps agencyId -> the caller's role in it ('OWNER' | 'BRANCH' | ...),
// across EVERY agency the user owns or is a branch of. Old code only ever
// looked at the first owned agency, so a user who owned/worked in more than
// one agency lost admin access to all but the first.
final myMembershipsProvider = FutureProvider<Map<int, String>>((ref) async {
  final dio = DioClient.dio;
  try {
    final resp = await dio.get('/agencies/my-memberships');
    final list = (resp.data is Map) ? (resp.data['data'] as List? ?? const []) : const [];
    final map = <int, String>{};
    for (final e in list) {
      if (e is! Map) continue;
      final agency = (e['agency'] as Map?) ?? const {};
      final id = agency['id'];
      final role = e['role'];
      if (id is int && role is String) map[id] = role;
    }
    return map;
  } on DioException {
    return {};
  }
});

final myAgenciesProvider = FutureProvider<List<ChargingAgency>>((ref) async {
  final dio = DioClient.dio;
  try {
    final resp = await dio.get('/agencies/my-agency');
    final raw = resp.data is Map ? resp.data['data'] : null;
    // #8: /my-agency now returns an ARRAY of every owned agency (hosting +
    // charging). Keep tolerating the old single-object shape too.
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => ChargingAgency.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    if (raw is Map && raw.isNotEmpty) {
      return [ChargingAgency.fromJson(Map<String, dynamic>.from(raw))];
    }
    return [];
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) {
      try {
        final resp = await dio.get('/charging-agencies/me');
        final list = (resp.data is List ? resp.data as List : (resp.data['data'] as List? ?? const []))
            .cast<Map<String, dynamic>>();
        return list.map((e) => ChargingAgency.fromJson(e)).toList();
      } on DioException {
        return [];
      }
    }
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
      try {
        await dio.post('/agencies/request', data: {
          'type': payload.type,
          'agencyName': payload.agencyName,
          'contactInfo': payload.phoneNumber,
          'imageUrl': agencyUrl,
        });
      } on DioException catch (e) {
        if (e.response?.statusCode != 404) rethrow;
        await dio.post('/charging-agencies', data: {
          'type': payload.type,
          'agencyName': payload.agencyName,
          'phoneNumber': payload.phoneNumber,
          'agencyImageUrl': agencyUrl,
          'idFrontUrl': agencyUrl,
          'idBackUrl': agencyUrl,
        });
      }

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
