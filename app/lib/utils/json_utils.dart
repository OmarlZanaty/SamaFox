int asInt(dynamic v, {int fallback = 0}) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? fallback;
}

String asString(dynamic v, {String fallback = ''}) {
  if (v == null) return fallback;
  return v.toString();
}

bool asBool(dynamic v, {bool fallback = false}) {
  if (v == null) return fallback;
  if (v is bool) return v;
  final s = v.toString().toLowerCase().trim();
  if (s == 'true' || s == '1') return true;
  if (s == 'false' || s == '0') return false;
  return fallback;
}

DateTime? asDate(dynamic v) {
  if (v == null) return null;
  try {
    return DateTime.parse(v.toString());
  } catch (_) {
    return null;
  }
}
