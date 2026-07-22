/// Converts an ISO 3166-1 alpha-2 country code (e.g. "EG", "SY") into its
/// Unicode flag emoji. No image asset needed — every modern platform font
/// renders these natively, and the app already stores plain 2-letter codes
/// on User.countryCode.
///
/// Returns null for anything that isn't exactly 2 ASCII letters, so callers
/// can cleanly fall back to hiding the flag rather than showing a broken glyph.
String? countryFlagEmoji(String? countryCode) {
  final code = countryCode?.trim().toUpperCase();
  if (code == null || code.length != 2) return null;
  final a = code.codeUnitAt(0);
  final b = code.codeUnitAt(1);
  if (a < 0x41 || a > 0x5A || b < 0x41 || b > 0x5A) return null; // A-Z only

  // Regional indicator symbols start at U+1F1E6 for 'A'.
  const regionalIndicatorBase = 0x1F1E6;
  final first = String.fromCharCode(regionalIndicatorBase + (a - 0x41));
  final second = String.fromCharCode(regionalIndicatorBase + (b - 0x41));
  return first + second;
}
