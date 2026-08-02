import 'package:dio/dio.dart';
import 'package:samafox/config/app_config.dart';
import 'dio_client.dart';

/// One configured tier from the admin dashboard — LV (`/levels`) or VIP
/// (`/vip/levels`). Both endpoints return the same shape.
class LevelTier {
  const LevelTier({required this.level, this.name, this.badgeUrl});

  final int level;
  final String? name;
  final String? badgeUrl;

  static LevelTier? fromJson(Map<String, dynamic> json) {
    final level = json['level'] is int
        ? json['level'] as int
        : int.tryParse(json['level']?.toString() ?? '');
    if (level == null) return null;
    final name = json['name']?.toString();
    final badgeUrl = json['badgeUrl']?.toString();
    return LevelTier(
      level: level,
      name: (name == null || name.isEmpty) ? null : name,
      badgeUrl: (badgeUrl == null || badgeUrl.isEmpty) ? null : badgeUrl,
    );
  }
}

/// LV + VIP tier catalogs as configured in لوحة التحكم, so both badges render
/// from the same source the dashboard controls instead of hardcoded chips.
///
/// Cached process-wide after the first load: the catalogs change only when an
/// admin edits them, and the badges are drawn on every seat and every profile.
/// A failed or unconfigured lookup returns null and callers fall back to their
/// built-in look — the dashboard is authoritative when set, never a hard
/// dependency for rendering.
class LevelCatalogService {
  LevelCatalogService._();

  static Dio get _dio => DioClient.dio;

  static Map<int, LevelTier>? _levels;
  static Map<int, LevelTier>? _vipLevels;
  static Future<void>? _inFlight;

  /// Load both catalogs once. Safe to call repeatedly and concurrently.
  static Future<void> ensureLoaded() {
    if (_levels != null && _vipLevels != null) return Future.value();
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  static Future<void> _load() async {
    final results = await Future.wait([
      _fetch('/levels'),
      _fetch('/vip/levels'),
    ]);
    _levels = results[0];
    _vipLevels = results[1];
  }

  static Future<Map<int, LevelTier>> _fetch(String path) async {
    try {
      final res = await _dio.get(path);
      final list = (res.data is Map) ? (res.data['data'] as List? ?? const []) : const [];
      final tiers = <int, LevelTier>{};
      for (final entry in list) {
        if (entry is! Map) continue;
        final tier = LevelTier.fromJson(Map<String, dynamic>.from(entry));
        if (tier != null) tiers[tier.level] = tier;
      }
      return tiers;
    } catch (_) {
      // Older backend or a network blip — an empty catalog just means every
      // badge keeps its built-in appearance.
      return <int, LevelTier>{};
    }
  }

  /// Admin config for an LV tier, or null when unconfigured / not yet loaded.
  static LevelTier? level(int level) => _levels?[level];

  /// Admin config for a VIP tier, or null when unconfigured / not yet loaded.
  static LevelTier? vipLevel(int level) => _vipLevels?[level];

  /// Dashboard uploads are stored site-relative (`/uploads/badge.png`), and
  /// badge images are served from the server ROOT, not the /api/v1 base.
  static String? absoluteBadgeUrl(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final base = AppConfig.socketUrl.replaceFirst(RegExp(r'/+$'), '');
    return raw.startsWith('/') ? '$base$raw' : '$base/$raw';
  }

  /// Drop the cache so the next [ensureLoaded] refetches — used after an admin
  /// edits the tiers from the in-app dashboard.
  static void invalidate() {
    _levels = null;
    _vipLevels = null;
  }
}
