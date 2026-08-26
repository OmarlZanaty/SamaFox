import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/music_provider.dart';

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
      result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
      );
    } catch (e) {
      _snack('تعذر فتح ملفات الهاتف', error: true);
      return;
    }
    if (result == null || result.files.isEmpty) return;

    final notifier = ref.read(musicLibraryProvider.notifier);
    var uploaded = 0;

    for (final file in result.files) {
      final path = file.path;
      if (path == null || path.isEmpty) continue;
      final title = file.name.replaceAll(RegExp(r'\.[^.]+$'), '');
      final track = await notifier.upload(path: path, title: title);
      if (track != null) {
        uploaded++;
      } else {
        _snack(ref.read(musicLibraryProvider).error ?? 'فشل رفع الأغنية', error: true);
        notifier.clearError();
        break;
      }
    }

    if (uploaded > 0) _snack('تم رفع $uploaded أغنية');
  }

  Future<void> _confirmDelete(int id, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: _panel,
          title: const Text('حذف الأغنية', style: TextStyle(color: Colors.white)),
          content: Text(
            'هل تريد حذف "$title" من قائمتك؟',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء', style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final done = await ref.read(musicLibraryProvider.notifier).delete(id);
    _snack(done ? 'تم حذف الأغنية' : 'تعذر حذف الأغنية', error: !done);
  }

  void _playFrom(int index) {
    if (!widget.canControl) {
      _snack('تشغيل الموسيقى متاح لصاحب الغرفة والمشرفين فقط', error: true);
      return;
    }
    final tracks = ref.read(musicLibraryProvider).tracks;
    if (tracks.isEmpty) {
      _snack('ارفع أغنية أولاً', error: true);
      return;
    }
    ref.read(roomMusicProvider(widget.roomId).notifier).play(tracks, index: index);
    Navigator.of(context).maybePop();
    _snack('جاري تشغيل الموسيقى في الغرفة');
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

              const Row(
                children: [
                  Icon(Icons.library_music, color: Colors.amber, size: 20),
                  SizedBox(width: 8),
                  Text('الموسيقى', style: TextStyle(color: Colors.white, fontSize: 17)),
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
                label: 'رفع موسيقى من الهاتف',
                color: Colors.lightBlueAccent,
                onTap: library.uploading ? null : _pickAndUpload,
              ),
              const SizedBox(height: 8),
              _actionTile(
                icon: Icons.play_circle_fill,
                label: music.active ? 'إعادة تشغيل القائمة' : 'تشغيل الموسيقى',
                color: Colors.greenAccent,
                onTap: () => _playFrom(0),
              ),

              const SizedBox(height: 14),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 10),

              Row(
                children: [
                  const Text('الأغاني عندي',
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
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Text(
          'لا توجد أغاني بعد — ارفع أغنية من هاتفك',
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
            tooltip: 'حذف',
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
