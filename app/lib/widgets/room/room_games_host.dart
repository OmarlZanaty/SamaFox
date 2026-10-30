import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../screens/games_hub_screen.dart';
import '../../l10n/tr.dart';

/// Floating room games card with its own navigator.
class RoomGamesHost extends StatefulWidget {
  const RoomGamesHost({super.key, this.initial});

  /// A game to open directly instead of the hub (dev previews).
  final Widget? initial;

  static Future<void> show(BuildContext context, {Widget? initial}) => showDialog<void>(
        context: context,
        useSafeArea: false,
        barrierDismissible: true,
        // The mics stay visible above the card.
        barrierColor: Colors.black26,
        builder: (context) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).pop(),
          child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 64),
            child: GestureDetector(
              onTap: () {},
              child: RoomGamesHost(initial: initial),
            ),
          ),
        ),
        ),
      );

  @override
  State<RoomGamesHost> createState() => _RoomGamesHostState();
}

class _RoomGamesHostState extends State<RoomGamesHost> {
  final _nav = GlobalKey<NavigatorState>();
  bool _inGame = false;

  void _back() {
    final nav = _nav.currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screen = mq.size;
    final width = math.max(0.0, screen.width - 12);
    final sheetH = (width * 1.12).clamp(0.0, screen.height * .64);
    const headerH = 36.0;

    return PopScope(
      canPop: !_inGame,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Material(
        color: Colors.transparent,
        child: Container(
        width: width,
        height: sheetH,
        decoration: const BoxDecoration(
          color: Color(0xFF07030F),
          borderRadius: BorderRadius.all(Radius.circular(22)),
          boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 20)],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            SizedBox(
              height: headerH,
              child: Row(
                children: [
                  IconButton(
                    tooltip: tr('رجوع', 'Back'),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                    onPressed: _back,
                  ),
                  Expanded(
                    child: Text(tr('الألعاب', 'Games'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                  IconButton(
                    tooltip: tr('إغلاق والرجوع للغرفة', 'Close and return to the room'),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Navigator(
                key: _nav,
                observers: [_InGameObserver((v) {
                  if (mounted && v != _inGame) setState(() => _inGame = v);
                })],
                onGenerateRoute: (_) => MaterialPageRoute(
                  builder: (_) => widget.initial != null
                      ? _ScaledCanvas(child: widget.initial!)
                      : const _ScaledCanvas(
                          // The hub is a list: it fits the sheet as it is.
                          scale: false,
                          child: GamesHubScreen(embedded: true),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// Lays a game out at [canvas] size and scales it into the available box.
class _ScaledCanvas extends StatelessWidget {
  const _ScaledCanvas({required this.child, this.scale = true});
  final Widget child;
  final bool scale;

  @override
  Widget build(BuildContext context) {
    if (!scale) return child;
    final mq = MediaQuery.of(context);
    return LayoutBuilder(builder: (context, box) {
      if (box.maxHeight <= 0 || box.maxWidth <= 0) return const SizedBox.shrink();
      final designH = math.max(box.maxHeight, 640.0);
      final k = box.maxHeight / designH;
      final canvas = Size(box.maxWidth / k, designH);
      return FittedBox(
        fit: BoxFit.fill,
        child: SizedBox(
          width: canvas.width,
          height: canvas.height,
          child: MediaQuery(
            data: mq.copyWith(size: canvas, padding: EdgeInsets.zero, viewPadding: EdgeInsets.zero),
            child: child,
          ),
        ),
      );
    });
  }
}

/// Wraps any page a game pushes inside the sheet so it is scaled too.
Route<T> roomGameRoute<T>(Widget page) => MaterialPageRoute<T>(builder: (_) => _ScaledCanvas(child: page));

class _InGameObserver extends NavigatorObserver {
  _InGameObserver(this.onChange);
  final void Function(bool inGame) onChange;

  void _update() {
    final nav = navigator;
    if (nav == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(nav.canPop()));
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _update();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _update();
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _update();
}
