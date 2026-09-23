import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../repositories/cp_repository.dart';
import 'app_network_image.dart';
import 'product_video_layer.dart';

/// C17 — العلاقة, the way the client asked for it.
///
/// Two placements, both from the reference video:
///   • [CpHeartPair]        — the partners' avatars in heart frames at the very
///                            top of the profile, with a CP pill between them.
///   • [CpRelationshipCard] — the big framed card lower down: both avatars, the
///                            tier name and level, and how long the pair has
///                            lasted.
///
/// The ornament is original artwork commissioned for this app (see [CpArt] and
/// CP_ARTWORK_BRIEF.md). The reference video belongs to another operator and
/// none of its assets are used. Every painted fallback below survives a missing
/// file, so a bad export degrades to plain gold rather than a blank page.
class CpTier {
  const CpTier(this.level, this.name, this.minDays, this.a, this.b);

  final int level;
  final String name;
  final int minDays;
  final Color a;
  final Color b;

  /// The server models a pair as two users, a gift and a date — there is no
  /// relationship name or level on CpPair. The reference shows both, so they
  /// are derived from how long the pair has lasted, which is the only thing
  /// that actually grows over time. If the client later wants these named per
  /// pair, it becomes two columns and this table turns into a fallback.
  static const List<CpTier> all = [
    CpTier(1, 'بداية حب', 0, Color(0xFF7B1FA2), Color(0xFF4A148C)),
    CpTier(2, 'حب حلو', 7, Color(0xFFD81B60), Color(0xFF880E4F)),
    CpTier(3, 'حب كبير', 30, Color(0xFFE53935), Color(0xFF8E0000)),
    CpTier(4, 'حب خالد', 90, Color(0xFFFF6F00), Color(0xFFBF360C)),
    CpTier(5, 'روح واحدة', 365, Color(0xFFFFC107), Color(0xFFB8860B)),
  ];

  static CpTier forDays(int days) {
    var hit = all.first;
    for (final t in all) {
      if (days >= t.minDays) hit = t;
    }
    return hit;
  }

  /// The colours for a server-computed level. The admin can set more than
  /// five levels, so anything past the table keeps the top tier's look.
  static CpTier forLevel(int level) => all[(level.clamp(1, all.length)) - 1];
}

/// The commissioned set. Every one of these is original artwork made for this
/// app — the reference video's assets belong to another operator and are not
/// used anywhere here.
class CpArt {
  CpArt._();
  static const String heartFrame = 'assets/images/cp/cp_heart_frame.png';
  static const String emblem = 'assets/images/cp/cp_emblem.png';
  static const String cardFrame = 'assets/images/cp/cp_card_frame.png';
  static const String pill = 'assets/images/cp/cp_pill.png';
  static const String tierGlow = 'assets/images/cp/cp_tier_glow.png';

  /// Where the photo sits inside [heartFrame], as a fraction of the asset.
  /// The frame's gold border occupies the outer edge; the transparent window
  /// starts here. Measured off the delivered 512x512 art.
  static const double photoInset = 0.17;

  /// The transparent middle of [cardFrame], as fractions of its 1024x640.
  /// Content is padded to these so it never sits under the filigree.
  static const EdgeInsets cardContentInset =
      EdgeInsets.fromLTRB(0.075, 0.09, 0.075, 0.09);
}

String _abs(String? raw) {
  final v = (raw ?? '').trim();
  if (v.isEmpty) return '';
  if (v.startsWith('http://') || v.startsWith('https://')) return v;
  final base = AppConfig.socketUrl.endsWith('/')
      ? AppConfig.socketUrl.substring(0, AppConfig.socketUrl.length - 1)
      : AppConfig.socketUrl;
  return v.startsWith('/') ? '$base$v' : '$base/$v';
}

int _daysSince(DateTime? since) =>
    since == null ? 0 : DateTime.now().difference(since).inDays;

/// A heart, drawn as a path so the avatar can be clipped into it.
class _HeartClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size s) {
    final w = s.width, h = s.height;
    return Path()
      ..moveTo(w * 0.5, h * 0.95)
      ..cubicTo(w * -0.20, h * 0.58, w * 0.12, h * -0.10, w * 0.5, h * 0.26)
      ..cubicTo(w * 0.88, h * -0.10, w * 1.20, h * 0.58, w * 0.5, h * 0.95)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// One partner's avatar inside a heart with a gold rim.
class CpHeartAvatar extends StatelessWidget {
  const CpHeartAvatar({super.key, required this.url, this.size = 62});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final resolved = _abs(url);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The photo goes UNDER the frame, clipped to a heart so it does not
          // square off inside the gold. The frame's own transparent window sits
          // exactly over it.
          Padding(
            padding: EdgeInsets.all(size * CpArt.photoInset),
            child: ClipPath(
              clipper: _HeartClipper(),
              child: resolved.isEmpty
                  ? Container(color: const Color(0xFF3A1B5C))
                  : AppNetworkImage(
                      resolved,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Container(color: const Color(0xFF3A1B5C)),
                    ),
            ),
          ),
          Image.asset(
            CpArt.heartFrame,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            // A missing asset must not blank the avatar out — the photo below
            // still reads fine on its own.
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// The header pair: me ♥ partner, with a CP pill under them.
///
/// Sits at the top of the profile in the reference, over the background, which
/// is why it paints its own shadow rather than assuming a dark surface.
class CpHeartPair extends StatelessWidget {
  const CpHeartPair({
    super.key,
    required this.myAvatarUrl,
    required this.partnerAvatarUrl,
    this.size = 58,
  });

  final String? myAvatarUrl;
  final String? partnerAvatarUrl;
  final double size;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CpHeartAvatar(url: myAvatarUrl, size: size),
              SizedBox(width: size * 0.10),
              Icon(Icons.favorite, color: const Color(0xFFFF4081), size: size * 0.30),
              SizedBox(width: size * 0.10),
              CpHeartAvatar(url: partnerAvatarUrl, size: size),
            ],
          ),
          const SizedBox(height: 4),
          // The plaque, with CP printed over its flat centre panel.
          SizedBox(
            width: size * 1.15,
            height: size * 0.43,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Image.asset(
                  CpArt.pill,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, __, ___) => Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE91E63), Color(0xFF9C27B0)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFFFE082), width: 1.2),
                    ),
                  ),
                ),
                Text(
                  'CP',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: size * 0.20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    shadows: const [Shadow(color: Color(0xAA000000), blurRadius: 3)],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

/// العلاقة — the framed card.
class CpRelationshipCard extends StatelessWidget {
  const CpRelationshipCard({
    super.key,
    required this.myAvatarUrl,
    required this.partner,
    this.onTap,
  });

  final String? myAvatarUrl;
  final CpPartner partner;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Level, name and days come from the server now (the admin can tune how
    // levels grow or pin one); the days ladder is only for an older server.
    final days = partner.cpDays ?? _daysSince(partner.since);
    final tier = partner.cpLevel != null ? CpTier.forLevel(partner.cpLevel!) : CpTier.forDays(days);
    final level = partner.cpLevel ?? tier.level;
    final levelName = (partner.cpLevelName ?? '').isNotEmpty ? partner.cpLevelName! : tier.name;
    final animation = _abs(partner.giftAnimationUrl);
    final icon = _abs(partner.giftIconUrl);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'العلاقة',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
          GestureDetector(
            onTap: onTap,
            child: Container(
              // Generous padding so names and numbers clear the filigree.
              padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
              decoration: BoxDecoration(
                // The tier gradient stays as the bed the glow and frame sit on:
                // it is what makes LV.1 and LV.5 look different at a glance.
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [tier.a, tier.b],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(color: Color(0x66000000), blurRadius: 14, offset: Offset(0, 6)),
                ],
              ),
              child: Stack(
                children: [
                  // Warm light under everything, brighter as the pair ages.
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Opacity(
                        opacity: 0.30 + (tier.level * 0.09),
                        child: Image.asset(
                          CpArt.tierGlow,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                  // The gift that made the pair, playing behind the card when it
                  // is a video — "طبعاً الهديه تشكل بردو". Muted and looping;
                  // ProductVideoLayer renders nothing until the first frame is
                  // ready and nothing at all on failure, so a bad upload simply
                  // leaves the gradient.
                  if (animation.isNotEmpty && isProductVideoUrl(animation))
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Opacity(
                          opacity: 0.45,
                          child: ProductVideoLayer(url: animation, fit: BoxFit.cover),
                        ),
                      ),
                    ),
                  // The border, painted OVER the content and ignoring taps.
                  // centerSlice keeps the corner flourishes at their true size
                  // while only the plain runs between them stretch — the whole
                  // reason the brief asked for detail in the corners only.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Image.asset(
                        CpArt.cardFrame,
                        fit: BoxFit.fill,
                        centerSlice: const Rect.fromLTRB(220, 180, 804, 460),
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          CpHeartAvatar(url: myAvatarUrl, size: 74),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 74,
                                height: 56,
                                child: Image.asset(
                                  CpArt.emblem,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.medium,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.favorite,
                                    color: Color(0xFFFFE082),
                                    size: 30,
                                  ),
                                ),
                              ),
                              if (icon.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                SizedBox(
                                  width: 30,
                                  height: 30,
                                  child: AppNetworkImage(
                                    icon,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) =>
                                        const SizedBox.shrink(),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          CpHeartAvatar(url: partner.avatarUrl, size: 74),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.32),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE3B84A), width: 1),
                        ),
                        child: Text(
                          '$levelName  LV.$level',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$days ${days == 1 ? 'يوم' : 'أيام'}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        partner.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
