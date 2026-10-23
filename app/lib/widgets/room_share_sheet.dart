import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../services/dio_client.dart';
import '../services/room_share_service.dart';
import '../l10n/tr.dart';

class RoomShareSheet extends StatefulWidget {
  final int roomId;
  const RoomShareSheet({super.key, required this.roomId});

  static Future<void> show(BuildContext context, int roomId) => showModalBottomSheet<void>(
    context: context, isScrollControlled: true, useSafeArea: true,
    builder: (_) => RoomShareSheet(roomId: roomId),
  );

  @override
  State<RoomShareSheet> createState() => _RoomShareSheetState();
}

class _RoomShareSheetState extends State<RoomShareSheet> {
  final _selected = <int>{};
  final _people = <int, String>{};
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _url;
  String _requestId = const Uuid().v4();

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    // Independent sources: recent conversations remain usable if friends fail.
    await Future.wait([
      () async {
        try {
          final r = await DioClient.dio.get('messages/conversations');
          for (final p in r.data as List) { _people[(p['partnerId'] as num).toInt()] = p['partnerName'].toString(); }
        } catch (_) { _error = tr('تعذر تحميل بعض المحادثات', 'Unable to load some conversations'); }
      }(),
      () async {
        try {
          final r = await DioClient.dio.get('friends');
          for (final p in r.data['data'] as List) { _people[(p['id'] as num).toInt()] = p['name'].toString(); }
        } catch (_) { _error = tr('تعذر تحميل بعض الأصدقاء', 'Unable to load some friends'); }
      }(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try { await action(); } catch (e) {
      if (mounted) setState(() => _error = RoomShareService.errorMessage(e));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<String> _link() async => _url ??= (await RoomShareService.create(widget.roomId))['url'] as String;

  @override
  Widget build(BuildContext context) => SafeArea(child: Directionality(
    textDirection: TextDirection.rtl,
    child: SizedBox(height: MediaQuery.sizeOf(context).height * .78, child: Column(children: [
      Padding(padding: EdgeInsets.all(16), child: Text(tr('مشاركة الغرفة', 'Share room'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
      Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) :
        _people.isEmpty ? Center(child: Text(tr('لا توجد محادثات أو أصدقاء', 'No conversations or friends'))) : ListView(
          children: _people.entries.map((p) => CheckboxListTile(
            title: Text(p.value), value: _selected.contains(p.key),
            onChanged: _busy ? null : (value) => setState(() {
              if (value == true && _selected.length < 30) { _selected.add(p.key); } else { _selected.remove(p.key); }
              _requestId = const Uuid().v4();
            }),
          )).toList(),
        )),
      FilledButton.icon(onPressed: _busy || _selected.isEmpty ? null : () => _run(() async {
        await RoomShareService.create(widget.roomId, recipients: _selected.toList(), requestId: _requestId);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('تم إرسال الدعوة', 'Invitation sent'))));
          Navigator.pop(context);
        }
      }), icon: const Icon(Icons.send), label: Text(tr('إرسال في SamaFox (${_selected.length})', 'Send in SamaFox (${_selected.length})'))),
      Flexible(child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.chat), title: const Text('WhatsApp'), enabled: !_busy,
          onTap: () => _run(() async {
            final text = tr('انضم إلى غرفتي في SamaFox\n${await _link()}', 'Join my room in SamaFox\n${await _link()}');
            bool opened = false;
            try { opened = await launchUrl(Uri.parse('whatsapp://send?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication); } catch (_) {}
            if (!opened) await Share.share(text);
          })),
        ListTile(leading: const Icon(Icons.copy), title: Text(tr('نسخ الرابط', 'Copy link')), enabled: !_busy,
          onTap: () => _run(() async {
            await Clipboard.setData(ClipboardData(text: await _link()));
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('تم نسخ الرابط', 'Link copied'))));
          })),
        ListTile(leading: const Icon(Icons.share), title: Text(tr('مشاركة…', 'Share…')), enabled: !_busy,
          onTap: () => _run(() async { await Share.share(tr('انضم إلى غرفتي في SamaFox\n${await _link()}', 'Join my room in SamaFox\n${await _link()}')); })),
      ]))),
    ])),
  ));
}
