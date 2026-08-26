import '../config/app_config.dart';

/// One song in the user's personal library ("الأغاني اللي عندي").
///
/// The backend stores a site-relative path (`/uploads/music/x.mp3`) so the rows
/// keep working when the server moves; [playbackUrl] turns it into something
/// the audio player can open.
class MusicTrack {
  final int id;
  final String title;
  final String url;
  final int sizeBytes;

  const MusicTrack({
    required this.id,
    required this.title,
    required this.url,
    this.sizeBytes = 0,
  });

  factory MusicTrack.fromJson(Map<String, dynamic> json) {
    return MusicTrack(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] ?? 'أغنية').toString(),
      url: (json['url'] ?? '').toString(),
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
      };

  String get playbackUrl => absoluteMusicUrl(url);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is MusicTrack && other.id == id && other.url == url);

  @override
  int get hashCode => Object.hash(id, url);
}

/// Server-relative → absolute, same rule the gift assets use.
String absoluteMusicUrl(String url) {
  if (url.isEmpty) return url;
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  final base = AppConfig.socketUrl.replaceFirst(RegExp(r'/+$'), '');
  return url.startsWith('/') ? '$base$url' : '$base/$url';
}
