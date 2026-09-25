import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../repositories/cp_repository.dart';
import '../screens/cp_list_screen.dart';
import 'app_network_image.dart';
import 'product_video_layer.dart';

/// C17 — العلاقة, the way the client asked for it.
///
/// Two placements, both from the reference video:
///   • [CpHeartPair]        — the partners' avatars in heart frames at the very
///                            top of the profile, with a CP pill between them.
///   • [CpRelationshipCard] — the couple card lower down (and, compact, in the
///                            room profile sheet): both partners in crowned
///                            rings, names, IDs, tier and how long the pair
///                            has lasted.
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

/// Blue for men, pink for women — the two halves of the couple card. Unknown
/// falls back to the side's default so a missing gender never breaks the
/// left-blue / right-pink composition the client showed.
enum CpSide { blue, pink }

CpSide cpSideFor(String? gender, {required CpSide fallback}) {
  final g = (gender ?? '').trim().toLowerCase();
  if (g == 'female' || g == 'f' || g == 'أنثى') return CpSide.pink;
  if (g == 'male' || g == 'm' || g == 'ذكر') return CpSide.blue;
  return fallback;
}

/// The commissioned set. Every one of these is original artwork made for this
/// app — the reference video's assets belong to another operator and are not
/// used anywhere here.
class CpArt {
  CpArt._();
  static const String heartFrame = 'assets/images/cp/cp_heart_frame.png';
  static const String emblem = 'assets/images/cp/cp_emblem.png';
  static const String pill = 'assets/images/cp/cp_pill.png';
  static const String tierGlow = 'assets/images/cp/cp_tier_glow.png';

  // ---- The couple card (v2 set, see CP_ARTWORK_BRIEF.md) -----------------
  // Every one of these has a painted fallback, so the card renders in full
  // before a single file lands and a bad export degrades to plain paint.
  static const String sceneBg = 'assets/images/cp/cp_scene_bg.png';
  static const String ribbon = 'assets/images/cp/cp_ribbon.png';
  static const String ringBlue = 'assets/images/cp/cp_ring_blue.png';
  static const String ringPink = 'assets/images/cp/cp_ring_pink.png';
  static const String plateBlue = 'assets/images/cp/cp_plate_blue.png';
  static const String platePink = 'assets/images/cp/cp_plate_pink.png';
  static const String idPlate = 'assets/images/cp/cp_id_plate.png';
  static const String linkHeart = 'assets/images/cp/cp_link_heart.png';
  static const String podium = 'assets/images/cp/cp_podium.png';

  /// Where the photo sits inside each ring, as fractions of the square canvas.
  /// Measured off the delivered art (the transparent window's bounding circle,
  /// plus a little so the gold overlaps the photo edge instead of leaving a
  /// gap). The two rings were drawn separately and their windows differ, so
  /// the geometry is per side.
  static double ringPhotoDiameter(CpSide side) => side == CpSide.blue ? 0.47 : 0.53;
  static Offset ringPhotoCenter(CpSide side) =>
      side == CpSide.blue ? const Offset(0.498, 0.533) : const Offset(0.496, 0.487);

  /// Where the photo sits inside [heartFrame], as a fraction of the asset.
  /// The frame's gold border occupies the outer edge; the transparent window
  /// starts here. Measured off the delivered 512x512 art.
  static const double photoInset = 0.17;
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

// ============================================================================
// The couple card — بطاقة الارتباط
// ============================================================================

const Color _gold = Color(0xFFE3B84A);
const Color _goldLight = Color(0xFFFFE082);
const Color _blueGlow = Color(0xFF3D8BFF);
const Color _pinkGlow = Color(0xFFFF3FA4);

/// One partner in a round jewelled frame: crown on top, wings at the sides,
/// blue or pink by gender. The photo goes UNDER the frame, clipped to the
/// frame's transparent window.
class CpRingAvatar extends StatelessWidget {
  const CpRingAvatar({
    super.key,
    required this.url,
    required this.side,
    required this.size,
  });

  final String? url;
  final CpSide side;
  final double size;

  @override
  Widget build(BuildContext context) {
    final resolved = _abs(url);
    final d = size * CpArt.ringPhotoDiameter(side);
    final c = CpArt.ringPhotoCenter(side);
    final glow = side == CpSide.blue ? _blueGlow : _pinkGlow;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: size * c.dx - d / 2,
            top: size * c.dy - d / 2,
            width: d,
            height: d,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: glow.withValues(alpha: 0.55), blurRadius: size * 0.08),
                ],
              ),
              child: ClipOval(
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
          ),
          Positioned.fill(
            child: Image.asset(
              side == CpSide.blue ? CpArt.ringBlue : CpArt.ringPink,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              // Painted stand-in — a gold ring with the side's glow, a crown
              // and a gem heart — so the card is complete before the art lands.
              errorBuilder: (_, __, ___) => _PaintedRing(side: side, size: size),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaintedRing extends StatelessWidget {
  const _PaintedRing({required this.side, required this.size});
  final CpSide side;
  final double size;

  @override
  Widget build(BuildContext context) {
    final d = size * CpArt.ringPhotoDiameter(side);
    final c = CpArt.ringPhotoCenter(side);
    final glow = side == CpSide.blue ? _blueGlow : _pinkGlow;
    final ring = size * 0.045;
    final top = size * (c.dy - CpArt.ringPhotoDiameter(side) / 2);
    final bottom = size * (c.dy + CpArt.ringPhotoDiameter(side) / 2);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: size * c.dx - d / 2 - ring,
          top: top - ring,
          width: d + ring * 2,
          height: d + ring * 2,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const SweepGradient(
                colors: [_goldLight, _gold, Color(0xFFB8860B), _goldLight, _gold, _goldLight],
              ),
              boxShadow: [
                BoxShadow(color: glow.withValues(alpha: 0.7), blurRadius: size * 0.06, spreadRadius: 1),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.all(ring),
              // Punches the window out so the photo below shows through.
              child: const DecoratedBox(
                decoration: BoxDecoration(shape: BoxShape.circle, color: Color(0x00000000)),
              ),
            ),
          ),
        ),
        Positioned(
          top: top - size * 0.17,
          left: 0,
          right: 0,
          child: Icon(Icons.workspace_premium_rounded, color: _goldLight, size: size * 0.18),
        ),
        Positioned(
          top: bottom - size * 0.09,
          left: 0,
          right: 0,
          child: Icon(
            Icons.favorite_rounded,
            color: side == CpSide.blue ? const Color(0xFF64B5F6) : const Color(0xFFFF80AB),
            size: size * 0.16,
            shadows: [Shadow(color: glow, blurRadius: 8)],
          ),
        ),
      ],
    );
  }
}

/// The gendered name plate under each ring: ♂ / ♀ and the name.
class _NamePlate extends StatelessWidget {
  const _NamePlate({required this.name, required this.side, required this.width});
  final String name;
  final CpSide side;
  final double width;

  @override
  Widget build(BuildContext context) {
    final h = width * 0.22;
    final blue = side == CpSide.blue;
    return SizedBox(
      width: width,
      height: h,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Image.asset(
              blue ? CpArt.plateBlue : CpArt.platePink,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: blue
                        ? const [Color(0xFF2979FF), Color(0xFF7B1FA2)]
                        : const [Color(0xFFFF4081), Color(0xFF880E4F)],
                  ),
                  borderRadius: BorderRadius.circular(h),
                  border: Border.all(color: _gold, width: 1.2),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: h * 0.55),
            child: Row(
              textDirection: TextDirection.ltr,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  blue ? '♂' : '♀',
                  style: TextStyle(
                    color: blue ? const Color(0xFF82B1FF) : const Color(0xFFFF80AB),
                    fontSize: h * 0.55,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                SizedBox(width: h * 0.25),
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: h * 0.42,
                      fontWeight: FontWeight.w800,
                      height: 1,
                      shadows: const [Shadow(color: Color(0xAA000000), blurRadius: 3)],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The dark "ID: 123456" plate under the name.
class _IdPlate extends StatelessWidget {
  const _IdPlate({required this.id, required this.width});
  final String id;
  final double width;

  @override
  Widget build(BuildContext context) {
    final h = width * 0.26;
    return SizedBox(
      width: width,
      height: h,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Image.asset(
              CpArt.idPlate,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => Container(
                decoration: BoxDecoration(
                  color: const Color(0xE61A0B2E),
                  borderRadius: BorderRadius.circular(h * 0.35),
                  border: Border.all(color: _gold, width: 1),
                ),
              ),
            ),
          ),
          Text(
            'ID: $id',
            textDirection: TextDirection.ltr,
            style: TextStyle(
              color: _goldLight,
              fontSize: h * 0.46,
              fontWeight: FontWeight.w800,
              height: 1,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// A partner column: ring, name plate, ID plate.
class _PartnerColumn extends StatelessWidget {
  const _PartnerColumn({
    required this.avatarUrl,
    required this.name,
    required this.displayId,
    required this.side,
    required this.ringSize,
  });

  final String? avatarUrl;
  final String name;
  final String displayId;
  final CpSide side;
  final double ringSize;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CpRingAvatar(url: avatarUrl, side: side, size: ringSize),
          SizedBox(height: ringSize * 0.03),
          _NamePlate(name: name, side: side, width: ringSize * 1.02),
          SizedBox(height: ringSize * 0.04),
          _IdPlate(id: displayId, width: ringSize * 0.66),
        ],
      );
}

class _Ribbon extends StatelessWidget {
  const _Ribbon({required this.width, required this.label});
  final double width;
  final String label;

  @override
  Widget build(BuildContext context) {
    final h = width / 3.7; // the delivered ribbon's aspect
    return SizedBox(
      width: width,
      height: h,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Image.asset(
              CpArt.ribbon,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => Container(
                margin: EdgeInsets.symmetric(vertical: h * 0.12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFD81B60), Color(0xFF880E4F)]),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _gold, width: 1),
                ),
              ),
            ),
          ),
          // Shrinks rather than wraps: the ribbon's flat face is the middle
          // 65% and the title must stay on it.
          Padding(
            padding: EdgeInsets.symmetric(horizontal: width * 0.17),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: h * 0.40,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  shadows: const [Shadow(color: Color(0xAA000000), blurRadius: 3)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The glowing heart that joins the two rings, with light trails to each side.
class _LinkHeart extends StatelessWidget {
  const _LinkHeart();

  @override
  Widget build(BuildContext context) => Image.asset(
        CpArt.linkHeart,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => LayoutBuilder(
          builder: (_, b) => Stack(
            alignment: Alignment.center,
            children: [
              Container(
                height: 2,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0x003D8BFF), _blueGlow, _pinkGlow, Color(0x00FF3FA4)],
                  ),
                  boxShadow: [BoxShadow(color: Color(0x88FF3FA4), blurRadius: 10)],
                ),
              ),
              Icon(
                Icons.favorite_rounded,
                color: const Color(0xFFFF4081),
                size: b.maxHeight * 0.9,
                shadows: const [Shadow(color: Color(0xFFFF4081), blurRadius: 14)],
              ),
            ],
          ),
        ),
      );
}

class _TierPill extends StatelessWidget {
  const _TierPill({
    required this.level,
    required this.levelName,
    required this.days,
    required this.height,
  });
  // From the server (the admin can tune or pin a level); see CpRelationshipCard.
  final int level;
  final String levelName;
  final int days;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        padding: EdgeInsets.symmetric(horizontal: height * 0.7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.40),
          borderRadius: BorderRadius.circular(height),
          border: Border.all(color: _gold, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$levelName  LV.$level',
              style: TextStyle(
                color: _goldLight,
                fontSize: height * 0.46,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            SizedBox(width: height * 0.5),
            Text(
              '•  $days ${days == 1 ? 'يوم' : 'أيام'}',
              style: TextStyle(
                color: Colors.white70,
                fontSize: height * 0.42,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ],
        ),
      );
}

class _PaintedPodium extends StatelessWidget {
  const _PaintedPodium({required this.width});
  final double width;

  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Container(
            width: width * 0.70,
            height: width * 0.06,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.all(Radius.elliptical(width * 0.35, width * 0.03)),
              gradient: const LinearGradient(
                colors: [Color(0xFF7B1FA2), Color(0xFFE91E63), Color(0xFF7B1FA2)],
              ),
              border: Border.all(color: _gold, width: 1),
              boxShadow: const [BoxShadow(color: Color(0x99FF3FA4), blurRadius: 18)],
            ),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: width * 0.04),
            child: Icon(
              Icons.favorite_rounded,
              color: const Color(0xFFFF4FA8),
              size: width * 0.16,
              shadows: const [Shadow(color: _pinkGlow, blurRadius: 20)],
            ),
          ),
        ],
      );
}

/// العلاقة — the couple card the client asked for: the winged CP emblem on
/// top, a ribbon reading علاقة الارتباط, the two partners in crowned rings
/// joined by a glowing heart, their names and IDs on plates beneath, and the
/// heart podium at the foot.
///
/// [compact] drops the podium and shrinks the rings for the room profile
/// sheet, which is capped at half the screen.
class CpRelationshipCard extends StatelessWidget {
  const CpRelationshipCard({
    super.key,
    required this.myAvatarUrl,
    required this.partner,
    this.myName = '',
    this.myDisplayId,
    this.myGender,
    this.compact = false,
    this.showTitle = true,
    this.onTap,
  });

  final String? myAvatarUrl;
  final String myName;
  final int? myDisplayId;
  final String? myGender;
  final CpPartner partner;
  final bool compact;
  final bool showTitle;
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

    // The owner sits on the LEFT. With no genders known the composition stays
    // left-blue / right-pink like the reference; when both are the same, both
    // sides carry that colour — that is the truth and it still reads.
    final mySide = cpSideFor(myGender, fallback: CpSide.blue);
    final theirSide = cpSideFor(
      partner.gender,
      fallback: mySide == CpSide.blue ? CpSide.pink : CpSide.blue,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 0 : 16, 4, compact ? 0 : 16, compact ? 0 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTitle)
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
            child: LayoutBuilder(
              builder: (context, box) {
                final w = box.maxWidth.isFinite
                    ? box.maxWidth
                    : MediaQuery.of(context).size.width - 32;
                final ring = w * (compact ? 0.31 : 0.36);
                final emblemH = w * (compact ? 0.20 : 0.26);
                return ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Stack(
                    children: [
                      // The night scene the whole card lives in. The tier
                      // gradient stays underneath so LV.1 and LV.5 still differ
                      // with no art at all.
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [const Color(0xFF1A0B3D), tier.b, const Color(0xFF12082B)],
                            ),
                          ),
                          child: Image.asset(
                            CpArt.sceneBg,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (_, __, ___) => Opacity(
                              opacity: 0.35 + tier.level * 0.08,
                              child: Image.asset(
                                CpArt.tierGlow,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // The gift that made the pair, playing faintly behind the
                      // scene — "طبعاً الهديه تشكل بردو". Renders nothing until
                      // the first frame and nothing at all on failure.
                      if (animation.isNotEmpty && isProductVideoUrl(animation))
                        Positioned.fill(
                          child: Opacity(
                            opacity: 0.30,
                            child: ProductVideoLayer(url: animation, fit: BoxFit.cover),
                          ),
                        ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          w * 0.04, w * 0.03, w * 0.04, compact ? w * 0.04 : 0,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // ── Emblem: the winged CP heart with the crown ──
                            SizedBox(
                              height: emblemH,
                              child: Image.asset(
                                CpArt.emblem,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.medium,
                                errorBuilder: (_, __, ___) => Icon(
                                  Icons.favorite,
                                  color: const Color(0xFFFF4081),
                                  size: emblemH * 0.8,
                                  shadows: const [Shadow(color: Color(0xFFFF4081), blurRadius: 18)],
                                ),
                              ),
                            ),
                            // ── Ribbon: علاقة الارتباط ──
                            Transform.translate(
                              offset: Offset(0, -emblemH * 0.10),
                              child: _Ribbon(width: w * 0.40, label: 'علاقة الارتباط'),
                            ),
                            SizedBox(height: w * 0.01),
                            // ── The pair, joined by the heart ──
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                // The glowing link runs behind both rings at
                                // photo height.
                                Positioned(
                                  top: ring * 0.51 - ring * 0.19,
                                  left: ring * 0.45,
                                  right: ring * 0.45,
                                  height: ring * 0.38,
                                  child: const _LinkHeart(),
                                ),
                                // Owner LEFT, partner RIGHT — the reference's
                                // composition — even though the app runs RTL.
                                Row(
                                  textDirection: TextDirection.ltr,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _PartnerColumn(
                                      avatarUrl: myAvatarUrl,
                                      name: myName.isEmpty ? 'أنا' : myName,
                                      displayId: myDisplayId?.toString() ?? '—',
                                      side: mySide,
                                      ringSize: ring,
                                    ),
                                    _PartnerColumn(
                                      avatarUrl: partner.avatarUrl,
                                      name: partner.name,
                                      displayId: partner.displayId?.toString() ?? '—',
                                      side: theirSide,
                                      ringSize: ring,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            SizedBox(height: w * 0.025),
                            // ── Tier + how long the pair has lasted ──
                            _TierPill(level: level, levelName: levelName, days: days, height: w * 0.065),
                            if (!compact) ...[
                              SizedBox(height: w * 0.01),
                              // ── The heart podium ──
                              SizedBox(
                                height: w * 0.30,
                                width: double.infinity,
                                child: Image.asset(
                                  CpArt.podium,
                                  fit: BoxFit.contain,
                                  alignment: Alignment.bottomCenter,
                                  filterQuality: FilterQuality.medium,
                                  errorBuilder: (_, __, ___) => _PaintedPodium(width: w),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Loads the owner's pairs and shows the featured one as a [CpRelationshipCard].
/// Renders nothing at all when there is no pair — an empty frame on every
/// profile in the app would be noise.
///
/// Shared by the profile page (full card) and the room profile sheet (compact).
class CpCoupleSection extends StatefulWidget {
  const CpCoupleSection({
    super.key,
    required this.userId,
    required this.isOwnProfile,
    this.ownerName = '',
    this.ownerAvatarUrl,
    this.ownerDisplayId,
    this.ownerGender,
    this.compact = false,
    this.showTitle = true,
    this.onTap,
  });

  final int userId;
  final bool isOwnProfile;
  final String ownerName;
  final String? ownerAvatarUrl;
  final int? ownerDisplayId;
  final String? ownerGender;
  final bool compact;
  final bool showTitle;

  /// Defaults to opening the CP list; pass to override.
  final VoidCallback? onTap;

  @override
  State<CpCoupleSection> createState() => _CpCoupleSectionState();
}

class _CpCoupleSectionState extends State<CpCoupleSection> {
  late Future<List<CpPartner>> _future;

  // On your own profile the featured partner is chosen on the server, so the
  // synced read also brings the local choice up to date.
  Future<List<CpPartner>> _load() => widget.isOwnProfile
      ? CpRepository().myPartnersSynced(userId: widget.userId)
      : CpRepository().partners(userId: widget.userId);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant CpCoupleSection old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId) {
      _future = _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<CpPartner>>(
        future: _future,
        builder: (context, snap) {
          final partners = snap.data ?? const <CpPartner>[];
          if (partners.isEmpty) return const SizedBox.shrink();
          return FutureBuilder<int?>(
            future: CpFeatured.get(),
            builder: (context, chosen) {
              final p = CpFeatured.pick(partners, chosen.data) ?? partners.first;
              return CpRelationshipCard(
                myAvatarUrl: widget.ownerAvatarUrl,
                myName: widget.ownerName,
                myDisplayId: widget.ownerDisplayId,
                myGender: widget.ownerGender,
                partner: p,
                compact: widget.compact,
                showTitle: widget.showTitle,
                onTap: widget.onTap ??
                    () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CpListScreen(
                            userId: widget.isOwnProfile ? null : widget.userId,
                          ),
                        ),
                      );
                      // A new featured partner picked in the list lives on the
                      // server; re-read so the card shows it.
                      if (mounted) setState(() => _future = _load());
                    },
              );
            },
          );
        },
      );
}
