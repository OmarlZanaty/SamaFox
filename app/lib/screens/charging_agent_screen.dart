import '../services/agency_branch_service.dart';
import '../services/agency_service.dart';
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
import '../widgets/app_network_image.dart';
import 'agency_branches_screen.dart';
import 'chat_screen.dart';
import '../l10n/tr.dart';

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
  String _agencyQuery = '';

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

    // A user who belongs to an agency must see HIS agency's system only —
    // opening وكالتي / العمل كوكيل شحن / العمل كوكيل مضيفين used to dump the
    // full directory of approved agencies on him. Users with no agency (and
    // system admins) still browse the whole list, which is how they join one.
    final hasMembership = myRoles.isNotEmpty;
    final scopedToMine = hasMembership && !isSystemAdmin;
    List<ChargingAgency> scope(List<ChargingAgency> items) {
      final base = scopedToMine ? items.where((a) => myRoles.containsKey(a.id)).toList() : items;
      final q = _agencyQuery.trim().toLowerCase();
      if (q.isEmpty) return base;
      return base.where((a) {
        if (a.agencyName.toLowerCase().contains(q)) return true;
        for (final m in a.members) {
          final u = (m['user'] is Map ? m['user'] as Map : m);
          if ('${u['displayId'] ?? ''}'.toLowerCase().contains(q) || '${u['name'] ?? ''}'.toLowerCase().contains(q)) {
            return true;
          }
        }
        return false;
      }).toList();
    }

    // Once scoped, a section the user has no agency in is just an empty box —
    // hide it instead.
    final showCharging =
        (!needsChoice || _activeInterface == 'CHARGING') && (!scopedToMine || hasCharging);
    final showHosting =
        (!needsChoice || _activeInterface == 'HOSTING') && (!scopedToMine || hasHosting);

    return Scaffold(
      backgroundColor: const Color(0xFF1A0E3E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          tr('وكيل الشحن', 'Recharge agent'),
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
            ref.invalidate(agencyWalletProvider);
            ref.invalidate(agencyBalanceProvider);
            ref.invalidate(myAgenciesProvider);
            ref.invalidate(myMembershipsProvider);
            ref.invalidate(chargingAgenciesProvider);
            ref.invalidate(hostingAgenciesProvider);
          },
          child: !membershipsAsync.hasValue && membershipsAsync.isLoading
              // Wait for the memberships before drawing anything: rendering
              // early would flash the full agency directory at an agent.
              ? const Center(child: CircularProgressIndicator())
              : needsChoice && _activeInterface == null
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
                            tr('تبديل الواجهة (حالياً: ${_activeInterface == 'CHARGING' ? 'الشحن' : 'الاستضافة'})', 'Switch interface (current: ${_activeInterface == 'CHARGING' ? 'Recharge' : 'Hosting'})'),
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: _CreateAgencyButton(
                            label: tr('طلب تفعيل وكالة شحن', 'Request recharge agency'),
                            onTap: () => _handleCreateAgencyRequest(context, ref, type: 'CHARGING'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _CreateAgencyButton(
                            label: tr('طلب تفعيل وكالة مضيفين', 'Request hosting agency'),
                            onTap: () => _handleCreateAgencyRequest(context, ref, type: 'HOSTING'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      onChanged: (v) => setState(() => _agencyQuery = v),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search, color: Colors.white54),
                        hintText: tr('ابحث باسم الوكالة أو ID الوكيل', 'Search by agency name or agent ID'),
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white10,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (showCharging) ...[
                      _AgencySidePanel(
                        title: tr('وكالات الشحن', 'Recharge agencies'),
                        children: [
                          chargingAsync.when(
                            data: (all) {
                              final items = scope(all);
                              return items.isEmpty
                                  ? _emptyText(tr('لا توجد وكالات شحن معتمدة حالياً', 'No approved recharge agencies yet'))
                                  : _buildAgencyGrid(
                                      items,
                                      onTap: (agency) => _onAgencyTap(
                                        context,
                                        ref,
                                        agency,
                                        // Only the وكيل and his فروع can charge —
                                        // matching the backend. A plain member
                                        // used to be offered the charge sheet and
                                        // got a 403 the moment he used it.
                                        isAgencyAdmin: isSystemAdmin ||
                                            myRoles[agency.id] == 'OWNER' ||
                                            myRoles[agency.id] == 'BRANCH',
                                        isOwner: isSystemAdmin || myRoles[agency.id] == 'OWNER',
                                      ),
                                    );
                            },
                            loading: () => const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                            error: (_, __) => _emptyText(tr('تعذر تحميل وكالات الشحن حالياً', 'Unable to load recharge agencies')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (showHosting)
                      _AgencySidePanel(
                        title: tr('وكالات الاستضافة', 'Hosting agencies'),
                        children: [
                          hostingAsync.when(
                            data: (all) {
                              final items = scope(all);
                              return items.isEmpty
                                  ? _emptyText(tr('لا توجد وكالات استضافة معتمدة حالياً', 'No approved hosting agencies yet'))
                                  : _buildAgencyGrid(
                                      items,
                                      onTap: (agency) => _onAgencyTap(
                                        context,
                                        ref,
                                        agency,
                                        isAgencyAdmin: isSystemAdmin || myRoles.containsKey(agency.id),
                                        isOwner: isSystemAdmin || myRoles[agency.id] == 'OWNER',
                                      ),
                                    );
                            },
                            loading: () => const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                            error: (_, __) => _emptyText(tr('تعذر تحميل وكالات الاستضافة حالياً', 'Unable to load hosting agencies')),
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
            Row(
              children: [
                Expanded(
                  child: _CreateAgencyButton(
                    label: tr('طلب تفعيل وكالة شحن', 'Request recharge agency'),
                    onTap: () => _handleCreateAgencyRequest(context, ref, type: 'CHARGING'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CreateAgencyButton(
                    label: tr('طلب تفعيل وكالة مضيفين', 'Request hosting agency'),
                    onTap: () => _handleCreateAgencyRequest(context, ref, type: 'HOSTING'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              tr('تعمل كوكيل شحن ووكيل استضافة معاً — اختر الواجهة التي تريد العمل عليها الآن', 'You are both a recharge agent and a hosting agent — choose an interface to use now'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => setState(() => _activeInterface = 'CHARGING'),
                icon: const Icon(Icons.attach_money),
                label: Text(tr('العمل كوكيل شحن', 'Work as a recharge agent')),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => setState(() => _activeInterface = 'HOSTING'),
                icon: const Icon(Icons.mic),
                label: Text(tr('العمل كوكيل استضافة', 'Work as a hosting agent')),
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
    await _showChargingActions(context, ref, agency, isAgencyAdmin: isAgencyAdmin, isOwner: isOwner);
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
      SnackBar(content: Text(tr('✅ تم إرسال طلب إنشاء الوكالة (Pending)', '✅ Agency request submitted (Pending)'))),
    );
    ref.invalidate(myAgenciesProvider);
    ref.invalidate(myMembershipsProvider);
    ref.invalidate(chargingAgenciesProvider);
    ref.invalidate(hostingAgenciesProvider);
    ref.invalidate(agencyWalletProvider);
    ref.invalidate(agencyBalanceProvider);
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('❌ فشل إرسال الطلب، راجع السيرفر/الإنترنت', '❌ Request failed. Check your connection or try again'))),
    );
  }
}

Future<void> _showChargingActions(
  BuildContext context,
  WidgetRef ref,
  ChargingAgency agency, {
  required bool isAgencyAdmin,
  required bool isOwner,
}) async {
  final role = ref.read(myMembershipsProvider).valueOrNull?[agency.id];
  // Read once, before the sheet builds — ref.watch is only legal inside a
  // widget build. This is the seller's own wallet, فرع included.
  AgencyWalletBalance? wallet;
  if (isAgencyAdmin) {
    try {
      wallet = await ref.read(agencyWalletProvider.future);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(agencyErrorMessage(e))));
      return;
    }
  }
  if (!context.mounted) return;
  final agencyBalance = wallet?.agencyWalletCoins ?? 0;
  await showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1F1247),
    isScrollControlled: true,
    builder: (_) => SafeArea(
      child: SingleChildScrollView(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(agency.agencyName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (isAgencyAdmin) ...[
              Text(tr('رصيد الوكالة: $agencyBalance', 'Agency balance: $agencyBalance'), style: const TextStyle(color: Colors.white)),
              Text(tr('محفظتي الشخصية: ${wallet!.personalCoins}', 'My personal wallet: ${wallet!.personalCoins}'), style: const TextStyle(color: Colors.white)),
              if (wallet!.frozen)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: Colors.red.shade800,
                  child: Text(tr('رصيد الوكالة مجمّد من الإدارة', 'The agency balance is frozen by administration'), style: const TextStyle(color: Colors.white)),
                ),
              ListTile(
                textColor: Colors.white,
                enabled: !wallet!.frozen,
                title: Text(tr('تحويل إلى محفظتي الشخصية', 'Transfer to my personal wallet')),
                onTap: wallet!.frozen ? null : () async {
                  Navigator.pop(context);
                  await _withdrawAgencyCoins(context, ref);
                },
              ),
              ListTile(
                textColor: Colors.white,
                iconColor: Colors.white,
                leading: const Icon(Icons.request_page),
                title: Text(tr('طلب كوينز من الأدمن', 'Request coins from admin')),
                onTap: () async {
                  Navigator.pop(context);
                  await _requestCoinsFromAdmin(context);
                },
              ),
              ListTile(
                textColor: Colors.white,
                iconColor: Colors.white,
                leading: const Icon(Icons.send),
                title: Text(tr('إضافة كوينز لمستخدم', 'Add coins to a user')),
                // Owner and فرع each sell from their own wallet — quote it via
                // agencyBalanceProvider, which a branch could not read before.
                subtitle: Text(
                  tr('يُخصم من رصيد الوكالة: $agencyBalance كوينز', 'Deducted from the agency balance: $agencyBalance coins'),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                onTap: wallet!.frozen ? null : () async {
                  Navigator.pop(context);
                  await _sendAgencyCoinsToUser(context, ref);
                },
              ),
              // SPEC52 #36 — branches are real entities now (Branch ID, name,
              // owner, status). The owner manages them and sees every branch's
              // charges; a branch sees only its own. The server scopes both.
              if (role == 'OWNER' || role == 'BRANCH')
                ListTile(
                  textColor: Colors.white,
                  iconColor: Colors.white,
                  leading: const Icon(Icons.groups),
                  title: Text(role == 'OWNER' ? tr('الفروع (حتى 3)', 'Branches (up to 3)') : tr('فرعي وعمليات الشحن', 'My branch and recharges')),
                  onTap: () async {
                    Navigator.pop(context);
                    await Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => AgencyBranchesScreen(
                        agencyId: agency.id,
                        agencyName: agency.agencyName,
                        isOwner: role == 'OWNER',
                        service: AgencyBranchService(onInviteCreated: (message) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
                          }
                        }),
                      ),
                    ));
                  },
                ),
              if (isOwner) ...[
                // #7: backend already supported this for CHARGING agencies —
                // it just wasn't exposed from this screen (only the hosting
                // panel had the button).
                ListTile(
                  textColor: Colors.white,
                  iconColor: Colors.white,
                  leading: const Icon(Icons.swap_horiz),
                  title: Text(tr('نقل ملكية الوكالة', 'Transfer agency ownership')),
                  onTap: () async {
                    Navigator.pop(context);
                    await _transferAgencyOwnership(context, agencyType: 'CHARGING');
                  },
                ),
              ],
            ] else ...[
              for (final m in agency.members.where((m) => (m['role'] ?? 'OWNER') == 'OWNER'))
                Builder(builder: (ctx) {
                  final u = (m['user'] is Map ? (m['user'] as Map) : m).cast<String, dynamic>();
                  final uid = (u['id'] as num?)?.toInt();
                  return ListTile(
                    textColor: Colors.white,
                    leading: const Icon(Icons.verified_user, color: Colors.amberAccent),
                    title: Text('${u['name'] ?? ''}'),
                    subtitle: Text(tr('ID الوكيل: ${u['displayId'] ?? uid ?? ''}', 'Agent ID: ${u['displayId'] ?? uid ?? ''}'),
                        style: const TextStyle(color: Colors.white70)),
                    trailing: uid == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.message_rounded, color: Colors.lightBlueAccent),
                            tooltip: tr('رسالة للوكيل', 'Message the agent'),
                            onPressed: () {
                              Navigator.pop(ctx);
                              Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  partnerId: uid,
                                  partnerName: '${u['name'] ?? ''}',
                                  partnerAvatarUrl: u['avatarUrl']?.toString(),
                                  partnerOnline: false,
                                ),
                              ));
                            },
                          ),
                  );
                }),
              ListTile(
                textColor: Colors.white,
                iconColor: Colors.white70,
                leading: const Icon(Icons.phone),
                title: Text(agency.contactInfo.isEmpty ? tr('لا يوجد رقم تواصل', 'No contact number') : agency.contactInfo),
                subtitle: Text(tr('تواصل مع أدمن الوكالة للشحن', 'Contact the agency admin to recharge'), style: TextStyle(color: Colors.white70)),
              ),
            ],
          ],
        ),
      )),
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
              Text(tr('المستهدف: ${agency.targetCoins} | المحقق: ${agency.earnedCoins}', 'Target: ${agency.targetCoins} | Earned: ${agency.earnedCoins}'),
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              ...agency.members.map(
                (m) => ListTile(
                  dense: true,
                  textColor: Colors.white,
                  leading: const Icon(Icons.person, color: Colors.white70),
                  title: Text((m['name'] ?? tr('عضو', 'Member')).toString()),
                  subtitle: Text(tr('كوينز الغرف: -- | التارجت: --', 'Room coins: -- | Target: --'), style: TextStyle(color: Colors.white70)),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _openJoinRequestsManager(context);
                },
                child: Text(tr('طلبات الانضمام المعلقة', 'Pending join requests')),
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
                  label: Text(tr('الفروع (حتى 3)', 'Branches (up to 3)')),
                ),
              ],
            ] else ...[
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  await _requestJoinHostingAgency(context, agency.id);
                },
                icon: const Icon(Icons.group_add),
                label: Text(tr('طلب انضمام للوكالة', 'Request to join agency')),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

Future<void> _withdrawAgencyCoins(BuildContext context, WidgetRef ref) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _WithdrawAgencyDialog(onSuccess: (balance) async {
      ref.invalidate(agencyWalletProvider);
      ref.invalidate(agencyBalanceProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(
          'تم التحويل — رصيد الوكالة: ${balance.agencyWalletCoins}، محفظتي الشخصية: ${balance.personalCoins}',
          'Transfer complete — Agency balance: ${balance.agencyWalletCoins}, my personal wallet: ${balance.personalCoins}',
        ))));
      }
      try { await ref.read(authStateProvider.notifier).refreshMe(); } catch (_) {}
    }),
  );
}

class _WithdrawAgencyDialog extends StatefulWidget {
  const _WithdrawAgencyDialog({required this.onSuccess});
  final Future<void> Function(AgencyWalletBalance) onSuccess;

  @override
  State<_WithdrawAgencyDialog> createState() => _WithdrawAgencyDialogState();
}

class _WithdrawAgencyDialogState extends State<_WithdrawAgencyDialog> {
  final _amount = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final amount = int.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = tr('أدخل كمية صحيحة أكبر من صفر', 'Enter a valid amount greater than zero'));
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final response = await DioClient.dio.post('/charging-agencies/my/withdraw', data: {'amount': amount});
      final balance = AgencyWalletBalance.fromJson(response.data as Map);
      if (!mounted) return;
      Navigator.pop(context);
      await widget.onSuccess(balance);
    } catch (e) {
      if (mounted) setState(() { _error = agencyErrorMessage(e); _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(tr('تحويل إلى محفظتي الشخصية', 'Transfer to my personal wallet')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _amount,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: tr('الكمية', 'Amount')),
        ),
        if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
      ]),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: Text(tr('إلغاء', 'Cancel'))),
        ElevatedButton(onPressed: _busy ? null : _submit, child: Text(_busy ? tr('جارٍ التحويل', 'Transferring') : tr('تحويل', 'Transfer'))),
      ],
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
      title: Text(tr('طلب كوينز', 'Request coins'), style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MiniField(controller: amountCtrl, label: tr('الكمية', 'Amount')),
          const SizedBox(height: 8),
          _MiniField(controller: receiptCtrl, label: tr('رابط الإيصال', 'Receipt link')),
          const SizedBox(height: 8),
          _MiniField(controller: noteCtrl, label: tr('ملاحظة', 'Note')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('إلغاء', 'Cancel'))),
        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('إرسال', 'Send'))),
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
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('تم إرسال الطلب', 'Request sent'))));
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(agencyErrorMessage(e))));
  }
}

// #5-7: "إضافة كوينز" flow — enter the person's ID, THEY APPEAR (name/avatar)
// so the agent confirms it's the right person, then a box for the coin count,
// then إرسال. Replaces the old raw userId+amount dialog with no confirmation.
// Sales debit the agency wallet and the server selects the recipient wallet.
Future<void> _sendAgencyCoinsToUser(BuildContext context, WidgetRef ref) async {
  final idCtrl = TextEditingController();
  final amountCtrl = TextEditingController();
  Map<String, dynamic>? foundUser;
  bool searching = false;
  bool recipientIsAgent = false;
  String? error;

  // The wallet the charge is paid from — the caller's own, وكيل or فرع.
  int agencyBalance = 0;
  try {
    agencyBalance = await ref.read(agencyBalanceProvider.future);
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(agencyErrorMessage(e))));
    return;
  }
  if (!context.mounted) return;

  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        Future<void> doSearch() async {
          final q = idCtrl.text.trim();
          if (q.isEmpty) return;
          setState(() { searching = true; error = null; foundUser = null; });
          try {
            // includeSelf: an agent may charge their own personal wallet.
            final resp = await DioClient.dio.get('/agencies/search-user', queryParameters: {'q': q, 'includeSelf': 1});
            final list = (resp.data is Map) ? (resp.data['data'] as List? ?? const []) : const [];
            if (!context.mounted) return;
            if (list.isNotEmpty) {
              final user = Map<String, dynamic>.from(list.first as Map);
              final recipient = await DioClient.dio.get('/charging-agencies/recipient/${user['id']}');
              if (!context.mounted) return;
              setState(() {
                foundUser = user;
                // Charging yourself always lands in your personal wallet.
                recipientIsAgent = recipient.data['isChargingAgent'] == true &&
                    user['id'] != ref.read(authStateProvider).user?.id;
                searching = false;
              });
            } else {
              setState(() { error = tr('لم يتم العثور على مستخدم بهذا الرقم', 'No user found with this ID'); searching = false; });
            }
          } catch (e) {
            if (!context.mounted) return;
            setState(() { error = agencyErrorMessage(e); searching = false; });
          }
        }

        return AlertDialog(
          backgroundColor: const Color(0xFF1F1247),
          title: Text(tr('إضافة كوينز', 'Add coins'), style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  tr('رصيد الوكالة: $agencyBalance كوينز', 'Agency balance: $agencyBalance coins'),
                  style: const TextStyle(color: Color(0xFFFFD700), fontSize: 13),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _MiniField(controller: idCtrl, label: tr('رقم المستخدم (ID)', 'User ID'))),
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
                        ? appImage(foundUser!['avatarUrl'].toString(), 40)
                        : null,
                    child: (foundUser!['avatarUrl'] ?? '').toString().isEmpty
                        ? const Icon(Icons.person)
                        : null,
                  ),
                  title: Text((foundUser!['name'] ?? '').toString(), style: const TextStyle(color: Colors.white)),
                  subtitle: Text('#${foundUser!['displayId'] ?? foundUser!['id']}', style: const TextStyle(color: Colors.white70)),
                ),
                const SizedBox(height: 8),
                Text(recipientIsAgent ? tr('سيُضاف إلى رصيد وكالته', 'Will be added to their agency balance') : tr('سيُضاف إلى محفظته الشخصية', 'Will be added to their personal wallet'), style: const TextStyle(color: Colors.white70)),
                _MiniField(controller: amountCtrl, label: tr('عدد الكوينز', 'Number of coins')),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr('إلغاء', 'Cancel'))),
            ElevatedButton(
              onPressed: foundUser == null ? null : () {
                final amount = int.tryParse(amountCtrl.text.trim());
                if (amount == null || amount <= 0) {
                  setState(() => error = tr('أدخل كمية صحيحة أكبر من صفر', 'Enter a valid amount greater than zero'));
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: Text(tr('إرسال', 'Send')),
            ),
          ],
        );
      },
    ),
  );
  if (ok != true || foundUser == null) return;
  try {
    final response = await DioClient.dio.post('/agencies/send-coins', data: {
      'userId': foundUser!['id'],
      'amount': int.tryParse(amountCtrl.text.trim()) ?? 0,
    });
    // The charge just moved coins — pull the fresh balances so the next charge
    // (and the profile) don't show the pre-charge number.
    try { await ref.read(authStateProvider.notifier).refreshMe(); } catch (_) {}
    ref.invalidate(agencyWalletProvider);
    ref.invalidate(agencyBalanceProvider);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text((response.data['wallet'] ?? response.data['data']?['wallet']) == 'agency' ? tr('تم الشحن إلى رصيد وكالته', 'Recharged their agency balance') : tr('تم الشحن إلى محفظته الشخصية', 'Recharged their personal wallet'))));
  } catch (e) {
    final message = agencyErrorMessage(e);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
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
              setState(() { error = tr('لم يتم العثور على مستخدم بهذا الرقم', 'No user found with this ID'); searching = false; });
            }
          } catch (e) {
            if (!context.mounted) return;
            setState(() { error = agencyErrorMessage(e); searching = false; });
          }
        }

        return AlertDialog(
          backgroundColor: const Color(0xFF1F1247),
          title: Text(tr('نقل ملكية الوكالة', 'Transfer agency ownership'), style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr('ستفقد صلاحيات الوكيل وتصبح مضيفاً في هذه الوكالة.', 'You will lose agent permissions and become a host in this agency.'),
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _MiniField(controller: idCtrl, label: tr('رقم المستخدم الجديد (ID)', 'New user ID'))),
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
                        ? appImage(foundUser!['avatarUrl'].toString(), 40)
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
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr('إلغاء', 'Cancel'))),
            ElevatedButton(
              onPressed: foundUser == null ? null : () => Navigator.pop(dialogContext, true),
              child: Text(tr('نقل', 'Transfer')),
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
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('تم نقل الملكية بنجاح', 'Ownership transferred successfully'))));
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(agencyErrorMessage(e))));
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
                Text(tr('فروع ${agency.agencyName}', '${agency.agencyName} branches'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(tr('نفس النظام بدون امتلاك الوكالة — حتى 3 فروع', 'Same system without agency ownership — up to 3 branches'), style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _MiniField(controller: idCtrl, label: tr('رقم المستخدم (ID)', 'User ID'))),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        final q = idCtrl.text.trim();
                        if (q.isEmpty) return;
                        try {
                          // The number the owner types is the ID he SEES on the
                          // profile (displayId), not the internal row id the
                          // endpoint wants. Posting it raw made every addition
                          // fail with "User not found" — or, worse, hand the
                          // فرع to whoever happened to hold that internal id.
                          // Resolve it first, exactly like the hosting panel.
                          final search = await DioClient.dio
                              .get('/agencies/search-user', queryParameters: {'q': q, 'agencyType': agencyType});
                          final found = (search.data is Map)
                              ? (search.data['data'] as List? ?? const [])
                              : const [];
                          if (found.isEmpty) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(tr('لم يتم العثور على مستخدم بهذا الرقم', 'No user found with this ID'))),
                              );
                            }
                            return;
                          }
                          final id = ((found.first as Map)['id'] as num).toInt();
                          final message = await AgencyService().addBranch(id, agencyType: agencyType);
                          idCtrl.clear();
                          setState(() {});
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
                          }
                        } catch (e) {
                          final msg = agencyErrorMessage(e);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg.toString())));
                          }
                        }
                      },
                      child: Text(tr('+ فرع', '+ Branch')),
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
                      return Text(tr('لا يوجد فروع حالياً', 'No branches yet'), style: TextStyle(color: Colors.white70));
                    }
                    return Column(
                      children: branches.map((b) {
                        final u = (b['user'] as Map?) ?? const {};
                        return ListTile(
                          textColor: Colors.white,
                          leading: const Icon(Icons.person, color: Colors.white70),
                          title: Text((u['name'] ?? tr('مستخدم', 'User')).toString()),
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
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('فشل الإزالة', 'Failed to remove'))));
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
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('تم إرسال طلب الانضمام', 'Join request sent'))));
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('لا يمكن إرسال الطلب حالياً', 'Unable to send request right now'))));
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
            title: Text((requester['name'] ?? tr('مستخدم', 'User')).toString()),
            subtitle: Text('ID: ${requester['displayId'] ?? requester['id'] ?? '-'}'),
            trailing: Wrap(
              spacing: 4,
              children: [
                TextButton(
                  onPressed: () async {
                    await DioClient.dio.patch('/agencies/join-requests/${r['id']}/review', data: {'action': 'accept'});
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Text(tr('قبول', 'Accept')),
                ),
                TextButton(
                  onPressed: () async {
                    await DioClient.dio.patch('/agencies/join-requests/${r['id']}/review', data: {'action': 'reject'});
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Text(tr('رفض', 'Reject')),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(agencyErrorMessage(e))));
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
        SnackBar(content: Text(tr('من فضلك ارفع صورة الوكالة.', 'Please upload an agency image.'))),
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
                          widget.type == 'HOSTING' ? tr('إنشاء وكالة استضافة', 'Create hosting agency') : tr('إنشاء وكالة شحن', 'Create recharge agency'),
                          textAlign: TextAlign.right,
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 14),

                        _Field(
                          controller: _agencyName,
                          label: tr('اسم الوكالة', 'Agency name'),
                          icon: Icons.storefront,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return tr('اكتب اسم الوكالة', 'Enter agency name');
                            if (v.trim().length < 3) return tr('اسم الوكالة قصير جدًا', 'Agency name is too short');
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        _Field(
                          controller: _phone,
                          label: tr('رقم الهاتف', 'Phone number'),
                          icon: Icons.phone,
                          keyboardType: TextInputType.phone,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return tr('اكتب رقم الهاتف', 'Enter phone number');
                            if (v.trim().length < 8) return tr('رقم الهاتف غير صحيح', 'Invalid phone number');
                            return null;
                          },
                        ),

                        const SizedBox(height: 14),

                        _ImagePickTile(
                          title: tr('صورة الوكالة / اللوجو', 'Agency image / logo'),
                          file: _agencyImage,
                          onPick: _chooseAgencyImage,
                        ),
                        const SizedBox(height: 10),

                        Row(
                          children: [
                            Expanded(
                              child: _ImagePickTile(
                                title: tr('البطاقة (الأمام)', 'ID card (front)'),
                                file: _idFront,
                                onPick: _chooseFront,
                                compact: true,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _ImagePickTile(
                                title: tr('البطاقة (الخلف)', 'ID card (back)'),
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
                          child: Text(tr('إلغاء', 'Cancel')),
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
                              : Text(tr('إرسال الطلب', 'Send request')),
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
                    file == null ? tr('اضغط للرفع', 'Tap to upload') : tr('تم الرفع ✅', 'Uploaded ✅'),
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
                    : AppNetworkImage(
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
                tr('الأعضاء: ${a.memberCount}', 'Members: ${a.memberCount}'),
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

class AgencyWalletBalance {
  const AgencyWalletBalance(this.agencyWalletCoins, this.personalCoins, this.frozen);
  final int agencyWalletCoins;
  final int personalCoins;
  final bool frozen;

  factory AgencyWalletBalance.fromJson(Map data) => AgencyWalletBalance(
    int.tryParse('${data['agencyWalletCoins'] ?? data['balanceCoins'] ?? 0}') ?? 0,
    int.tryParse('${data['personalCoins'] ?? 0}') ?? 0,
    data['frozen'] == true,
  );
}

final agencyWalletProvider = FutureProvider<AgencyWalletBalance>((ref) async {
  final response = await DioClient.dio.get('/charging-agencies/my/balance');
  return AgencyWalletBalance.fromJson(response.data as Map);
});

final agencyBalanceProvider = FutureProvider<int>((ref) async {
  return (await ref.watch(agencyWalletProvider.future)).agencyWalletCoins;
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
      ref.invalidate(agencyWalletProvider);
    ref.invalidate(agencyBalanceProvider);

      return true;
    } catch (e) {
      return false;
    } finally {
      state = false;
    }
  }
}
