import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/music_track.dart';
import 'dio_client.dart';

/// REST side of the room music feature: the user's own library.
/// Playback across the room is driven over the socket, not here.
class MusicService {
  Dio get _dio => DioClient.dio;

  Future<List<MusicTrack>> fetchMyTracks() async {
    final res = await _dio.get('music/tracks');
    final data = res.data;
    final raw = (data is Map ? data['tracks'] : null) ?? const [];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => MusicTrack.fromJson(Map<String, dynamic>.from(e)))
        .where((t) => t.url.isNotEmpty)
        .toList();
  }

  /// Uploads a file picked from the phone. [title] is the song name shown in
  /// the list — the stored filename on the server is randomised.
  Future<MusicTrack> uploadTrack({
    required String filePath,
    required String title,
    void Function(int sent, int total)? onProgress,
  }) async {
    final name = filePath.split(RegExp(r'[/\\]')).last;
    final form = FormData.fromMap({
      'title': title,
      'audio': await MultipartFile.fromFile(filePath, filename: name),
    });

    final res = await _dio.post(
      'music/tracks',
      data: form,
      onSendProgress: onProgress,
      options: Options(contentType: 'multipart/form-data'),
    );

    final data = res.data;
    final track = (data is Map) ? data['track'] : null;
    if (track is Map) {
      return MusicTrack.fromJson(Map<String, dynamic>.from(track));
    }
    throw Exception('فشل رفع الأغنية');
  }

  Future<void> deleteTrack(int id) async {
    await _dio.delete('music/tracks/$id');
    debugPrint('🎵 deleted track $id');
  }
}
