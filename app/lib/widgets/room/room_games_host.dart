import 'package:flutter/material.dart';

import '../../screens/games_hub_screen.dart';

/// SPEC52 #11 — games inside the room.
///
/// The hub (3 games per row) and every game open in a sheet that rises from
/// the bottom and takes about two thirds of the screen — never the whole
/// room. A nested navigator keeps the game INSIDE the sheet, and the header
/// always has ← (back to the list) and ✕ (close, back to the room). Closing
/// the sheet never leaves the room: it is only a sheet over it.
///
/// The games were drawn for a full phone screen, so the game page is laid out
/// at the phone's own size and scaled down to the sheet (FittedBox). Their
/// layout, art and touch targets stay exactly as designed, just smaller.
class RoomGamesHost extends StatefulWidget {
  const RoomGamesHost({super.key});

  /// Share of the screen height the sheet may use.
  static const double heightFactor = 0.66;

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        builder: (_) => const RoomGamesHost(),
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
    final sheetH = screen.height * RoomGamesHost.heightFactor;
    const headerH = 44.0;

    return PopScope(
      canPop: !_inGame,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Container(
        height: sheetH,
        decoration: const BoxDecoration(
          color: Color(0xFF07030F),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
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
                    tooltip: 'رجوع',
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                    onPressed: _back,
                  ),
                  const Expanded(
                    child: Text('الألعاب',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                  IconButton(
                    tooltip: 'إغلاق والرجوع للغرفة',
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
                  builder: (_) => const _ScaledCanvas(
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
    final full = MediaQueryData.fromView(View.of(context));
    final canvas = Size(full.size.width, full.size.height - full.padding.top);
    return ColoredBox(
      color: Colors.black,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: canvas.width,
          height: canvas.height,
          child: MediaQuery(
            data: mq.copyWith(size: canvas, padding: EdgeInsets.zero, viewPadding: EdgeInsets.zero),
            child: child,
          ),
        ),
      ),
    );
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
