import 'package:flutter/material.dart';

import '../../models/product_layout.dart';
import '../../utils/image_intrinsic_size.dart';

/// C6 — the chat-bubble artwork, wrapped around whatever it is given.
///
/// This is the room's bubble rendering, lifted out so the PRIVATE MESSAGES can
/// use the same thing. The client's report was that a bought bubble showed
/// inside a room and vanished in the DMs; the reason was simply that only the
/// room had this code. Copying it would have left two implementations to keep
/// in step, and the frames and entry bars in this project already show where
/// that ends up.
///
/// Three properties matter and all three are the client's own words:
///
///  * the writing stays INSIDE the artwork's empty middle — [layout] carries
///    the inner box the dashboard configured, and the padding is never allowed
///    to be tighter than [defaultPadding] so a mis-set 0.01 inset cannot shove
///    the text against the edge;
///  * the bubble grows with the message "بالطول والعرض" — nothing here sets a
///    height, the container wraps its child;
///  * only the slice centre stretches, so a decorated border does not smear as
///    the message gets longer.
///
/// `centerSlice` is expressed in the SOURCE image's pixels, so the artwork's
/// real size has to be resolved before it can be sliced. That is asynchronous;
/// until it lands the bubble renders with a plain stretch, which is exactly how
/// it looked before any of this existed.
class BubbleSkin extends StatefulWidget {
  const BubbleSkin({
    super.key,
    required this.child,
    required this.bubbleUrl,
    this.layout = ProductLayout.empty,
    this.fallbackAsset,
    this.fallbackSlice,
    this.defaultPadding = const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    this.maxWidthFactor = 0.85,
    this.plainDecoration,
  });

  final Widget child;

  /// The equipped design, or null/empty for none.
  final String? bubbleUrl;

  /// Dashboard-configured inner box and 9-slice guides for [bubbleUrl].
  final ProductLayout layout;

  /// Bundled artwork used when the user has no design equipped. When null,
  /// [plainDecoration] is used instead — the private messages have no bundled
  /// bubble and fall back to their own flat style.
  final String? fallbackAsset;
  final Rect? fallbackSlice;

  /// Decoration for "no design and no bundled artwork".
  final BoxDecoration? plainDecoration;

  final EdgeInsets defaultPadding;
  final double maxWidthFactor;

  @override
  State<BubbleSkin> createState() => _BubbleSkinState();
}

class _BubbleSkinState extends State<BubbleSkin> {
  /// Source-pixel size of the custom artwork, or null while it resolves.
  /// Exactly one resolve per URL; the result is cached across every bubble.
  Size? _intrinsic(String url) {
    final known = ImageIntrinsicSize.peek(url);
    if (known != null) return known;
    ImageIntrinsicSize.resolve(url).then((size) {
      if (size != null && mounted) setState(() {});
    });
    return null;
  }

  double _maxWidth(BuildContext context) =>
      MediaQuery.of(context).size.width * widget.maxWidthFactor;

  /// Reference box the fractional inner insets resolve against.
  ///
  /// A bubble's real size depends on its padding, which depends on its size —
  /// so this measures against the WIDEST a bubble may get. That errs towards a
  /// slightly roomier inner box on short messages, which is the safe direction:
  /// the text can only land further inside the artwork, never over its edge.
  Size _reference(BuildContext context) {
    final w = _maxWidth(context);
    return Size(w, w * 0.3);
  }

  BoxDecoration _decoration() {
    final url = (widget.bubbleUrl ?? '').trim();
    if (url.isNotEmpty) {
      final intrinsic = _intrinsic(url);
      return BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        image: DecorationImage(
          image: NetworkImage(url),
          // No slice yet (or none configured) → plain stretch, i.e. the
          // previous behaviour, so an un-migrated product still renders.
          centerSlice: intrinsic == null ? null : widget.layout.centerSlice(intrinsic),
          fit: BoxFit.fill,
          onError: (_, __) {},
        ),
      );
    }

    if (widget.fallbackAsset != null) {
      return BoxDecoration(
        image: DecorationImage(
          image: AssetImage(widget.fallbackAsset!),
          centerSlice: widget.fallbackSlice,
          fit: BoxFit.fill,
        ),
      );
    }

    return widget.plainDecoration ?? const BoxDecoration();
  }

  EdgeInsets _padding(BuildContext context) {
    if ((widget.bubbleUrl ?? '').trim().isEmpty) return widget.defaultPadding;
    final p = widget.layout.padding(_reference(context), widget.defaultPadding);
    final d = widget.defaultPadding;
    // Never tighter than the default, for the reason in the class doc.
    return EdgeInsets.only(
      left: p.left < d.left ? d.left : p.left,
      top: p.top < d.top ? d.top : p.top,
      right: p.right < d.right ? d.right : p.right,
      bottom: p.bottom < d.bottom ? d.bottom : p.bottom,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: _maxWidth(context)),
      padding: _padding(context),
      decoration: _decoration(),
      child: widget.child,
    );
  }
}
