import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../screens/games_hub_screen.dart';
import '../../screens/games/room_native_game.dart';
import '../../l10n/tr.dart';

/// Floating room games card with its own navigator.
class RoomGamesHost extends StatefulWidget {
  const RoomGamesHost({super.key, this.initial, this.availableHeight});

  /// A game to open directly instead of the hub (dev previews).
  final Widget? initial;
  final double? availableHeight;

  static Future<void> show(BuildContext context, {Widget? initial, double? availableHeight}) => showDialog<void>(
        context: context,
        useSafeArea: false,
        barrierDismissible: true,
        // Keep the room visible behind the card.
        barrierColor: Colors.black26,
        builder: (context) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).pop(),
          child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 76),
            child: GestureDetector(
              onTap: () {},
              child: RoomGamesHost(initial: initial, availableHeight: availableHeight),
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

  /// The open game lays itself out for this card: no header bar over it.
  bool _native = false;

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
    // The caller's height is the space below the mics, not a hard limit:
    // games may cover that area to use about 85% of the screen.
    final availableH = math.max(0.0,
        screen.height - mq.padding.top - mq.padding.bottom - 76);
    final sheetH = math.min(availableH,
        math.max(screen.height * .85, widget.availableHeight ?? 0.0));
    final headerH = _native ? 0.0 : 36.0;

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
            if (headerH > 0) SizedBox(
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
                observers: [_InGameObserver((v, native) {
                  if (mounted && (v != _inGame || native != _native)) {
                    setState(() {
                      _inGame = v;
                      _native = native;
                    });
                  }
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

/// Lays a game out on a compact canvas and uniformly fits it to the card.
class _ScaledCanvas extends StatelessWidget {
  const _ScaledCanvas({required this.child, this.scale = true});
  final Widget child;
  final bool scale;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (!scale) return child;
    if (child is RoomNativeGame) {
      return MediaQuery(
        data: mq.copyWith(padding: EdgeInsets.zero, viewPadding: EdgeInsets.zero),
        child: child,
      );
    }
    return LayoutBuilder(builder: (context, box) {
      if (box.maxHeight <= 0 || box.maxWidth <= 0) return const SizedBox.shrink();
      // Cap the design size instead of imposing a minimum that shrinks games.
      final design = Size(math.min(box.maxWidth, 360.0),
          math.min(box.maxHeight, 480.0));
      final k = math.min(box.maxWidth / design.width,
          box.maxHeight / design.height);
      // Extend the non-limiting axis so the canvas fills the whole card.
      final canvas = Size(box.maxWidth / k, box.maxHeight / k);
      return FittedBox(
        fit: BoxFit.contain,
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
Route<T> roomGameRoute<T>(Widget page) => MaterialPageRoute<T>(
      settings: RouteSettings(name: page is RoomNativeGame ? _nativeRoute : null),
      builder: (_) => _ScaledCanvas(child: page),
    );

const _nativeRoute = 'room-native-game';

class _InGameObserver extends NavigatorObserver {
  _InGameObserver(this.onChange);
  final void Function(bool inGame, bool native) onChange;

  void _update(Route<dynamic>? top) {
    final nav = navigator;
    if (nav == null) return;
    final native = top?.settings.name == _nativeRoute;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(nav.canPop(), native));
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _update(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _update(previousRoute);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _update(previousRoute);
}
