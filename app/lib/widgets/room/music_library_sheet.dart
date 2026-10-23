import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/music_provider.dart';
import '../../l10n/tr.dart';

/// The sheet behind the "موسيقى" button in the room menu.
///
///   • رفع موسيقى من الهاتف — pick one or more audio files and upload them
///   • تشغيل الموسيقى       — start the whole library; tracks play back to
///                            back and loop to the first one when they finish
///   • the songs you own, each with a delete button — nothing is ever removed
///     automatically, only by the user
///
/// Playback is gated to the room owner and room admins; the sheet itself is
/// open to everyone so any user can still manage their own library.
class MusicLibrarySheet extends ConsumerStatefulWidget {
  const MusicLibrarySheet({
    super.key,
    required this.roomId,
    required this.canControl,
  });

  final int roomId;
  final bool canControl;

  @override
  ConsumerState<MusicLibrarySheet> createState() => _MusicLibrarySheetState();
}

class _MusicLibrarySheetState extends ConsumerState<MusicLibrarySheet> {
  static const _panel = Color(0xFF2A1655);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(musicLibraryProvider.notifier).load();
    });
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textDirection: TextDirection.rtl),
        backgroundColor: error ? Colors.red.shade700 : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pickAndUpload() async {
    FilePickerResult? result;
    try {
      // SPEC52 #21 — the system document picker (no storage permission is
      // asked for), limited to the formats the room plays: MP3/M4A/WAV/AAC.
      // file_picker copies the chosen document into the app cache, so even a
      // Drive/Downloads content:// item comes back with a readable path.
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['mp3', 'm4a', 'wav', 'aac'],
        allowMultiple: true,
      );
    } catch (e) {
      _snack(tr('تعذر فتح ملفات الهاتف', 'Unable to open phone files'), error: true);
      return;
    }
    // The file picker backgrounds the app; the sheet can be gone by the time it
    // returns ("Cannot use ref after the widget was disposed", 1.0.46).
    if (result == null || result.files.isEmpty || !mounted) return;

    final notifier = ref.read(musicLibraryProvider.notifier);
    var uploaded = 0;

    for (final file in result.files) {
      final path = file.path;
      if (path == null || path.isEmpty) {
        // Used to be skipped silently, which looked like "the picker does
        // nothing". Say why instead.
        _snack(tr('تعذر قراءة الملف "${file.name}" — اختره من مدير الملفات', 'Unable to read "${file.name}" — select it from the file manager'), error: true);
        continue;
      }
      if (file.size > 25 * 1024 * 1024) {
        _snack(tr('الملف "${file.name}" أكبر من 25MB', 'File "${file.name}" exceeds 25MB'), error: true);
        continue;
      }
      final title = file.name.replaceAll(RegExp(r'\.[^.]+$'), '');
      final track = await notifier.upload(path: path, title: title);
      if (!mounted) return;
      if (track != null) {
        uploaded++;
      } else {
        _snack(ref.read(musicLibraryProvider).error ?? tr('فشل رفع الأغنية', 'Failed to upload song'), error: true);
        notifier.clearError();
        break;
      }
    }

    if (uploaded > 0) _snack(tr('تم رفع $uploaded أغنية', 'Uploaded $uploaded songs'));
  }

  Future<void> _confirmDelete(int id, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: _panel,
          title: Text(tr('حذف الأغنية', 'Delete song'), style: TextStyle(color: Colors.white)),
          content: Text(
            tr('هل تريد حذف "$title" من قائمتك؟', 'Delete "$title" from your list?'),
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('إلغاء', 'Cancel'), style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('حذف', 'Delete'), style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final done = await ref.read(musicLibraryProvider.notifier).delete(id);
    _snack(done ? tr('تم حذف الأغنية', 'Song deleted') : tr('تعذر حذف الأغنية', 'Unable to delete song'), error: !done);
  }

  void _playFrom(int index) {
    if (!widget.canControl) {
      _snack(tr('تشغيل الموسيقى متاح لصاحب الغرفة والمشرفين فقط', 'Only the room owner and moderators can play music'), error: true);
      return;
    }
    final tracks = ref.read(musicLibraryProvider).tracks;
    if (tracks.isEmpty) {
      _snack(tr('ارفع أغنية أولاً', 'Upload a song first'), error: true);
      return;
    }
    ref.read(roomMusicProvider(widget.roomId).notifier).play(tracks, index: index);
    Navigator.of(context).maybePop();
    _snack(tr('جاري تشغيل الموسيقى في الغرفة', 'Playing music in the room'));
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(musicLibraryProvider);
    final music = ref.watch(roomMusicProvider(widget.roomId));
    final maxHeight = MediaQuery.of(context).size.height * 0.72;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: const BoxDecoration(
            color: _panel,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 50,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Icon(Icons.library_music, color: Colors.amber, size: 20),
                  SizedBox(width: 8),
                  Text(tr('الموسيقى', 'Music'), style: TextStyle(color: Colors.white, fontSize: 17)),
                ],
              ),
              const SizedBox(height: 14),

              if (library.uploading) ...[
                LinearProgressIndicator(
                  value: library.uploadProgress == 0 ? null : library.uploadProgress,
                  backgroundColor: Colors.white12,
                  color: Colors.amber,
                  minHeight: 3,
                ),
                const SizedBox(height: 10),
              ],

              _actionTile(
                icon: Icons.upload_file,
                label: tr('رفع موسيقى من الهاتف', 'Upload music from phone'),
                color: Colors.lightBlueAccent,
                onTap: library.uploading ? null : _pickAndUpload,
              ),
              const SizedBox(height: 8),
              _actionTile(
                icon: Icons.play_circle_fill,
                label: music.active ? tr('إعادة تشغيل القائمة', 'Restart playlist') : tr('تشغيل الموسيقى', 'Play music'),
                color: Colors.greenAccent,
                onTap: () => _playFrom(0),
              ),

              const SizedBox(height: 14),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 10),

              Row(
                children: [
                  Text(tr('الأغاني عندي', 'My songs'),
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const Spacer(),
                  if (library.tracks.isNotEmpty)
                    Text('${library.tracks.length}',
                        style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 6),

              Flexible(child: _buildList(library, music)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(MusicLibraryState library, RoomMusicState music) {
    if (library.loading && library.tracks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (library.tracks.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Text(
          tr('لا توجد أغاني بعد — ارفع أغنية من هاتفك', 'No songs yet — upload one from your phone'),
          style: TextStyle(color: Colors.white38, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      );
    }

    final playingUrl = music.active ? music.current?.url : null;

    return ListView.separated(
      shrinkWrap: true,
      itemCount: library.tracks.length,
      separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
      itemBuilder: (_, i) {
        final track = library.tracks[i];
        final isPlaying = playingUrl != null && playingUrl == track.url;
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            isPlaying ? Icons.graphic_eq : Icons.music_note,
            color: isPlaying ? Colors.greenAccent : Colors.white54,
            size: 20,
          ),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isPlaying ? Colors.greenAccent : Colors.white,
              fontSize: 13.5,
            ),
          ),
          onTap: () => _playFrom(i),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
            tooltip: tr('حذف', 'Delete'),
            onPressed: () => _confirmDelete(track.id, track.title),
          ),
        );
      },
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(enabled ? 0.06 : 0.03),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            Icon(icon, color: enabled ? color : color.withOpacity(0.4), size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: enabled ? Colors.white : Colors.white38,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
