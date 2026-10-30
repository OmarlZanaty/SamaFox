import '../services/dio_client.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../services/agency_service.dart';
import '../widgets/app_network_image.dart';
import '../l10n/tr.dart';

/// Hosting-agency panel.
/// Agent (وكيل): search users by ID and invite them, see members with their
/// target earnings, remove members, control the exit lock and its coin price,
/// and transfer the whole system to another user.
/// Host (مضيف): sees his agency and can leave (paying the exit fee if locked).
class AgencyPanelScreen extends StatefulWidget {
  /// Which agency this panel acts on. Passed by the وكالتي chooser when the
  /// user has more than one; null lets the server pick (older entry points).
  const AgencyPanelScreen({super.key, this.agencyType});

  final String? agencyType;

  @override
  State<AgencyPanelScreen> createState() => _AgencyPanelScreenState();
}

class _AgencyPanelScreenState extends State<AgencyPanelScreen> {
  final _service = AgencyService();
  final _searchCtrl = TextEditingController();
  final _exitPriceCtrl = TextEditingController();
  final _branchIdCtrl = TextEditingController();

  bool _loading = true;
  Map<String, dynamic>? _membership; // my role + agency
  Map<String, dynamic>? _stats; // agent-only: agency + members
  List<Map<String, dynamic>> _searchResults = const [];
  bool _searching = false;
  bool _exitLocked = false;

  bool get _isAgent => (_membership?['role'] ?? '') == 'OWNER';

  /// A فرع has the same host-management rights as the owner.
  bool get _canManage {
    final role = _membership?['role'] ?? '';
    return role == 'OWNER' || role == 'BRANCH';
  }

  /// Which of the caller's agencies this panel acts on. Sent with every call so
  /// a user who also owns a charging agency never gets that one by mistake.
  /// The type the caller asked for wins; otherwise fall back to whatever the
  /// loaded membership turned out to be.
  String get _agencyType =>
      widget.agencyType ??
      (_membership?['agency']?['type'] as String?) ??
      'HOSTING';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _exitPriceCtrl.dispose();
    _branchIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final membership = await _service.getMyMembership(agencyType: widget.agencyType);
    Map<String, dynamic>? stats;
    // A فرع (BRANCH) manages hosts exactly like the owner, so it must see the
    // roster too — the backend already allows it. Pass the agency type so a
    // user who also owns a charging agency doesn't get that one's members.
    final role = membership?['role'];
    if (membership != null && (role == 'OWNER' || role == 'BRANCH')) {
      stats = await _service.getMembersStats(
        agencyType: widget.agencyType ??
            (membership['agency']?['type'] as String?) ??
            'HOSTING',
      );
    }
    if (!mounted) return;
    setState(() {
      _membership = membership;
      _stats = stats;
      final agency = stats?['agency'] ?? membership?['agency'];
      _exitLocked = (agency?['exitLocked'] ?? false) == true;
      _exitPriceCtrl.text = '${agency?['exitPriceCoins'] ?? 0}';
      _loading = false;
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    try {
      final results = await _service.searchUser(q, agencyType: _agencyType);
      if (mounted) setState(() => _searchResults = results);
    } catch (e) {
      _toast(agencyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _invite(Map<String, dynamic> user) async {
    try {
      final inv = await _service.inviteUser((user['id'] as num).toInt(), agencyType: _agencyType);
      if (inv['canResend'] == true && inv['id'] != null) {
        // SPEC52 #35 — still pending: resend or cancel instead of an error.
        final id = (inv['id'] as num).toInt();
        if (!mounted) return;
        final choice = await showDialog<String>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(tr('الدعوة ما زالت بانتظار الرد', 'Invitation awaiting response')),
            content: Text(tr('دعوة ${user['name']} لم يُرد عليها بعد.', '${user['name']} has not responded to the invitation yet.')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, 'cancel'), child: Text(tr('إلغاء الدعوة', 'Cancel invitation'))),
              TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('رجوع', 'Back'))),
              FilledButton(onPressed: () => Navigator.pop(c, 'resend'), child: Text(tr('إعادة إرسال', 'Resend'))),
            ],
          ),
        );
        if (choice == 'resend') {
          await _service.resendInvite(id);
          _toast(tr('✓ تمت إعادة إرسال الدعوة', '✓ Invitation resent'));
        } else if (choice == 'cancel') {
          await _service.cancelInvite(id);
          _toast(tr('تم إلغاء الدعوة', 'Invitation canceled'));
        }
        return;
      }
      _toast(tr('✓ تم إرسال الدعوة إلى ${user['name']}', '✓ Invitation sent to ${user['name']}'));
    } catch (e) {
      _toast(agencyErrorMessage(e));
    }
  }

  /// SPEC52 #35 — rename the agency / change its picture (the server keeps
  /// old → new, who and when; a name locked by the admins cannot change).
  Future<void> _editAgencyProfile(Map agency) async {
    final id = (agency['id'] as num?)?.toInt() ?? (agency['agencyId'] as num?)?.toInt();
    if (id == null) return;
    final ctrl = TextEditingController(text: '${agency['agencyName'] ?? ''}');
    String? imageUrl;
    final save = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(tr('بيانات الوكالة', 'Agency details')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: ctrl, decoration: InputDecoration(labelText: tr('اسم الوكالة', 'Agency name'))),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.image),
              label: Text(imageUrl == null ? tr('تغيير صورة الوكالة', 'Change agency image') : tr('تم اختيار صورة ✓', 'Image selected ✓')),
              onPressed: () async {
                final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1024);
                if (picked == null) return;
                try {
                  final form = FormData.fromMap({'image': await MultipartFile.fromFile(picked.path)});
                  final r = await DioClient.dio.post('/upload/image', data: form);
                  final url = (r.data is Map ? (r.data['url'] ?? r.data['imageUrl']) : null)?.toString();
                  if (url != null) set(() => imageUrl = url);
                } catch (_) {
                  _toast(tr('تعذر رفع الصورة', 'Unable to upload image'));
                }
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('إلغاء', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('حفظ', 'Save'))),
          ],
        ),
      ),
    );
    if (save != true) return;
    try {
      final newName = ctrl.text.trim();
      await _service.updateAgencyProfile(id,
          name: newName.isNotEmpty && newName != '${agency['agencyName'] ?? ''}' ? newName : null, imageUrl: imageUrl);
      _toast(tr('✓ تم تحديث بيانات الوكالة', '✓ Agency details updated'));
      _load();
    } catch (e) {
      _toast(agencyErrorMessage(e));
    }
  }

  Future<void> _removeMember(Map<String, dynamic> member) async {
    final user = member['user'] as Map? ?? {};
    final yes = await _confirm(tr('إزالة مضيف', 'Remove host'), tr('سيتم إخراج ${user['name']} من الوكالة. متابعة؟', '${user['name']} will be removed from the agency. Continue?'));
    if (yes != true) return;
    try {
      await _service.removeMember((user['id'] as num).toInt(), agencyType: _agencyType);
      _toast(tr('✓ تمت الإزالة', '✓ Removed'));
      _load();
    } catch (e) {
      _toast(agencyErrorMessage(e));
    }
  }

  Future<void> _saveExitSettings() async {
    try {
      await _service.setExitSettings(
        exitLocked: _exitLocked,
        exitPriceCoins: int.tryParse(_exitPriceCtrl.text.trim()) ?? 0,
        // Set the fee on the agency this panel is showing, not on whichever
        // one the server would have picked.
        agencyType: _agencyType,
      );
      _toast(tr('✓ تم حفظ إعدادات الخروج', '✓ Exit settings saved'));
    } catch (e) {
      _toast(agencyErrorMessage(e));
    }
  }

  Future<void> _transferOwnership() async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A1A5E),
        title: Text(tr('نقل ملكية الوكالة', 'Transfer agency ownership'), style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr('أدخل ID المستخدم الجديد. ستفقد صلاحيات الوكيل وتصبح مضيفاً.', 'Enter the new user ID. You will lose agent permissions and become a host.'),
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(hintText: tr('ID المستخدم', 'User ID')),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('إلغاء', 'Cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('نقل', 'Transfer'))),
        ],
      ),
    );
    if (confirmed != true) return;
    final q = ctrl.text.trim();
    if (q.isEmpty) return;
    try {
      final results = await _service.searchUser(q, agencyType: _agencyType);
      if (results.isEmpty) {
        _toast(tr('لم يتم العثور على المستخدم', 'User not found'));
        return;
      }
      await _service.transferOwnership((results.first['id'] as num).toInt(), agencyType: _agencyType);
      _toast(tr('✓ تم نقل الملكية', '✓ Ownership transferred'));
      _load();
    } catch (e) {
      _toast(agencyErrorMessage(e));
    }
  }

  /// Owner-only: add/remove the فروع who share host-management access.
  Future<void> _manageBranches() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1F1247),
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> reload() async => setSheet(() {});
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(tr('الفروع', 'Branches'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(tr('نفس صلاحيات إدارة المضيفين بدون امتلاك الوكالة — حتى 3 فروع', 'Same host management permissions without agency ownership — up to 3 branches'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 14),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _service.listBranches(agencyType: _agencyType),
                    builder: (c, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final branches = snap.data ?? const [];
                      if (branches.isEmpty) {
                        return Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text(tr('لا يوجد فروع حالياً', 'No branches yet'),
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white70)),
                        );
                      }
                      return Column(
                        children: branches.map((b) {
                          final user = (b['user'] as Map?) ?? b;
                          final uid = (b['userId'] ?? user['id']) as num?;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const CircleAvatar(child: Icon(Icons.person)),
                            title: Text(tr('${user['name'] ?? 'عضو'}', '${user['name'] ?? 'Member'}'),
                                style: const TextStyle(color: Colors.white)),
                            subtitle: Text('#${user['displayId'] ?? uid ?? ''}',
                                style: const TextStyle(color: Colors.white54)),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.redAccent),
                              onPressed: uid == null
                                  ? null
                                  : () async {
                                      try {
                                        await _service.removeBranch(uid.toInt(),
                                            agencyType: _agencyType);
                                        _toast(tr('✓ تم إلغاء الفرع', '✓ Branch removed'));
                                        await reload();
                                      } catch (e) {
                                        _toast(agencyErrorMessage(e));
                                      }
                                    },
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 6),
                  Text(tr('إضافة فرع بالـ ID', 'Add branch by ID'),
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _branchIdCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: tr('ID المستخدم', 'User ID'),
                            hintStyle: const TextStyle(color: Colors.white38),
                            filled: true,
                            fillColor: Colors.black26,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6B4CE6)),
                        onPressed: () async {
                          final q = _branchIdCtrl.text.trim();
                          if (q.isEmpty) return;
                          try {
                            // Resolve by display ID / name first, the same way
                            // invites do, so the owner types the ID they see.
                            final results =
                                await _service.searchUser(q, agencyType: _agencyType);
                            if (results.isEmpty) {
                              _toast(tr('لم يتم العثور على المستخدم', 'User not found'));
                              return;
                            }
                            final message = await _service.addBranch(
                                (results.first['id'] as num).toInt(),
                                agencyType: _agencyType);
                            _branchIdCtrl.clear();
                            _toast(message);
                            await reload();
                          } catch (e) {
                            _toast(agencyErrorMessage(e));
                          }
                        },
                        child: Text(tr('إضافة', 'Add'), style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (mounted) _load();
  }

  Future<void> _leave() async {
    final agency = _membership?['agency'] as Map? ?? {};
    final locked = agency['exitLocked'] == true;
    final price = (agency['exitPriceCoins'] as num?)?.toInt() ?? 0;
    // The dialog quotes THIS agency's fee, so the request must name the same
    // agency — otherwise the user could be promised a fee and leave another.
    final agencyId = (agency['id'] as num?)?.toInt();
    final name = (agency['agencyName'] ?? '').toString();
    final body = locked && price > 0
        ? tr('الخروج من وكالة $name مقفول — ستدفع $price كوينز للمغادرة. متابعة؟', 'Leaving $name agency is locked — you will pay $price coins to leave. Continue?')
        : tr('هل تريد مغادرة وكالة $name؟', 'Leave $name agency?');
    final yes = await _confirm(tr('مغادرة الوكالة', 'Leave agency'), body);
    if (yes != true) return;
    try {
      final paid = await _service.leaveAgency(
        agencyId: agencyId,
        agencyType: agencyId == null ? _agencyType : null,
      );
      _toast(paid > 0 ? tr('✓ غادرت الوكالة بعد دفع $paid كوينز', '✓ Left the agency after paying $paid coins') : tr('✓ غادرت الوكالة', '✓ Left the agency'));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _toast(agencyErrorMessage(e));
    }
  }

  Future<bool?> _confirm(String title, String body) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A1A5E),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(body, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('إلغاء', 'Cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('تأكيد', 'Confirm'))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A0E3E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _isAgent ? tr('لوحة الوكيل', 'Agent panel') : (_canManage ? tr('لوحة الفرع', 'Branch panel') : tr('وكالتي', 'My agency')),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh, color: Colors.white)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _membership == null
              ? Center(
                  child: Text(tr('أنت لست عضواً في أي وكالة', 'You are not a member of any agency'),
                      style: TextStyle(color: Colors.white70, fontSize: 16)),
                )
              : _canManage
                  ? _agentView()
                  : _memberView(),
    );
  }

  Widget _card({required Widget child}) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF2A1A5E).withOpacity(0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF6B4CE6).withOpacity(0.3)),
        ),
        child: child,
      );

  /// تارجت الوكيل — goal set on the agency by the platform admin, progress is
  /// the agency's whole production (all hosts' gift earnings combined).
  Widget _agencyTargetCard(Map agency) {
    final goal = (agency['targetGoalCoins'] as num?)?.toInt() ?? 0;
    final earned = (agency['earnedCoins'] as num?)?.toInt() ?? 0;
    final remaining = (agency['remainingCoins'] as num?)?.toInt() ?? 0;
    final progress = goal > 0 ? (earned / goal).clamp(0.0, 1.0).toDouble() : 0.0;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.flag, color: Color(0xFFFFD700), size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr('تارجت الوكيل', 'Agent target'),
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              Text(
                goal > 0 ? '$earned / $goal' : '$earned',
                style: const TextStyle(
                    color: Color(0xFFFFD700), fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (goal > 0) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              remaining > 0
                  ? tr('متبقٍ $remaining كوينز لإغلاق تارجت الوكالة', '$remaining coins left to reach the agency target')
                  : tr('اكتمل تارجت الوكالة 🎉', 'Agency target reached 🎉'),
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ] else
            Text(tr('إجمالي إنتاج الوكالة — لم يحدد الأدمن تارجت بعد', 'Total agency earnings — the admin has not set a target yet'),
                style: TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _agentView() {
    final agency = _stats?['agency'] as Map? ?? {};
    final members = (_stats?['members'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card(
          child: Row(
            children: [
              const Icon(Icons.workspace_premium, color: Color(0xFFFFD700), size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${agency['agencyName'] ?? ''}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(_isAgent ? tr('وكيل', 'Agent') : tr('فرع', 'Branch'),
                        style: const TextStyle(color: Color(0xFFFFD700), fontSize: 13)),
                  ],
                ),
              ),
              // Ownership actions belong to the owner alone — a فرع manages
              // hosts but never owns or hands over the agency.
              if (_isAgent)
                IconButton(
                  tooltip: tr('تعديل اسم وصورة الوكالة', 'Edit agency name and image'),
                  icon: const Icon(Icons.edit, color: Colors.white70),
                  onPressed: () => _editAgencyProfile(agency),
                ),
              if (_isAgent)
                TextButton(
                  onPressed: _transferOwnership,
                  child: Text(tr('نقل الملكية', 'Transfer ownership'), style: TextStyle(color: Colors.orangeAccent)),
                ),
            ],
          ),
        ),

        // The agency's own target — the agent's, as opposed to each host's.
        _agencyTargetCard(agency),

        // Invite by ID
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('دعوة مستخدم (بالـ ID)', 'Invite user (by ID)'),
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: tr('ID المستخدم أو الاسم', 'User ID or name'),
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.black26,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none),
                      ),
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _searching ? null : _search,
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6B4CE6)),
                    child: _searching
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(tr('بحث', 'Search'), style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
              ..._searchResults.map((u) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundImage: (u['avatarUrl'] ?? '').toString().isNotEmpty
                          ? appImage(u['avatarUrl'], 40)
                          : null,
                      child: (u['avatarUrl'] ?? '').toString().isEmpty
                          ? const Icon(Icons.person)
                          : null,
                    ),
                    title: Text('${u['name'] ?? ''}', style: const TextStyle(color: Colors.white)),
                    subtitle: Text('#${u['displayId'] ?? u['id']}',
                        style: const TextStyle(color: Colors.white54)),
                    trailing: u['isMember'] == true
                        ? Text(tr('عضو', 'Member'), style: TextStyle(color: Colors.greenAccent))
                        : ElevatedButton(
                            onPressed: () => _invite(u),
                            style:
                                ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4ECDC4)),
                            child: Text(tr('دعوة', 'Invite'), style: TextStyle(color: Colors.black)),
                          ),
                  )),
            ],
          ),
        ),

        // Branches (فرع) — owner-only: who gets the same management access.
        if (_isAgent)
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('الفروع (حتى 3)', 'Branches (up to 3)'),
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(tr('نفس صلاحيات إدارة المضيفين بدون امتلاك الوكالة', 'Same host management permissions without agency ownership'),
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _manageBranches,
                    icon: const Icon(Icons.groups, color: Colors.white),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6B4CE6)),
                    label: Text(tr('إدارة الفروع', 'Manage branches'), style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),

        // Exit policy — owner-only (the backend gates it on OWNER too).
        if (_isAgent)
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('إعدادات خروج الأعضاء', 'Member exit settings'),
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _exitLocked,
                onChanged: (v) => setState(() => _exitLocked = v),
                title: Text(tr('قفل الخروج (يدفع المضيف رسوماً للمغادرة)', 'Lock exit (hosts pay a fee to leave)'),
                    style: TextStyle(color: Colors.white70, fontSize: 14)),
                activeColor: const Color(0xFF6B4CE6),
              ),
              if (_exitLocked)
                TextField(
                  controller: _exitPriceCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: tr('رسوم الخروج (كوينز)', 'Exit fee (coins)'),
                    labelStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveExitSettings,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6B4CE6)),
                  child: Text(tr('حفظ', 'Save'), style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),

        // Members + targets
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('المضيفون (${members.where((m) => m['role'] != 'OWNER').length})', 'Hosts (${members.where((m) => m['role'] != 'OWNER').length})'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              if (members.where((m) => m['role'] != 'OWNER').isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child:
                      Text(tr('لا يوجد مضيفون بعد', 'No hosts yet'), style: TextStyle(color: Colors.white54)),
                ),
              ...members.where((m) => m['role'] != 'OWNER').map((m) {
                final user = m['user'] as Map? ?? {};
                final target = (m['targetCoins'] as num?)?.toInt() ?? 0;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundImage: (user['avatarUrl'] ?? '').toString().isNotEmpty
                        ? appImage(user['avatarUrl'], 40)
                        : null,
                    child: (user['avatarUrl'] ?? '').toString().isEmpty
                        ? const Icon(Icons.person)
                        : null,
                  ),
                  title:
                      Text('${user['name'] ?? ''}', style: const TextStyle(color: Colors.white)),
                  subtitle: Text(
                    tr('#${user['displayId'] ?? user['id']} — التارجت: $target كوينز', '#${user['displayId'] ?? user['id']} — Target: $target coins'),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.person_remove, color: Colors.redAccent),
                    onPressed: () => _removeMember(m),
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _memberView() {
    final agency = _membership?['agency'] as Map? ?? {};
    final locked = agency['exitLocked'] == true;
    final price = (agency['exitPriceCoins'] as num?)?.toInt() ?? 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card(
          child: Column(
            children: [
              const Icon(Icons.mic_rounded, color: Color(0xFF4ECDC4), size: 48),
              const SizedBox(height: 8),
              Text('${agency['agencyName'] ?? ''}',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              Text(tr('مضيف', 'Host'), style: TextStyle(color: Color(0xFF4ECDC4))),
              const SizedBox(height: 12),
              if (locked && price > 0)
                Text(tr('الخروج مقفول — رسوم المغادرة: $price كوينز', 'Exit locked — leaving fee: $price coins'),
                    style: const TextStyle(color: Colors.orangeAccent, fontSize: 13)),
            ],
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _leave,
            icon: const Icon(Icons.logout, color: Colors.white),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            label: Text(tr('مغادرة الوكالة', 'Leave agency'),
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}
