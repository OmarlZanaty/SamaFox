import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/music_track.dart';
import '../services/music_service.dart';
import '../services/socket_service.dart';

// =====================================================================
// LIBRARY — "الأغاني اللي عندي"
// =====================================================================

class MusicLibraryState {
  final List<MusicTrack> tracks;
  final bool loading;
  final bool uploading;
  final double uploadProgress;
  final String? error;

  const MusicLibraryState({
    this.tracks = const [],
    this.loading = false,
    this.uploading = false,
    this.uploadProgress = 0,
    this.error,
  });

  MusicLibraryState copyWith({
    List<MusicTrack>? tracks,
    bool? loading,
    bool? uploading,
    double? uploadProgress,
    String? error,
    bool clearError = false,
  }) {
    return MusicLibraryState(
      tracks: tracks ?? this.tracks,
      loading: loading ?? this.loading,
      uploading: uploading ?? this.uploading,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// The library is per-user, not per-room: the same songs are there whichever
/// room you open, and nothing is removed unless the user deletes it.
class MusicLibraryNotifier extends StateNotifier<MusicLibraryState> {
  MusicLibraryNotifier(this._service) : super(const MusicLibraryState());

  final MusicService _service;

  Future<void> load({bool force = false}) async {
    if (state.loading) return;
    if (!force && state.tracks.isNotEmpty) return;

    state = state.copyWith(loading: true, clearError: true);
    try {
      final tracks = await _service.fetchMyTracks();
      state = state.copyWith(tracks: tracks, loading: false);
    } catch (e) {
      debugPrint('🎵 load library failed: $e');
      state = state.copyWith(loading: false, error: 'تعذر تحميل الأغاني');
    }
  }

  Future<MusicTrack?> upload({required String path, required String title}) async {
    state = state.copyWith(uploading: true, uploadProgress: 0, clearError: true);
    try {
      final track = await _service.uploadTrack(
        filePath: path,
        title: title,
        onProgress: (sent, total) {
          if (total > 0) {
            state = state.copyWith(uploadProgress: sent / total);
          }
        },
      );
      state = state.copyWith(
        tracks: [...state.tracks, track],
        uploading: false,
        uploadProgress: 0,
      );
      return track;
    } catch (e) {
      debugPrint('🎵 upload failed: $e');
      state = state.copyWith(
        uploading: false,
        uploadProgress: 0,
        error: _readableError(e, fallback: 'فشل رفع الأغنية'),
      );
      return null;
    }
  }

  Future<bool> delete(int id) async {
    final before = state.tracks;
    // Optimistic: the row disappears immediately, and comes back if the
    // request fails.
    state = state.copyWith(tracks: before.where((t) => t.id != id).toList());
    try {
      await _service.deleteTrack(id);
      return true;
    } catch (e) {
      debugPrint('🎵 delete failed: $e');
      state = state.copyWith(tracks: before, error: 'تعذر حذف الأغنية');
      return false;
    }
  }

  void clearError() => state = state.copyWith(clearError: true);

  /// The backend explains refusals in Arabic (size, format, 50-song cap);
  /// show that instead of a generic failure.
  String _readableError(Object e, {required String fallback}) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] != null) return data['message'].toString();
      if (e.error is String && (e.error as String).isNotEmpty) return e.error as String;
    }
    return fallback;
  }
}

final musicServiceProvider = Provider<MusicService>((ref) => MusicService());

final musicLibraryProvider =
    StateNotifierProvider<MusicLibraryNotifier, MusicLibraryState>((ref) {
  return MusicLibraryNotifier(ref.read(musicServiceProvider));
});

// =====================================================================
// ROOM PLAYBACK — synced across everyone in the room
// =====================================================================

class RoomMusicState {
  /// False = nothing is playing and the control bar must be hidden.
  final bool active;
  final List<MusicTrack> queue;
  final int index;
  final bool isPlaying;
  final int hostId;
  final String hostName;

  const RoomMusicState({
    this.active = false,
    this.queue = const [],
    this.index = 0,
    this.isPlaying = false,
    this.hostId = 0,
    this.hostName = '',
  });

  MusicTrack? get current =>
      (index >= 0 && index < queue.length) ? queue[index] : null;

  String get currentTitle => current?.title ?? '';
}

/// Mirrors the server's `room_music_state` and keeps the local audio player in
/// step with it. Everyone in the room runs this, which is what makes the same
/// song play for the whole room at the same position.
class RoomMusicNotifier extends StateNotifier<RoomMusicState> {
  RoomMusicNotifier(this.roomId) : super(const RoomMusicState()) {
    _player.setReleaseMode(ReleaseMode.stop);
    _completeSub = _player.onPlayerComplete.listen((_) => _reportEnded());
    _attachSocket();
    _socket.emit('music_sync', {'roomId': roomId});
  }

  final int roomId;
  final SocketService _socket = SocketService();
  final AudioPlayer _player = AudioPlayer();

  StreamSubscription<void>? _completeSub;
  StreamSubscription<void>? _reconnectSub;

  /// URL currently loaded into the player — avoids re-fetching the same file
  /// every time a state broadcast arrives.
  String? _loadedUrl;
  int _loadedIndex = -1;

  /// Position drift above this is corrected with a seek. Below it, leaving
  /// playback alone sounds better than a constant stutter.
  static const Duration _driftTolerance = Duration(milliseconds: 2500);

  void _attachSocket() {
    _socket.on('room_music_state', _onServerState);
    _socket.on('music_denied', _onDenied);
    // After a drop the local position has drifted (or the queue changed while
    // we were away) — ask the server where the room actually is.
    _reconnectSub = _socket.reconnectStream.listen((_) => resync());
  }

  final _deniedController = StreamController<String>.broadcast();

  /// Server refused a control action (not owner/admin).
  Stream<String> get deniedStream => _deniedController.stream;

  void _onDenied(dynamic data) {
    if (data is! Map) return;
    if (_notMyRoom(data)) return;
    final msg = (data['message'] ?? 'غير مسموح').toString();
    if (!_deniedController.isClosed) _deniedController.add(msg);
  }

  bool _notMyRoom(Map data) {
    final rid = data['roomId'];
    return rid != null && (rid is num ? rid.toInt() : int.tryParse('$rid')) != roomId;
  }

  Future<void> _onServerState(dynamic data) async {
    // Events can land after the room screen is gone (the socket listener is
    // global); writing `state` then would throw.
    if (!mounted) return;
    if (data is! Map) return;
    if (_notMyRoom(data)) return;

    final active = data['active'] == true;
    if (!active) {
      state = const RoomMusicState();
      _loadedUrl = null;
      _loadedIndex = -1;
      await _player.stop();
      return;
    }

    final rawTracks = data['tracks'];
    final queue = (rawTracks is List)
        ? rawTracks
            .whereType<Map>()
            .map((e) => MusicTrack.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <MusicTrack>[];

    final index = (data['index'] as num?)?.toInt() ?? 0;
    final isPlaying = data['isPlaying'] == true;
    final positionMs = (data['positionMs'] as num?)?.toInt() ?? 0;

    if (!mounted) return;
    state = RoomMusicState(
      active: true,
      queue: queue,
      index: index,
      isPlaying: isPlaying,
      hostId: (data['hostId'] as num?)?.toInt() ?? 0,
      hostName: (data['hostName'] ?? '').toString(),
    );

    await _applyToPlayer(positionMs: positionMs, isPlaying: isPlaying);
  }

  Future<void> _applyToPlayer({required int positionMs, required bool isPlaying}) async {
    final track = state.current;
    if (track == null) {
      await _player.stop();
      return;
    }

    final url = track.playbackUrl;
    final changedTrack = url != _loadedUrl || state.index != _loadedIndex;

    try {
      if (changedTrack) {
        _loadedUrl = url;
        _loadedIndex = state.index;
        await _player.stop();
        await _player.setSourceUrl(url);
        if (positionMs > 0) {
          await _player.seek(Duration(milliseconds: positionMs));
        }
        if (isPlaying) await _player.resume();
        return;
      }

      if (isPlaying) {
        final current = await _player.getCurrentPosition() ?? Duration.zero;
        final target = Duration(milliseconds: positionMs);
        if ((current - target).abs() > _driftTolerance) {
          await _player.seek(target);
        }
        await _player.resume();
      } else {
        await _player.pause();
        await _player.seek(Duration(milliseconds: positionMs));
      }
    } catch (e) {
      debugPrint('🎵 playback error: $e');
    }
  }

  void _reportEnded() {
    if (!state.active) return;
    // The server takes the first report and ignores the rest, so it is safe
    // for every listener to send this.
    _socket.emit('music_ended', {'roomId': roomId, 'index': state.index});
  }

  // ---- controls (server enforces owner/admin) ----

  void play(List<MusicTrack> tracks, {int index = 0}) {
    if (tracks.isEmpty) return;
    _socket.emit('music_play', {
      'roomId': roomId,
      'tracks': tracks.map((t) => t.toJson()).toList(),
      'index': index,
      'positionMs': 0,
    });
  }

  void pause() => _socket.emit('music_pause', {'roomId': roomId});
  void resume() => _socket.emit('music_resume', {'roomId': roomId});
  void next() => _socket.emit('music_next', {'roomId': roomId});
  void previous() => _socket.emit('music_prev', {'roomId': roomId});
  void stop() => _socket.emit('music_stop', {'roomId': roomId});

  void togglePlayPause() => state.isPlaying ? pause() : resume();

  /// Re-ask the server after a reconnect or when the app comes back.
  void resync() => _socket.emit('music_sync', {'roomId': roomId});

  @override
  void dispose() {
    _socket.off('room_music_state');
    _socket.off('music_denied');
    _reconnectSub?.cancel();
    _completeSub?.cancel();
    _deniedController.close();
    _player.stop();
    _player.dispose();
    super.dispose();
  }
}

/// autoDispose: leaving the room screen tears the player down, so the song
/// never keeps playing after you walk out of the room.
final roomMusicProvider =
    StateNotifierProvider.autoDispose.family<RoomMusicNotifier, RoomMusicState, int>(
  (ref, roomId) => RoomMusicNotifier(roomId),
);
