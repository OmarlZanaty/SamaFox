import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/staff_provider.dart';
import '../../services/staff_service.dart';
import '../../widgets/app_network_image.dart';

const staffGold = Color(0xFFFFD700);
const staffCardColor = Color(0xFF1A0E3E);
const staffRoles = {'MANAGER': 'Manager', 'SUPER_ADMIN': 'Super Admin', 'ADMIN': 'Admin'};
const staffStatuses = {'': 'كل الحالات', 'ACTIVE': '🟢 نشط', 'EXPIRED': '🔴 منتهي', 'REVOKED': 'ملغى'};
const banDurations = {'1d': 'يوم', '7d': 'أسبوع', '30d': 'شهر', '365d': 'سنة', 'permanent': 'أبدي'};
const permissionLabels = {
  'role_panel': 'نظام الإدارة', 'manage_admins': 'تعيين Admin',
  'grant_vip': 'منح VIP', 'grant_level': 'منح Level', 'grant_frame': 'منح إطار',
  'grant_entry': 'منح دخولية', 'grant_bubble': 'منح فقاعة دردشة',
  'manage_host_agency': 'تعيين وكالة مضيفين', 'follow_agencies': 'متابعة الوكالات', 'ban_users': 'نظام الحظر',
};
String dateLabel(DateTime? date) => date == null ? 'بلا نهاية' :
    '${date.toLocal().year}/${date.toLocal().month.toString().padLeft(2, '0')}/${date.toLocal().day.toString().padLeft(2, '0')} ${date.toLocal().hour.toString().padLeft(2, '0')}:${date.toLocal().minute.toString().padLeft(2, '0')}';
String statusLabel(String status) => staffStatuses[status] ?? (status == 'LIFTED' ? 'تم رفعه' : status);
void staffSnack(BuildContext context, String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text, textDirection: TextDirection.rtl)));
Future<T?> openStaff<T>(BuildContext context, Widget screen) => Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => screen));

abstract class StaffActionState<T extends ConsumerStatefulWidget> extends ConsumerState<T> {
  bool busy = false;
  int revision = 0;
  StaffService get service => ref.read(staffServiceProvider);
  StaffAccess? get access => ref.read(staffMeProvider).valueOrNull;
  void reload() { if (mounted) setState(() => revision++); }
  Future<bool> act(Future<void> Function() operation, {String message = 'تم تنفيذ العملية'}) async {
    if (busy) return false;
    setState(() => busy = true);
    try {
      await operation();
      if (!mounted) return false;
      staffSnack(context, message);
      reload();
      return true;
    } catch (e) {
      if (mounted) {
        staffSnack(context, staffError(e));
        if (e is DioException && e.response?.statusCode == 403) ref.invalidate(staffMeProvider);
      }
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

/// Each route checks its own permission. Closing an ancestor also dismisses
/// its forms/dialogs, so a revoked session cannot keep an actionable modal.
class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key, required this.title, required this.allowed, required this.child});
  final String title;
  final bool Function(StaffAccess) allowed;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(staffMeProvider);
    if (!state.isLoading && !state.hasError && (state.valueOrNull == null || !allowed(state.valueOrNull!))) {
      final route = ModalRoute.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted || route?.isActive != true) return;
        final navigator = Navigator.of(context);
        final messenger = ScaffoldMessenger.of(context);
        navigator.popUntil((r) => r == route);
        navigator.pop();
        messenger.showSnackBar(SnackBar(content: Text(title.contains('الحظر')
            ? 'نظام الحظر: مسحوب أو انتهت الصلاحية'
            : 'انتهى الوصول إلى هذه الشاشة أو تم سحب الصلاحية')));
      });
    }
    final theme = ThemeData.dark().copyWith(
      scaffoldBackgroundColor: const Color(0xFF100823),
      colorScheme: const ColorScheme.dark(primary: staffGold, onPrimary: Colors.black, secondary: staffGold, onSecondary: Colors.black, surface: staffCardColor),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    );
    return Theme(data: theme, child: Directionality(textDirection: TextDirection.rtl,
      child: Scaffold(appBar: AppBar(title: Text(title), backgroundColor: staffCardColor),
        body: state.hasError ? StaffRefreshList(onRefresh: () async { ref.invalidate(staffMeProvider); await ref.read(staffMeProvider.future); },
          children: [Text(staffError(state.error!)), TextButton(onPressed: () => ref.invalidate(staffMeProvider), child: const Text('إعادة المحاولة'))])
          : state.valueOrNull == null || !allowed(state.valueOrNull!)
            ? const Center(child: CircularProgressIndicator()) : child)));
  }
}

class StaffRefreshList extends StatelessWidget {
  const StaffRefreshList({super.key, required this.children, required this.onRefresh});
  final List<Widget> children;
  final Future<void> Function() onRefresh;
  @override
  Widget build(BuildContext context) => RefreshIndicator(onRefresh: () async {
    try { await onRefresh(); } catch (e) { if (context.mounted) staffSnack(context, staffError(e)); }
  }, child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16),
      children: children.map((w) => Padding(padding: const EdgeInsets.only(bottom: 12), child: w)).toList()));
}

class StaffLoad<T> extends ConsumerStatefulWidget {
  const StaffLoad({super.key, required this.load, required this.builder, this.revision = 0, this.header = const []});
  final Future<T> Function() load;
  final List<Widget> Function(T) builder;
  final int revision;
  final List<Widget> header;
  @override
  ConsumerState<StaffLoad<T>> createState() => _StaffLoadState<T>();
}
class _StaffLoadState<T> extends ConsumerState<StaffLoad<T>> {
  late Future<T> future = widget.load();
  @override
  void didUpdateWidget(covariant StaffLoad<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) future = widget.load();
  }
  Future<void> refresh() async {
    final next = widget.load();
    setState(() => future = next);
    // Both requests are observed even when one fails.
    await Future.wait([next, ref.refresh(staffMeProvider.future)]);
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(future: future, builder: (context, snapshot) {
    final children = <Widget>[...widget.header];
    if (snapshot.connectionState != ConnectionState.done) {
      children.add(const Center(child: CircularProgressIndicator()));
    } else if (snapshot.hasError) {
      children.addAll([Text(staffError(snapshot.error!)), TextButton(onPressed: () { setState(() => future = widget.load()); }, child: const Text('إعادة المحاولة'))]);
    } else {
      final content = widget.builder(snapshot.data as T);
      children.addAll(content.isEmpty ? [const Text('لا توجد بيانات')] : content);
    }
    return StaffRefreshList(onRefresh: refresh, children: children);
  });
}

Widget staffCard(String title, {String? subtitle, Widget? leading, Widget? trailing, VoidCallback? onTap}) =>
    Card(color: staffCardColor, child: ListTile(leading: leading, title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle), trailing: trailing, onTap: onTap));
Widget staffHeading(String title) => Text(title, style: const TextStyle(color: staffGold, fontSize: 18, fontWeight: FontWeight.bold));
Widget staffSelect(String label, String value, Map<String, String> choices, ValueChanged<String> onChanged) =>
    DropdownButtonFormField<String>(initialValue: value, isExpanded: true,
      decoration: InputDecoration(labelText: label), items: choices.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
      onChanged: (v) { if (v != null) onChanged(v); });
Widget staffAvatar(StaffUser user) => SizedBox(width: 44, height: 44,
    child: ClipOval(child: user.avatarUrl?.isNotEmpty == true
      ? AppNetworkImage(user.avatarUrl!, width: 44, height: 44, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.person))
      : const Icon(Icons.person)));
Widget staffUserCard(StaffUser user) => staffCard(user.label, leading: staffAvatar(user), subtitle: 'VIP ${user.vip} • Level ${user.level}');
Widget staffThumbnail(StaffItem item) => SizedBox(width: 48, height: 48, child: item.thumbnail == null
    ? const Icon(Icons.image_outlined) : AppNetworkImage(item.thumbnail!, width: 48, height: 48, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined)));

class StaffUserLookup extends ConsumerStatefulWidget {
  const StaffUserLookup({super.key, required this.onSelected});
  final ValueChanged<StaffUser?> onSelected;
  @override
  ConsumerState<StaffUserLookup> createState() => _StaffUserLookupState();
}
class _StaffUserLookupState extends ConsumerState<StaffUserLookup> {
  final controller = TextEditingController();
  StaffUser? user;
  bool busy = false;
  int generation = 0;
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  Future<void> search() async {
    final id = int.tryParse(controller.text.trim());
    if (id == null || id < 1) { staffSnack(context, 'أدخل ID صحيحاً'); return; }
    final request = ++generation;
    setState(() { busy = true; user = null; });
    widget.onSelected(null);
    try {
      final result = await ref.read(staffServiceProvider).lookup(id);
      if (!mounted || request != generation) return;
      setState(() => user = result);
      widget.onSelected(result);
    } catch (e) {
      if (mounted && request == generation) staffSnack(context, staffError(e));
    } finally {
      if (mounted && request == generation) setState(() => busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => Column(children: [
    TextField(controller: controller, keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: 'ID المستخدم', suffixIcon: IconButton(onPressed: busy ? null : search, icon: const Icon(Icons.search))),
      onSubmitted: (_) => search(), onChanged: (_) {
        generation++;
        setState(() { user = null; busy = false; });
        widget.onSelected(null);
      }),
    if (busy) const LinearProgressIndicator(),
    if (user != null) staffUserCard(user!),
  ]);
}

Future<bool> staffConfirm(BuildContext context, String title, String body) async =>
    await showDialog<bool>(context: context, builder: (ctx) => Directionality(textDirection: TextDirection.rtl,
      child: AlertDialog(title: Text(title), content: Text(body), actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
      ]))) ?? false;

Future<String?> staffPrompt(BuildContext context, String title, {String initial = '', int? maxDays, String? label, bool numeric = false}) async {
  final controller = TextEditingController(text: initial);
  final key = GlobalKey<FormState>();
  final result = await showDialog<String>(context: context, builder: (ctx) => Directionality(textDirection: TextDirection.rtl,
    child: AlertDialog(title: Text(title), content: Form(key: key, child: TextFormField(controller: controller,
      autofocus: true, keyboardType: maxDays == null && !numeric ? TextInputType.text : TextInputType.number,
      decoration: InputDecoration(labelText: label ?? (maxDays == null ? 'السبب' : 'عدد الأيام (1–$maxDays)')),
      validator: (value) {
        if (value == null || value.trim().isEmpty) return 'هذا الحقل مطلوب';
        if (numeric && (int.tryParse(value.trim()) ?? 0) < 1) return 'أدخل رقماً صحيحاً';
        if (maxDays != null) {
          final n = int.tryParse(value);
          if (n == null || n < 1 || n > maxDays) return 'أدخل من 1 إلى $maxDays يوم';
        }
        return null;
      })), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
      FilledButton(onPressed: () { if (key.currentState!.validate()) Navigator.pop(ctx, controller.text.trim()); }, child: const Text('تأكيد'))])));
  // The route's exit animation may still reference its controller.
  Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
  return result;
}

class StaffItemPicker extends StatelessWidget {
  const StaffItemPicker({super.key, required this.items, required this.selected, required this.onChanged, this.title = 'المنتجات المسموحة'});
  final List<StaffItem> items;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final String title;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    staffHeading(title), if (items.isEmpty && selected.isEmpty) const Text('لا توجد منتجات متاحة'),
    ...items.map((item) => CheckboxListTile(value: selected.contains(item.id), title: Text(item.name),
      subtitle: Text(item.id), secondary: staffThumbnail(item), onChanged: (enabled) {
        final next = {...selected};
        enabled == true ? next.add(item.id) : next.remove(item.id);
        onChanged(next);
      })),
    // Reward IDs outside the grantable pool have no metadata endpoint. Preserve
    // them and identify them honestly instead of silently dropping selections.
    ...selected.where((id) => !items.any((item) => item.id == id)).map((id) => CheckboxListTile(
      value: true, title: Text('منتج ID $id'), onChanged: (_) => onChanged({...selected}..remove(id)))),
  ]);
}

Widget permissionDuration(int days, ValueChanged<int> changed, {bool standalone = false}) => staffSelect(
    'مدة صلاحية الحظر', '$days', {'1': 'يوم', '7': 'أسبوع', '30': 'شهر', '365': 'سنة', '0': standalone ? 'أبدي' : 'حتى نهاية الإدارة'}, (v) => changed(int.parse(v)));
