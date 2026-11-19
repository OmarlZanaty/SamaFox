/// One on-screen height for every badge (profile row, room profile card, chat
/// line, level/VIP art). Set from `GET /settings` -> `badgeSize` so the client
/// can resize badges from the dashboard without an app release.
class BadgeSize {
  BadgeSize._();

  static const double min = 16;
  static const double max = 48;

  /// Pixels. 26 until the server says otherwise.
  static double value = 26;

  /// Reads the `badgeSize` field of a /settings payload; ignores anything that
  /// is not a number, and clamps the rest to [min]..[max].
  static void apply(dynamic raw) {
    final n = raw is num ? raw.toDouble() : double.tryParse('${raw ?? ''}');
    if (n == null || !n.isFinite) return;
    value = n.clamp(min, max).toDouble();
  }
}
