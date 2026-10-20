import 'package:flutter/material.dart';

/// SPEC52 #7 — a user's name drawn in the colour of his active VIP tier.
///
/// The colour comes from the SERVER (`nameColor`, optional `nameGradient`)
/// with every user it sends; this widget never decides a colour from the VIP
/// number itself. Null/invalid colour = the surrounding [style]'s colour.
class UserNameText extends StatelessWidget {
  const UserNameText(
    this.name, {
    super.key,
    this.nameColor,
    this.nameGradient,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign,
  });

  final String name;
  final String? nameColor;
  final List<String>? nameGradient;
  final TextStyle? style;
  final int maxLines;
  final TextOverflow overflow;
  final TextAlign? textAlign;

  /// "#RRGGBB" / "#AARRGGBB" → Color; null when absent or malformed.
  static Color? parse(String? hex) {
    if (hex == null) return null;
    var h = hex.trim();
    if (h.startsWith('#')) h = h.substring(1);
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(v);
  }

  /// The style with the VIP colour applied (for places that build their own Text/RichText).
  static TextStyle styleFor(TextStyle? base, String? nameColor) {
    final c = parse(nameColor);
    return c == null ? (base ?? const TextStyle()) : (base ?? const TextStyle()).copyWith(color: c);
  }

  @override
  Widget build(BuildContext context) {
    final colors = (nameGradient ?? const <String>[]).map(parse).whereType<Color>().toList();
    if (colors.length >= 2) {
      return ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => LinearGradient(colors: colors).createShader(r),
        child: Text(
          name,
          maxLines: maxLines,
          overflow: overflow,
          textAlign: textAlign,
          style: (style ?? const TextStyle()).copyWith(color: Colors.white),
        ),
      );
    }
    return Text(
      name,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      style: styleFor(style, nameColor),
    );
  }
}
