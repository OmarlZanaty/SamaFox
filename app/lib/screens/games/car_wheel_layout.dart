part of 'car_wheel_screen.dart';

extension _CarWheelLayout on CarWheelScreenState {
  /// Fixed heights for everything but the wheel; the wheel takes what is left,
  /// so the whole game fits one screen without scrolling.
  Widget _game(int balance) => LayoutBuilder(
        builder: (context, box) {
          final width = min(box.maxWidth, 520.0);
          final inner = width - 20;
          final cardW = (inner - 3 * 6) / 4;
          final phase = state?.phase ?? 'betting';
          final result = state?.result;
          const hud = 48.0,
              crowd = 40.0,
              history = 28.0,
              dock = 70.0,
              gaps = 18.0;
          final totals = phase == 'result' ? 66.0 : 44.0;
          final room =
              box.maxHeight - hud - crowd - history - totals - dock - gaps - 6;
          final minCard = (cardW * .78).clamp(58.0, 76.0);
          final wheel =
              min(width * .94, room - minCard * 2).clamp(200.0, 520.0);
          // A tall phone's spare height goes to bigger cards, not a gap.
          final cardH = ((room - wheel) / 2).clamp(minCard, 96.0);
          return Center(
            child: SizedBox(
              width: width,
              child: Stack(
                key: _stageKey,
                clipBehavior: Clip.none,
                children: [
                  Column(
                    children: [
                      SizedBox(height: hud, child: _hud(balance)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: CarWheelCrowdRow(
                          players: state?.players ?? const [],
                          playerCount: state?.playerCount ?? 0,
                          strings: _s,
                          onPlayers: _openPlayers,
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: CarWheelWheel(
                            size: wheel,
                            angle: _angle,
                            ambient: _ambient,
                            secondsLeft: _secondsLeft,
                            phase: _landed == null && phase == 'result'
                                ? 'spinning'
                                : phase,
                            result:
                                _landed ?? (phase == 'result' ? result : null),
                            myStakes: myStakes,
                            reduced: _reduced,
                            diskKey: _diskKey,
                            onBet: _betting
                                ? (k) => placeChip(k, fromWheel: true)
                                : null,
                          ),
                        ),
                      ),
                      CarWheelHistoryStrip(
                        history: state?.history ?? const [],
                        strings: _s,
                        onTap: _openHistory,
                      ),
                      SizedBox(
                        height: totals,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: phase == 'result' && result != null
                              ? _resultPlaque(result)
                              : CarWheelTotalsRow(
                                  total: state?.totalBet ?? 0,
                                  mine: _myTotal,
                                  phaseText: _phaseText(phase),
                                  urgent: _urgent,
                                  strings: _s,
                                ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: SizedBox(
                          height: cardH * 2 + 6,
                          child: GridView.count(
                            physics: const NeverScrollableScrollPhysics(),
                            padding: EdgeInsets.zero,
                            crossAxisCount: 4,
                            mainAxisSpacing: 6,
                            crossAxisSpacing: 6,
                            childAspectRatio: cardW / cardH,
                            children: [
                              for (final s in carWheelSegments)
                                CarWheelBetCard(
                                  key: _cardKeys[s.key],
                                  segment: s,
                                  mine: myStakes[s.key] ?? 0,
                                  chips: _chips
                                      .where((c) => c['key'] == s.key)
                                      .toList(),
                                  all: state?.totals[s.key] ?? 0,
                                  winner: phase == 'result' && result == s.key,
                                  loser: phase == 'result' &&
                                      result != null &&
                                      result != s.key,
                                  enabled: _betting && !_timeUp,
                                  reduced: _reduced,
                                  strings: _s,
                                  onTap: () => placeChip(s.key),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      CarWheelDock(
                        selected: chip,
                        reduced: _reduced,
                        canRenew: _betting && _pending == 0,
                        strings: _s,
                        barKey: _barKey,
                        onPick: _pickChip,
                        onRenew: _renew,
                      ),
                    ],
                  ),
                  if (phase == 'result' && _payout > 0 && !_reduced)
                    Positioned(
                        left: 0,
                        right: 0,
                        top: hud + crowd + wheel * .55,
                        child: CarWheelFloatingWin(
                            key: ValueKey('float-$_round'),
                            text: '+${cwNumber(_payout)}',),),
                  if (phase == 'result' &&
                      _landed != null &&
                      _payout > 0 &&
                      !_reduced)
                    Positioned.fill(
                      child: CarWheelCoinBurst(
                        key: ValueKey('burst-$_round'),
                        big: _payout >= max(1, state?.myStaked ?? 1) * 10,
                      ),
                    ),
                  if (_notice != null)
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: dock + cardH * 2 + totals + 24,
                      child: _toast(_notice!),
                    ),
                  for (final f in _flights)
                    CarWheelFlyingChip(
                      key: f.key,
                      from: f.from,
                      to: f.to,
                      amount: f.amount,
                      onDone: () {
                        _finishFlight(f.key);
                      },
                    ),
                ],
              ),
            ),
          );
        },
      );

  String _phaseText(String phase) {
    if (phase == 'betting' && _timeUp) return _s.text('closing');
    return switch (phase) {
      'closing' => _s.text('closing'),
      'spinning' => _s.text('spinning'),
      'result' => _s.text('result'),
      _ => _s.text('betting'),
    };
  }

  Widget _hud(int balance) {
    final date = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            CarWheelRoundButton(
              icon: Icons.arrow_back_rounded,
              tooltip: _s.text('home'),
              onTap: () => Navigator.maybePop(context),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _s.round(state?.round ?? 0),
                      style: const TextStyle(
                        color: cwGoldLight,
                        fontSize: 14,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${date.year} / ${two(date.month)} / ${two(date.day)}',
                      style: const TextStyle(
                        color: cwMuted,
                        fontSize: 10,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Flexible(
              child: FittedBox(child: CarWheelBalance(balance: balance)),
            ),
            const SizedBox(width: 6),
            CarWheelRoundButton(
              icon: Icons.emoji_events_rounded,
              tooltip: _s.text('ranking'),
              onTap: _openRanking,
              child: SizedBox.square(
                dimension: 26,
                child: carWheelImage(
                  'trophy',
                  const Icon(Icons.emoji_events, color: cwGold),
                ),
              ),
            ),
            const SizedBox(width: 6),
            PopupMenuButton<String>(
              tooltip: _s.text('menu'),
              color: cwNavy,
              padding: EdgeInsets.zero,
              icon: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF8B54D6), Color(0xFF4A1C86)],
                  ),
                  border: Border.fromBorderSide(
                    BorderSide(color: Color(0x88FFE7A2), width: 1.2),
                  ),
                ),
                child: const Icon(Icons.menu_rounded, color: Colors.white),
              ),
              itemBuilder: (_) => [
                for (final key in [
                  'help',
                  'paytable',
                  'history',
                  'players',
                  'settings',
                ])
                  PopupMenuItem(
                    value: key,
                    child: Text(
                      _s.text(key),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
              ],
              onSelected: (key) {
                switch (key) {
                  case 'help':
                    _openHelp();
                  case 'paytable':
                    _openHelp(paytable: true);
                  case 'history':
                    _openHistory();
                  case 'players':
                    _openPlayers();
                  case 'settings':
                    _openSettings();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultPlaque(String result) {
    final won = _payout > 0;
    final big = won && _payout >= max(1, state?.myStaked ?? 1) * 10;
    return Center(
      child: RepaintBoundary(
        child: CarWheelPopIn(
          key: ValueKey('plaque-$_round'),
          reduced: _reduced,
          shake: big,
          child: Semantics(
            liveRegion: true,
            label:
                '${_s.winning(result)}. ${won ? '${_s.text('youWon')} ${cwNumber(_payout)}' : _s.text('noWin')}',
            child: ExcludeSemantics(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  decoration: cwPanel(radius: 18, lit: won),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CarWheelEmblem(segment: result, size: big ? 46 : 38),
                      const SizedBox(width: 10),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _s.winning(result),
                            style: const TextStyle(
                              color: cwGold,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (won)
                            TweenAnimationBuilder<double>(
                              key: ValueKey('prize-$_round-$_payout'),
                              tween: Tween(begin: 0, end: _payout.toDouble()),
                              duration: Duration(
                                milliseconds:
                                    _reduced ? 0 : (big ? 1800 : 1000),
                              ),
                              builder: (_, value, __) => Text(
                                '${_s.text('youWon')} ${cwNumber(value.round())}',
                                style: TextStyle(
                                  color: cwGoldLight,
                                  fontSize: big ? 24 : 20,
                                  fontWeight: FontWeight.w900,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            )
                          else
                            Text(
                              _s.text('noWin'),
                              style:
                                  const TextStyle(color: cwMuted, fontSize: 13),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _toast(String text) => IgnorePointer(
        child: Center(
          child: Semantics(
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xEE1A0830),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cwGold.withValues(alpha: .6)),
              ),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: cwGoldLight,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      );
}
