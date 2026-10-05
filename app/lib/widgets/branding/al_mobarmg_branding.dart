import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

/// Which presentation of the developer signature to draw.
///
/// * [compact] — a small two-line signature for the bottom of the splash and
///   login screens: a caption ("Developed by" / "Powered by") over the mark
///   and the wordmark.
/// * [full] — a quiet card for the About screen: mark, wordmark,
///   "Software Company" and almobarmg.com.
enum AlMobarmgVariant { compact, full }

/// The caption above a [AlMobarmgVariant.compact] signature.
enum AlMobarmgCaption { developedBy, poweredBy }

/// AL MOBARMG's developer signature — the ONE widget every branded screen uses.
///
/// Allowed only on the splash, the login screen and the About screen, once per
/// screen. It is a signature, not an advert: it never animates, it stays
/// smaller and quieter than SamaFox's own logo and name, and the whole block
/// is a single tap target that opens the company site in the EXTERNAL browser.
///
/// Colours follow [brightness] when given (the splash and login screens are
/// always dark, whatever the theme says), otherwise the ambient theme.
class AlMobarmgBranding extends StatelessWidget {
  const AlMobarmgBranding({
    super.key,
    this.variant = AlMobarmgVariant.compact,
    this.caption = AlMobarmgCaption.developedBy,
    this.brightness,
  });

  final AlMobarmgVariant variant;
  final AlMobarmgCaption caption;
  final Brightness? brightness;

  static final Uri website = Uri.parse('https://www.almobarmg.com');
  static const String websiteLabel = 'almobarmg.com';
  static const String _markAsset = 'assets/branding/al_mobarmg_mark.svg';

  // Brand colours, taken from the logo itself.
  static const Color _brandBlue = Color(0xFF26A9E0);
  static const Color _brandNavy = Color(0xFF2A3A92);
  static const Color _dotNavy = Color(0xFF252460);

  /// Opens the company site outside the app. A phone with no browser, or a
  /// refused launch, must not interrupt the user: it simply does nothing.
  static Future<void> openWebsite() async {
    try {
      await launchUrl(website, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[AlMobarmgBranding] could not open $website: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark =
        (brightness ?? Theme.of(context).brightness) == Brightness.dark;
    final isArabic = Localizations.maybeLocaleOf(context)?.languageCode == 'ar';
    final content = variant == AlMobarmgVariant.full
        ? _full(context, dark)
        : _compact(context, dark, isArabic);

    return Semantics(
      button: true,
      link: true,
      label: 'Visit AL MOBARMG Software Company website',
      excludeSemantics: true,
      child: content,
    );
  }

  // ── pieces ────────────────────────────────────────────────────────────────

  Widget _mark(double size, bool dark) {
    return SvgPicture.asset(
      _markAsset,
      height: size,
      // The three dots are navy in the logo; on a dark surface they would
      // vanish, so they go light there.
      theme: SvgTheme(currentColor: dark ? const Color(0xFFE8F6FD) : _dotNavy),
      excludeFromSemantics: true,
    );
  }

  /// "AL MOBARMG", two-tone as in the logo. Latin and left-to-right in every
  /// locale — an Arabic layout must not reorder it.
  Widget _wordmark(double fontSize, bool dark) {
    // The name is never cut: in a narrow space or with large text it shrinks.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'AL ',
              style: TextStyle(color: dark ? Colors.white : _brandNavy),
            ),
            const TextSpan(
                text: 'MOBARMG', style: TextStyle(color: _brandBlue)),
          ],
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        style: TextStyle(
          fontFamily: 'Roboto',
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: fontSize * 0.08,
          height: 1.15,
        ),
      ),
    );
  }

  /// A Latin line of the card: one line, left-to-right, shrunk rather than
  /// wrapped when large text leaves no room.
  Widget _oneLine(String text, TextStyle style) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Text(text,
          textDirection: TextDirection.ltr, maxLines: 1, style: style),
    );
  }

  Widget _tappable({
    required Widget child,
    required BorderRadius radius,
    required bool dark,
    Color? color,
    BoxBorder? border,
  }) {
    final overlay = (dark ? Colors.white : _brandBlue).withValues(alpha: 0.08);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration:
            BoxDecoration(color: color, borderRadius: radius, border: border),
        child: InkWell(
          onTap: openWebsite,
          borderRadius: radius,
          mouseCursor: SystemMouseCursors.click,
          hoverColor: overlay,
          focusColor: overlay,
          highlightColor: overlay,
          splashColor: overlay,
          child: child,
        ),
      ),
    );
  }

  // ── variants ──────────────────────────────────────────────────────────────

  Widget _compact(BuildContext context, bool dark, bool isArabic) {
    final captionText = switch (caption) {
      AlMobarmgCaption.developedBy => isArabic ? 'تطوير' : 'Developed by',
      AlMobarmgCaption.poweredBy => isArabic ? 'مدعوم من' : 'Powered by',
    };
    final muted =
        dark ? Colors.white.withValues(alpha: 0.55) : const Color(0xFF6B7280);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: _tappable(
        dark: dark,
        radius: BorderRadius.circular(14),
        child: ConstrainedBox(
          // 48 dp: the minimum comfortable tap target.
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  captionText,
                  style: TextStyle(fontSize: 11, color: muted, height: 1.2),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  textDirection: TextDirection.ltr,
                  children: [
                    _mark(20, dark),
                    const SizedBox(width: 7),
                    Flexible(child: _wordmark(13, dark)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _full(BuildContext context, bool dark) {
    final secondary =
        dark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF6B7280);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: _tappable(
        dark: dark,
        radius: BorderRadius.circular(16),
        color: dark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFE5E7EB),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              _mark(42, dark),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _wordmark(16, dark),
                    const SizedBox(height: 3),
                    _oneLine('Software Company',
                        TextStyle(fontSize: 12.5, color: secondary)),
                    const SizedBox(height: 2),
                    _oneLine(websiteLabel,
                        const TextStyle(fontSize: 12.5, color: _brandBlue)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Says "this leaves the app" without leaning on colour alone.
              Icon(Icons.open_in_new_rounded, size: 18, color: secondary),
            ],
          ),
        ),
      ),
    );
  }
}
