import 'package:flutter/widgets.dart';

/// One layout for every phone, whatever its Android font and display size.
///
/// "عايز حل دائم بحيث شكل التطبيق و ال ID و الايقونات يكون ثابت فى اى
/// موبايل" (19/10): a phone with a large "display size" (720 px wide, about
/// 320 dp) and a large font broke the room header — the name vanished, the
/// owner's "ID: 100945" was written one character per line and the icons
/// spilled out of their bars. Screens are designed for 360 dp and more.
///
/// So, app-wide:
///  - the system font size is ignored — text is always drawn at its own size;
///  - a screen narrower than [designMinWidth] lays the app out at exactly
///    [designMinWidth] and shrinks the whole picture to fit, the way a
///    picture is scaled, so nothing is ever squeezed. Wider screens are left
///    as they are.
class AppScale extends StatelessWidget {
  const AppScale({super.key, required this.child});

  final Widget child;

  static const double designMinWidth = 360;

  static EdgeInsets _div(EdgeInsets e, double s) =>
      EdgeInsets.fromLTRB(e.left / s, e.top / s, e.right / s, e.bottom / s);

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final fixed = mq.copyWith(textScaler: TextScaler.noScaling);
    final size = mq.size;
    if (size.width <= 0 || size.width >= designMinWidth) {
      return MediaQuery(data: fixed, child: child);
    }

    final s = size.width / designMinWidth;
    final layoutSize = Size(designMinWidth, size.height / s);
    final scaled = fixed.copyWith(
      size: layoutSize,
      devicePixelRatio: mq.devicePixelRatio * s,
      padding: _div(mq.padding, s),
      viewPadding: _div(mq.viewPadding, s),
      viewInsets: _div(mq.viewInsets, s),
      systemGestureInsets: _div(mq.systemGestureInsets, s),
    );
    return FittedBox(
      fit: BoxFit.fill,
      alignment: Alignment.topLeft,
      child: SizedBox.fromSize(
        size: layoutSize,
        child: MediaQuery(data: scaled, child: child),
      ),
    );
  }
}
