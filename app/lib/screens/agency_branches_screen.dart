import '../l10n/tr.dart';
import 'package:flutter/material.dart';

import '../services/agency_branch_service.dart';

String _date(dynamic value) {
  final date = DateTime.tryParse('$value')?.toLocal();
  if (date == null) return tr('غير مسجل', "Not recorded");
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}/${two(date.month)}/${two(date.day)} '
      '${two(date.hour)}:${two(date.minute)}';
}

String _status(dynamic value) => switch (value) {
      'ACTIVE' => tr('نشط', "Active"),
      'SUSPENDED' => tr('موقوف', "Suspended"),
      'CLOSED' => tr('مغلق', "Closed"),
      _ => tr('غير معروف', "Unknown"),
    };

void _error(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(AgencyBranchService.errorMessage(error))),
  );
}

class AgencyBranchesScreen extends StatefulWidget {
  const AgencyBranchesScreen({
    super.key,
    required this.agencyId,
    required this.agencyName,
    required this.isOwner,
    this.service,
  });

  final int agencyId;
  final String agencyName;
  // Presentation only: the API rechecks membership for reads and mutations.
  final bool isOwner;
  final AgencyBranchService? service;

  @override
  State<AgencyBranchesScreen> createState() => _AgencyBranchesScreenState();
}

class _AgencyBranchesScreenState extends State<AgencyBranchesScreen> {
  late final _service = widget.service ?? AgencyBranchService();
  List<Map<String, dynamic>> _branches = [];
  bool _loading = true;
  bool _changing = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
      _branches = [];
    });
    try {
      final rows = await _service.branches(widget.agencyId);
      if (mounted) setState(() => _branches = rows);
    } catch (error) {
      if (!mounted) return;
      setState(() => _failure = AgencyBranchService.errorMessage(error));
      _error(context, error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([Map<String, dynamic>? branch]) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BranchEditor(
        service: _service,
        agencyId: widget.agencyId,
        branch: branch,
      ),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _toggle(Map<String, dynamic> branch) async {
    final activating = branch['status'] != 'ACTIVE';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(activating ? tr('تفعيل الفرع', "Activate branch") : tr('إيقاف الفرع', "Suspend branch")),
          content: Text(tr('${branch['name']}\n'
              '${activating ? 'السماح للفرع بالشحن مجدداً؟' : 'إيقاف الشحن من هذا الفرع؟'}', "${branch['name']}\n${activating ? 'Allow this branch to recharge again?' : 'Stop recharges from this branch?'}")),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('إلغاء', "Cancel")),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('تأكيد', "Confirm")),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _changing = true);
    try {
      await _service.update(
        widget.agencyId,
        (branch['id'] as num).toInt(),
        status: activating ? 'ACTIVE' : 'SUSPENDED',
      );
      if (mounted) await _load();
    } catch (error) {
      if (mounted) _error(context, error);
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  void _transfers([Map<String, dynamic>? branch]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AgencyBranchTransfersScreen(
          agencyId: widget.agencyId,
          agencyName: widget.agencyName,
          branchId: (branch?['id'] as num?)?.toInt(),
          branchName: branch?['name'] as String?,
          service: _service,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(widget.isOwner ? tr('الفروع', "Branches") : tr('فرعي', "My branch"))),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _loading || _changing ? () async {} : _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  tr('الوكالة الأم: ${widget.agencyName} (#${widget.agencyId})', "Parent agency: ${widget.agencyName} (#${widget.agencyId})"),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (widget.isOwner)
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _loading || _changing || _failure != null
                            ? null
                            : () => _edit(),
                        icon: const Icon(Icons.add),
                        label: Text(tr('إنشاء فرع', "Create branch")),
                      ),
                      TextButton.icon(
                        onPressed: _loading || _failure != null
                            ? null
                            : () => _transfers(),
                        icon: const Icon(Icons.receipt_long),
                        label: Text(tr('كل عمليات الشحن', "All recharges")),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                if (_loading || _changing) const LinearProgressIndicator(),
                if (_failure != null)
                  _Retry(message: _failure!, onRetry: _load)
                else if (!_loading && _branches.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      tr('لا توجد فروع حالياً', "No branches yet"),
                      textAlign: TextAlign.center,
                    ),
                  ),
                for (final branch in _branches) _branchCard(branch),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _branchCard(Map<String, dynamic> branch) {
    final owner = branch['owner'] as Map? ?? const {};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${branch['name']}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(tr('رقم الفرع: ${branch['id']}', "Branch ID: ${branch['id']}")),
            Text(tr('المالك: ${owner['name'] ?? 'غير متاح'}', "Owner: ${owner['name'] ?? 'Unavailable'}")),
            Text(
              tr('رقم المستخدم: ${owner['displayId'] ?? owner['id'] ?? branch['ownerUserId']}', "User ID: ${owner['displayId'] ?? owner['id'] ?? branch['ownerUserId']}"),
            ),
            Text(tr('الحالة: ${_status(branch['status'])}', "Status: ${_status(branch['status'])}")),
            Text(tr('تاريخ الإنشاء: ${_date(branch['createdAt'])}', "Created: ${_date(branch['createdAt'])}")),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _changing ? null : () => _transfers(branch),
                  icon: const Icon(Icons.receipt_long),
                  label: Text(tr('عمليات الشحن', "Recharges")),
                ),
                if (widget.isOwner) ...[
                  TextButton(
                    onPressed: _changing ? null : () => _edit(branch),
                    child: Text(tr('تغيير الاسم', "Rename")),
                  ),
                  TextButton(
                    onPressed: _changing ? null : () => _toggle(branch),
                    child:
                        Text(branch['status'] == 'ACTIVE' ? tr('إيقاف', "Stop") : tr('تفعيل', "Activate")),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BranchEditor extends StatefulWidget {
  const _BranchEditor({
    required this.service,
    required this.agencyId,
    this.branch,
  });
  final AgencyBranchService service;
  final int agencyId;
  final Map<String, dynamic>? branch;

  @override
  State<_BranchEditor> createState() => _BranchEditorState();
}

class _BranchEditorState extends State<_BranchEditor> {
  final _form = GlobalKey<FormState>();
  late final _name =
      TextEditingController(text: widget.branch?['name'] as String?);
  final _ownerId = TextEditingController();
  Map<String, dynamic>? _owner;
  bool _internalId = false;
  bool _busy = false;
  String? _failure;

  @override
  void dispose() {
    _name.dispose();
    _ownerId.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    setState(() {
      _busy = true;
      _owner = null;
      _failure = null;
    });
    try {
      final owner = await widget.service.resolveOwner(
        _ownerId.text,
        internalId: _internalId,
      );
      if (mounted) setState(() => _owner = owner);
    } catch (error) {
      if (mounted) {
        setState(() => _failure = AgencyBranchService.errorMessage(error));
        _error(context, error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      if (widget.branch == null) {
        await widget.service.create(
          widget.agencyId,
          _name.text,
          (_owner!['id'] as num).toInt(),
        );
      } else {
        await widget.service.update(
          widget.agencyId,
          (widget.branch!['id'] as num).toInt(),
          name: _name.text,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _failure = AgencyBranchService.errorMessage(error));
        _error(context, error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          scrollable: true,
          title: Text(widget.branch == null ? tr('إنشاء فرع', "Create branch") : tr('تغيير اسم الفرع', "Rename branch")),
          content: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  enabled: !_busy,
                  maxLength: 120,
                  decoration: InputDecoration(labelText: tr('اسم الفرع', "Branch name")),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? tr('أدخل اسم الفرع', "Enter branch name")
                      : null,
                ),
                if (widget.branch == null) ...[
                  DropdownButtonFormField<bool>(
                    initialValue: _internalId,
                    isExpanded: true,
                    decoration:
                        InputDecoration(labelText: tr('نوع رقم المالك', "Owner ID type")),
                    items: [
                      DropdownMenuItem(
                        value: false,
                        child: Text(tr('رقم الملف الشخصي', "Profile ID")),
                      ),
                      DropdownMenuItem(
                        value: true,
                        child: Text(tr('المعرف الداخلي (ID)', "Internal ID")),
                      ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                              _internalId = value ?? false;
                              _owner = null;
                            }),
                  ),
                  TextFormField(
                    controller: _ownerId,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    decoration:
                        InputDecoration(labelText: tr('رقم مالك الفرع', "Branch owner ID")),
                    onChanged: (_) => setState(() => _owner = null),
                  ),
                  TextButton.icon(
                    onPressed: _busy ? null : _lookup,
                    icon: const Icon(Icons.search),
                    label: Text(tr('تحقق من المستخدم', "Verify user")),
                  ),
                  if (_owner != null)
                    Text(tr('مالك الفرع: ${_owner!['name']}\n'
                        'رقم المستخدم: ${_owner!['displayId'] ?? _owner!['id']}', "Branch owner: ${_owner!['name']}\nUser ID: ${_owner!['displayId'] ?? _owner!['id']}")),
                ],
                if (_busy) const LinearProgressIndicator(),
                if (_failure != null)
                  Text(
                    _failure!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: Text(tr('إلغاء', "Cancel")),
            ),
            FilledButton(
              onPressed: _busy || (widget.branch == null && _owner == null)
                  ? null
                  : _save,
              child: Text(tr('حفظ', "Save")),
            ),
          ],
        ),
      ),
    );
  }
}

class AgencyBranchTransfersScreen extends StatefulWidget {
  const AgencyBranchTransfersScreen({
    super.key,
    required this.agencyId,
    required this.agencyName,
    required this.service,
    this.branchId,
    this.branchName,
  });
  final int agencyId;
  final String agencyName;
  final int? branchId;
  final String? branchName;
  final AgencyBranchService service;

  @override
  State<AgencyBranchTransfersScreen> createState() =>
      _AgencyBranchTransfersScreenState();
}

class _AgencyBranchTransfersScreenState
    extends State<AgencyBranchTransfersScreen> {
  final _rows = <Map<String, dynamic>>[];
  bool _loading = false;
  bool _hasMore = false;
  String? _failure;
  int? _cursor;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failure = null;
      if (!more) {
        _rows.clear();
        _cursor = null;
        _hasMore = false;
      }
    });
    try {
      final page = await widget.service.transfers(
        widget.agencyId,
        branchId: widget.branchId,
        beforeId: more ? _cursor : null,
      );
      if (!mounted) return;
      setState(() {
        final ids = _rows.map((row) => row['id']).toSet();
        _rows.addAll(page.where((row) => ids.add(row['id'])));
        final next = page.isEmpty ? null : (page.last['id'] as num).toInt();
        _hasMore = page.length == AgencyBranchService.transferPageSize &&
            next != _cursor;
        _cursor = next;
      });
    } catch (error) {
      if (!mounted) return;
      // Do not leave a previously loaded ledger visible after access is revoked.
      setState(() {
        _rows.clear();
        _cursor = null;
        _hasMore = false;
        _failure = AgencyBranchService.errorMessage(error);
      });
      _error(context, error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(widget.branchName ?? tr('كل عمليات الشحن', "All recharges"))),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: _rows.length + 1,
              itemBuilder: (context, index) {
                if (index < _rows.length) return _transfer(_rows[index]);
                if (_loading) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (_failure != null) {
                  return _Retry(message: _failure!, onRetry: _load);
                }
                if (_rows.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.all(24),
                    child:
                        Text(tr('لا توجد عمليات شحن', "No recharges"), textAlign: TextAlign.center),
                  );
                }
                return _hasMore
                    ? TextButton(
                        onPressed: () => _load(more: true),
                        child: Text(tr('تحميل المزيد', "Load more")),
                      )
                    : const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _transfer(Map<String, dynamic> row) {
    final branch = row['branch'] as Map?;
    final user = row['toUser'] as Map? ?? const {};
    final branchId = row['branchId'];
    final branchLabel = branchId != null
        ? tr('${branch?['name'] ?? widget.branchName ?? 'فرع'} (#$branchId)', "${branch?['name'] ?? widget.branchName ?? 'Branch'} (#$branchId)")
        : row['actorUserId'] == null
            ? tr('غير منسوب (سجل قديم)', "Unassigned (old record)")
            : tr('الوكالة الرئيسية', "Main agency");
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('الوكالة الأم: ${widget.agencyName} '
                '(#${row['parentAgencyId'] ?? row['agencyId']})', "Parent agency: ${widget.agencyName} (#${row['parentAgencyId'] ?? row['agencyId']})")),
            Text(tr('الفرع: $branchLabel', "Branch: $branchLabel")),
            Text(tr('المستخدم: ${user['name'] ?? 'غير متاح'} '
                '(#${user['displayId'] ?? user['id'] ?? row['toUserId']})', "User: ${user['name'] ?? 'Unavailable'} (#${user['displayId'] ?? user['id'] ?? row['toUserId']})")),
            // This API stores amount in coins, not fiat. Do not invent a rate.
            Text(tr('المبلغ: ${row['amount']} كوينز', "Amount: ${row['amount']} coins")),
            Text(tr('الكوينز: ${row['coins'] ?? row['amount']}', "Coins: ${row['coins'] ?? row['amount']}")),
            Text(tr('الوقت: ${_date(row['createdAt'])}', "Time: ${_date(row['createdAt'])}")),
            Text(tr('رقم المعاملة: ${row['transactionId'] ?? 'غير مسجل'}', "Transaction ID: ${row['transactionId'] ?? 'Not recorded'}")),
            Text(tr('رقم سجل الشحن: ${row['id']}', "Recharge record ID: ${row['id']}")),
          ],
        ),
      ),
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(message, textAlign: TextAlign.center),
          TextButton(onPressed: onRetry, child: Text(tr('إعادة المحاولة', "Retry"))),
        ],
      ),
    );
  }
}
