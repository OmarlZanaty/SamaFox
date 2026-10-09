import 'package:flutter/material.dart';
import 'car_wheel_art.dart';
import 'car_wheel_engine.dart';
import 'car_wheel_strings.dart';

/// A raised glass panel: lit from the top, shaded at the bottom, gold-edged.
BoxDecoration cwPanel({double radius = 14, bool lit = false, Color? edge}) =>
    BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: lit
            ? const [Color(0xFF8E2A4E), Color(0xFF5A1033), Color(0xFF3A0821)]
            : const [Color(0xCC4B1F7A), Color(0xCC2A0F4A), Color(0xDD1A0830)],
      ),
      border: Border.all(
          color: edge ?? cwGold.withValues(alpha: lit ? .9 : .35),
          width: lit ? 1.6 : 1,),
    );

/// Round glossy icon button used across the HUD.
class CarWheelRoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Widget? child;
  const CarWheelRoundButton(
      {super.key,
      required this.icon,
      required this.tooltip,
      required this.onTap,
      this.child,});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: tooltip,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF8B54D6), Color(0xFF4A1C86)],),
                border: Border.fromBorderSide(
                    BorderSide(color: Color(0x88FFE7A2), width: 1.2),),
              ),
              child: Center(
                  child: child ?? Icon(icon, color: Colors.white, size: 22),),
            ),
          ),
        ),
      );
}

/// Balance capsule with a coin.
class CarWheelBalance extends StatelessWidget {
  final int balance;
  const CarWheelBalance({super.key, required this.balance});
  @override
  Widget build(BuildContext context) => Container(
        height: 30,
        padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 10, 0),
        decoration: cwPanel(radius: 15),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                  colors: [cwGoldLight, cwGold, Color(0xFFA8681B)],),
            ),
            child: const Center(
                child: Text('S',
                    style: TextStyle(
                        color: Color(0xFF7A4A10),
                        fontSize: 12,
                        fontWeight: FontWeight.w900,),),),
          ),
          const SizedBox(width: 6),
          Text(cwNumber(balance),
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                  color: cwGoldLight,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  fontFeatures: [FontFeature.tabularFigures()],),),
        ],),
      );
}

/// Top bettors on the left, last results on the right.
class CarWheelCrowdRow extends StatelessWidget {
  final List<Map<String, dynamic>> players;
  final int playerCount;
  final List<String> history;
  final CarWheelStrings strings;
  final VoidCallback onPlayers, onHistory;
  const CarWheelCrowdRow(
      {super.key,
      required this.players,
      required this.playerCount,
      required this.history,
      required this.strings,
      required this.onPlayers,
      required this.onHistory,});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 46,
        child: Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: onPlayers,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: cwPanel(radius: 23),
                child: players.isEmpty
                    ? Center(
                        child: Text(strings.text('emptyPlayers'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(color: cwMuted, fontSize: 11),),)
                    : Row(children: [
                        for (final (i, p) in players.take(4).indexed)
                          Expanded(child: _Bettor(p: p, first: i == 0)),
                        if (playerCount > 4)
                          Text('+${playerCount - 4}',
                              style: const TextStyle(
                                  color: cwGold,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,),),
                      ],),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onHistory,
            child: Semantics(
              label: strings.text('lastResults'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: cwPanel(radius: 23),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (final (i, k) in history.reversed.take(4).indexed)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Opacity(
                        opacity: i == 0 ? 1 : .75,
                        child:
                            CarWheelEmblem(segment: k, size: i == 0 ? 30 : 24),
                      ),
                    ),
                  if (history.isEmpty)
                    const Icon(Icons.history_rounded, color: cwMuted, size: 20),
                ],),
              ),
            ),
          ),
        ],),
      );
}

class _Bettor extends StatelessWidget {
  final Map<String, dynamic> p;
  final bool first;
  const _Bettor({required this.p, required this.first});
  @override
  Widget build(BuildContext context) {
    final name = p['name']?.toString() ?? '';
    final url = p['avatarUrl']?.toString() ?? '';
    final initial = Container(
      decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [cwPink, cwPurple]),),
      child: Center(
          child: Text(name.characters.firstOrNull ?? '?',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w900,),),),
    );
    return Row(children: [
      Stack(clipBehavior: Clip.none, children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: first ? cwGold : Colors.white38, width: 1.5,),),
          child: ClipOval(
            child: url.startsWith('http')
                ? Image.network(url,
                    cacheWidth: 96,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => initial,)
                : initial,
          ),
        ),
        if (first)
          const Positioned(
              top: -9,
              left: 8,
              child: Icon(Icons.workspace_premium_rounded,
                  color: cwGold, size: 15,),),
      ],),
      const SizedBox(width: 3),
      Expanded(
        child: Text(carWheelCompact((p['staked'] as num?)?.toInt() ?? 0),
            maxLines: 1,
            overflow: TextOverflow.clip,
            textDirection: TextDirection.ltr,
            style: const TextStyle(
                color: cwGoldLight, fontSize: 11, fontWeight: FontWeight.w800,),),
      ),
    ],);
  }
}

/// Total bet · phase · my bet.
class CarWheelTotalsRow extends StatelessWidget {
  final int total, mine;
  final String phaseText;
  final bool urgent;
  final CarWheelStrings strings;
  const CarWheelTotalsRow(
      {super.key,
      required this.total,
      required this.mine,
      required this.phaseText,
      required this.urgent,
      required this.strings,});

  Widget _value(String label, int v) => Expanded(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              maxLines: 1,
              style: const TextStyle(color: cwMuted, fontSize: 10.5),),
          Text(carWheelCompact(v),
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                  color: cwGoldLight,
                  fontSize: 17,
                  height: 1.1,
                  fontWeight: FontWeight.w900,
                  fontFeatures: [FontFeature.tabularFigures()],),),
        ],),
      );

  @override
  Widget build(BuildContext context) => Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: cwPanel(radius: 14),
        child: Row(children: [
          _value(strings.text('totalBet'), total),
          Container(
            constraints: const BoxConstraints(maxWidth: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                  colors: urgent
                      ? const [Color(0xFFFF4D5E), Color(0xFFB0122E)]
                      : const [Color(0xFFF39430), Color(0xFFD83944)],),
            ),
            child: Text(phaseText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,),),
          ),
          _value(strings.text('myTotalBet'), mine),
        ],),
      );
}

/// One brand's bet card: emblem, multiplier, mine / all.
class CarWheelBetCard extends StatelessWidget {
  final CarWheelSegment segment;
  final int mine, all;
  final bool winner, loser, enabled;
  final CarWheelStrings strings;
  final VoidCallback onTap;
  const CarWheelBetCard(
      {super.key,
      required this.segment,
      required this.mine,
      required this.all,
      required this.winner,
      required this.loser,
      required this.enabled,
      required this.strings,
      required this.onTap,});

  @override
  Widget build(BuildContext context) {
    final card = AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: loser ? .45 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: cwPanel(
          radius: 12,
          lit: winner || mine > 0,
          edge: winner ? cwGoldLight : null,
        ).copyWith(boxShadow: [
          if (winner)
            BoxShadow(color: cwGold.withValues(alpha: .7), blurRadius: 14),
        ],),
        padding: const EdgeInsets.fromLTRB(3, 3, 3, 2),
        child: Column(children: [
          Expanded(
            child: Row(children: [
              Expanded(
                  flex: 5,
                  child: FittedBox(
                      child: CarWheelEmblem(segment: segment.key, size: 36),),),
              Expanded(
                flex: 6,
                child: FittedBox(
                  child: Text('x${segment.multiplier}',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                          color: winner ? cwGoldLight : Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,),),
                ),
              ),
            ],),
          ),
          SizedBox(
            height: 13,
            child: FittedBox(
              child: Text(segment.name,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,),),
            ),
          ),
          SizedBox(
            height: 13,
            child: FittedBox(
              child: Text('${carWheelCompact(mine)} / ${carWheelCompact(all)}',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                      color: mine > 0 ? cwGoldLight : cwMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],),),
            ),
          ),
        ],),
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: strings.betLabel(segment),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: ExcludeSemantics(child: _Press(enabled: enabled, child: card)),
      ),
    );
  }
}

/// Squashes on touch, springs back on release.
class _Press extends StatefulWidget {
  final Widget child;
  final bool enabled;
  const _Press({required this.child, required this.enabled});
  @override
  State<_Press> createState() => _PressState();
}

class _PressState extends State<_Press> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) {
          if (widget.enabled) setState(() => _down = true);
        },
        onPointerUp: (_) => setState(() => _down = false),
        onPointerCancel: (_) => setState(() => _down = false),
        child: AnimatedScale(
          scale: _down ? .93 : 1,
          duration: const Duration(milliseconds: 90),
          child: widget.child,
        ),
      );
}

/// Chips and Renew.
class CarWheelDock extends StatelessWidget {
  final int selected;
  final bool canRenew;
  final CarWheelStrings strings;
  final GlobalKey barKey;
  final ValueChanged<int> onPick;
  final VoidCallback onRenew;
  const CarWheelDock(
      {super.key,
      required this.selected,
      required this.canRenew,
      required this.strings,
      required this.barKey,
      required this.onPick,
      required this.onRenew,});

  @override
  Widget build(BuildContext context) => Container(
        height: 70,
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xE63B1466), Color(0xF2180726)],),
          border: Border(top: BorderSide(color: cwGold.withValues(alpha: .5))),
        ),
        child: Row(children: [
          Expanded(
            child: LayoutBuilder(
              builder: (_, box) {
                final size = (box.maxWidth / 4 - 8).clamp(30.0, 50.0);
                return Row(
                  key: barKey,
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    for (final amount in carWheelChips)
                      Semantics(
                        button: true,
                        selected: selected == amount,
                        label: cwNumber(amount),
                        child: GestureDetector(
                          onTap: () => onPick(amount),
                          child: AnimatedSlide(
                            duration: const Duration(milliseconds: 160),
                            offset: Offset(0, selected == amount ? -.14 : 0),
                            child: CarWheelChip(
                                amount: amount,
                                size: size,
                                selected: selected == amount,),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 6),
          Opacity(
            opacity: canRenew ? 1 : .5,
            child: GestureDetector(
              onTap: canRenew ? onRenew : null,
              child: Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFFFFB054),
                        Color(0xFFF26A2E),
                        Color(0xFFC72E3A),
                      ],),
                  border:
                      Border.all(color: const Color(0xFFFFE0A8), width: 1.2),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.autorenew_rounded,
                      color: Colors.white, size: 18,),
                  const SizedBox(width: 4),
                  Text(strings.text('renew'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          shadows: [
                            Shadow(color: Color(0x88000000), blurRadius: 3),
                          ],),),
                ],),
              ),
            ),
          ),
        ],),
      );
}

String cwNumber(int value) => value
    .toString()
    .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
