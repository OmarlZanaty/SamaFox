import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'yummy_engine.dart';
import 'yummy_fx.dart';
import 'yummy_strings.dart';
import 'yummy_symbols.dart';

/// Decoded symbol pictures, shared by every machine. Decoded at 256 px (the
/// art is 512) so all eleven cost ~3 MB instead of ~11 MB on small phones.
class YummyAtlas {
  YummyAtlas._();
  static final Map<String, ui.Image> images = {};
  static final ValueNotifier<int> loaded = ValueNotifier(0);
  static Future<void>? _loading;

  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() {
    final done = <Future<void>>[];
    for (final symbol in yummySymbolIds) {
      final completer = Completer<void>();
      done.add(completer.future);
      final stream = ResizeImage(
        AssetImage('$yummyArt$symbol.png'),
        width: 256,
        allowUpscaling: false,
      ).resolve(ImageConfiguration.empty);
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          images[symbol] = info.image;
          loaded.value++;
          stream.removeListener(listener);
          if (!completer.isCompleted) completer.complete();
        },
        onError: (_, __) {
          stream.removeListener(listener);
          if (!completer.isCompleted) completer.complete();
        },
      );
      stream.addListener(listener);
    }
    return Future.wait(done);
  }
}

/// A colour per symbol for juice splashes and the fallback drawing.
const yummySymbolColors = {
  'strawberry': Color(0xFFFF3B5C),
  'cherry': Color(0xFFD7193B),
  'orange': Color(0xFFFF9419),
  'lemon': Color(0xFFFFE03A),
  'watermelon': Color(0xFF3FCB4A),
  'grapes': Color(0xFF9B4DFF),
  'candy': Color(0xFFFF6FD0),
  'diamond': Color(0xFF4FD8FF),
  'wild': Color(0xFFFFD529),
  'bonus': Color(0xFFFF4B86),
  'jackpot': Color(0xFFFFC21A),
};
const _premium = {'diamond', 'wild', 'bonus', 'jackpot'};

enum _Phase { idle, spinning, settling }

class _Reel {
  _Phase phase = _Phase.idle;

  /// tape[0] sits above the window; tape[1..3] are rows 0..2.
  List<String> tape = const [];
  double y = 0, speed = 0, maxSpeed = 16, startIn = 0;
  double settleT = 0, settleFrom = 0, settleTime = .26;
  List<String> queue = [];

  /// Rows 0..2 this reel is landing on, once known.
  List<String>? target;
  Completer<void>? landed;
  bool anticipating = false;
  double landedAt = -10;
}

/// Timing for one presentation speed. Turbo roughly halves everything.
class YummyPace {
  final double minSpin, gap, anticipation, settle, pop, fall, lineDraw;
  const YummyPace({
    required this.minSpin,
    required this.gap,
    required this.anticipation,
    required this.settle,
    required this.pop,
    required this.fall,
    required this.lineDraw,
  });
  static const normal = YummyPace(
    minSpin: .55,
    gap: .17,
    anticipation: 1.1,
    settle: .28,
    pop: .32,
    fall: .42,
    lineDraw: .45,
  );
  static const turbo = YummyPace(
    minSpin: .22,
    gap: .07,
    anticipation: .55,
    settle: .18,
    pop: .2,
    fall: .26,
    lineDraw: .25,
  );
}

/// The 5×3 machine: a candy cabinet with chasing bulbs and real scrolling
/// reel strips that stop one by one (slowing down with a glow when two
/// BONUS or crowns already landed), win lines that draw in, cells that pop
/// into juice and refill from the top, WILDs that expand in free spins, and
/// particles. Driven imperatively by the screen through [YummyMachineState];
/// it never decides an outcome, it only replays boards the server sent.
class YummyMachine extends StatefulWidget {
  final List<String> initial;
  final YummyStrings strings;

  /// Ambient clock for idle glints and bulbs; null on lite phones.
  final YummyClock? clock;

  /// No motion at all: every call lands instantly.
  final bool reduced;

  /// Fewer particles, no shader, no motion ghosts.
  final bool lite;
  final bool freeSpins;
  final void Function(int reel, List<String> column)? onReelStop;
  final VoidCallback? onAnticipate;
  const YummyMachine({
    super.key,
    required this.initial,
    required this.strings,
    this.clock,
    this.reduced = false,
    this.lite = false,
    this.freeSpins = false,
    this.onReelStop,
    this.onAnticipate,
  });

  @override
  State<YummyMachine> createState() => YummyMachineState();
}

class YummyMachineState extends State<YummyMachine>
    with SingleTickerProviderStateMixin {
  final _random = math.Random();
  final _repaint = _Repaint();
  late final Ticker _ticker;
  late List<String> board = [...widget.initial];
  final List<_Reel> _reels = List.generate(5, (_) => _Reel());
  late final YummyParticles _particles =
      YummyParticles(cap: widget.lite ? 40 : 170);
  Duration _last = Duration.zero;
  double _now = 0, _animUntil = 0;
  Size _size = Size.zero;
  YummyPace pace = YummyPace.normal;

  // Win display.
  List<YummyLineWin> _wins = const [];
  Set<int> _winCells = const {};
  double _winStart = -10;
  // Pop and fall.
  Set<int> _popping = const {};
  double _popStart = -10;
  final List<double> _fallFrom = List.filled(15, 0);
  double _fallStart = -10;
  // Expanding WILDs: reel → row the WILD landed on.
  Map<int, int> _expanding = const {};
  double _expandStart = -10;
  String? _label;
  int _labelId = 0;
  bool _skipping = false;

  bool get spinning => _reels.any((reel) => reel.phase != _Phase.idle);
  bool get _motion => !widget.reduced;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    YummyAtlas.load();
    YummyAtlas.loaded.addListener(_onAtlas);
    widget.clock?.addListener(_onClock);
    for (var reel = 0; reel < 5; reel++) {
      _reels[reel].tape = _column(reel, board);
    }
  }

  @override
  void didUpdateWidget(YummyMachine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clock != widget.clock) {
      oldWidget.clock?.removeListener(_onClock);
      widget.clock?.addListener(_onClock);
    }
    _particles.cap = widget.lite ? 40 : 170;
  }

  @override
  void dispose() {
    YummyAtlas.loaded.removeListener(_onAtlas);
    widget.clock?.removeListener(_onClock);
    for (final reel in _reels) {
      if (reel.landed?.isCompleted == false) reel.landed!.complete();
    }
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _onAtlas() => _paint();
  void _onClock() {
    if (!_ticker.isActive) _paint();
  }

  void _paint() => _repaint.ping();

  List<String> _column(int reel, List<String> grid) => [
        _filler(),
        for (var row = 0; row < 3; row++) grid[row * 5 + reel],
      ];
  String _filler() => yummySymbolIds[_random.nextInt(9)];

  void _wake([double duration = 0]) {
    _animUntil = math.max(_animUntil, _now + duration);
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = math.min(.05, (elapsed - _last).inMicroseconds / 1e6);
    _last = elapsed;
    _now += dt;
    for (var index = 0; index < 5; index++) {
      _stepReel(index, dt);
    }
    _particles.step(dt);
    // Twinkles while a win shows, and sparks along expanding WILDs.
    if (!widget.lite && _size != Size.zero) {
      final sinceWin = _now - _winStart;
      if (_winCells.isNotEmpty &&
          sinceWin < 2.4 &&
          _random.nextDouble() < .35) {
        final cell = _winCells.elementAt(_random.nextInt(_winCells.length));
        _particles.twinkle(_cellRect(cell), count: 1);
      }
      final sinceExpand = _now - _expandStart;
      if (_expanding.isNotEmpty && sinceExpand < .7) {
        for (final entry in _expanding.entries) {
          final cellH = _size.height / 3;
          final reach = _expandReach(sinceExpand / .7);
          final x = (entry.key + .5) * _size.width / 5;
          final centre = (entry.value + .5) * cellH;
          _particles.trail(Offset(x, centre - reach * cellH), _scale);
          _particles.trail(Offset(x, centre + reach * cellH), _scale);
        }
      }
    }
    _paint();
    if (!spinning && _particles.isEmpty && _now > _animUntil) _ticker.stop();
  }

  double get _scale => _size.width / 360;

  void _stepReel(int index, double dt) {
    final reel = _reels[index];
    switch (reel.phase) {
      case _Phase.idle:
        return;
      case _Phase.spinning:
        if (reel.startIn > 0) {
          // Wind-up: a short pull upwards before the strip runs.
          reel.startIn -= dt;
          reel.y =
              -.14 * math.sin(math.min(1, 1 - reel.startIn / .12) * math.pi);
          return;
        }
        final target = reel.anticipating ? reel.maxSpeed * .55 : reel.maxSpeed;
        reel.speed += (target - reel.speed) * math.min(1, dt * 9);
        reel.y += reel.speed * dt;
        while (reel.y >= 1) {
          reel.y -= 1;
          reel.tape = [
            reel.queue.isNotEmpty ? reel.queue.removeAt(0) : _filler(),
            ...reel.tape.take(3),
          ];
          if (reel.queue.isEmpty && reel.landed != null) {
            reel.phase = _Phase.settling;
            reel.settleT = 0;
            reel.settleFrom = reel.y;
            break;
          }
        }
      case _Phase.settling:
        reel.settleT += dt / reel.settleTime;
        final t = math.min(1.0, reel.settleT);
        final e = Curves.easeOutCubic.transform(t);
        // Past the rest position, then a springy return.
        reel.y =
            reel.settleFrom * (1 - e) + .2 * math.sin(math.pi * e) * (1 - t);
        if (t >= 1) _finishReel(index);
    }
  }

  void _finishReel(int index) {
    final reel = _reels[index];
    reel
      ..phase = _Phase.idle
      ..y = 0
      ..speed = 0
      ..anticipating = false
      ..target = null
      ..landedAt = _now;
    final column = reel.tape.sublist(1);
    for (var row = 0; row < 3; row++) {
      board[row * 5 + index] = column[row];
    }
    final done = reel.landed;
    reel.landed = null;
    widget.onReelStop?.call(index, column);
    if (done?.isCompleted == false) done!.complete();
  }

  /// Sets the resting board with no animation.
  void setBoard(List<String> grid) {
    board = [...grid];
    for (var reel = 0; reel < 5; reel++) {
      _reels[reel]
        ..phase = _Phase.idle
        ..tape = _column(reel, board)
        ..y = 0
        ..speed = 0
        ..queue = []
        ..anticipating = false;
      if (_reels[reel].landed?.isCompleted == false) {
        _reels[reel].landed!.complete();
      }
      _reels[reel].landed = null;
    }
    _fallFrom.fillRange(0, 15, 0);
    _expanding = const {};
    _popping = const {};
    _paint();
  }

  void clearWins() {
    _wins = const [];
    _winCells = const {};
    _label = null;
    _paint();
  }

  /// Starts every reel running. Results are not known yet.
  void startSpin() {
    clearWins();
    _skipping = false;
    if (!_motion) return;
    for (var index = 0; index < 5; index++) {
      final reel = _reels[index];
      reel
        ..phase = _Phase.spinning
        ..tape = _column(index, board)
        ..y = 0
        ..speed = 0
        ..maxSpeed = pace == YummyPace.turbo ? 24 : 16
        ..settleTime = pace.settle
        ..startIn = .12 + index * .045
        ..queue = []
        ..anticipating = false;
    }
    _wake();
  }

  /// Skips the rest of the current presentation step.
  void skip() {
    _skipping = true;
    for (var index = 0; index < 5; index++) {
      final reel = _reels[index];
      final target = reel.target;
      if (reel.phase != _Phase.idle && target != null) {
        reel
          ..tape = [_filler(), ...target]
          ..queue = [];
        _finishReel(index);
      }
    }
  }

  Future<void> _wait(double seconds) async {
    if (_skipping || !_motion || seconds <= 0) return;
    final end = _now + seconds;
    _wake(seconds);
    // Poll the machine clock so a skip() cuts the wait short.
    while (mounted && !_skipping && _now < end) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  /// Lands [target] reel by reel. [elapsed] is how long the reels already ran.
  Future<void> land(List<String> target, {double elapsed = 0}) async {
    if (!_motion || _skipping || !spinning) {
      setBoard(target);
      for (var reel = 0; reel < 5; reel++) {
        widget.onReelStop?.call(reel, [
          for (var row = 0; row < 3; row++) target[row * 5 + reel],
        ]);
      }
      return;
    }
    await _wait(pace.minSpin - elapsed);
    var anticipating = false;
    for (var index = 0; index < 5; index++) {
      if (!mounted) return;
      if (index > 0) {
        await _wait(anticipating ? pace.anticipation : pace.gap);
      }
      final reel = _reels[index];
      final column = [
        for (var row = 0; row < 3; row++) target[row * 5 + index],
      ];
      reel.target = column;
      if (reel.phase == _Phase.idle) continue;
      if (_skipping) {
        reel
          ..tape = [_filler(), ...column]
          ..queue = [];
        _finishReel(index);
        continue;
      }
      final done = Completer<void>();
      reel
        ..landed = done
        ..anticipating = false
        // Inserted at the top: bottom row first, the filler last.
        ..queue = [
          target[10 + index],
          target[5 + index],
          target[index],
          _filler(),
        ];
      if (anticipating) {
        await done.future;
      } else if (yummyAnticipates(target, index + 1) && index < 4) {
        await done.future;
        anticipating = true;
        for (var later = index + 1; later < 5; later++) {
          _reels[later].anticipating = true;
        }
        widget.onAnticipate?.call();
      }
    }
    // Wait for the last reels to settle.
    for (final reel in _reels) {
      final pending = reel.landed;
      if (pending != null) await pending.future;
    }
    if (mounted) setBoard(target);
  }

  Rect _cellRect(int cell) {
    final w = _size.width / 5, h = _size.height / 3;
    return Rect.fromLTWH((cell % 5) * w, (cell ~/ 5) * h, w, h);
  }

  /// Highlights [wins], draws their lines in and floats [label] (the prize).
  Future<void> showWins(
    List<YummyLineWin> wins, {
    String? label,
    double hold = .9,
  }) async {
    _wins = wins;
    _winCells = wins.expand((win) => win.cells).toSet();
    _winStart = _now;
    _label = label;
    _labelId++;
    if (mounted) setState(() {});
    if (!_motion) return;
    _wake(2.6);
    if (!widget.lite) {
      for (final win in wins) {
        if (win.symbol == 'wild' || win.symbol == 'jackpot') {
          for (final cell in win.cells) {
            _particles.twinkle(_cellRect(cell), count: 3, color: yummyGold);
          }
        }
      }
    }
    await _wait(hold);
  }

  /// Pops [cells] into juice.
  Future<void> pop(List<int> cells) async {
    if (!_motion) return;
    _popping = cells.toSet();
    _popStart = _now;
    _wake(pace.pop + .1);
    await _wait(pace.pop * .5);
    for (final cell in cells) {
      final rect = _cellRect(cell);
      _particles.splash(
        rect.center,
        yummySymbolColors[board[cell]] ?? Colors.white,
        _scale,
        count: widget.lite ? 5 : 12,
      );
    }
    await _wait(pace.pop * .5);
  }

  /// Collapses to [next]: survivors fall, new symbols drop in from the top.
  Future<void> collapse(List<String> next, List<int> removed) async {
    final sources = yummyFallSources(removed);
    _popping = const {};
    clearWins();
    board = [...next];
    for (var cell = 0; cell < 15; cell++) {
      _fallFrom[cell] = (sources[cell] - cell ~/ 5).toDouble();
    }
    for (var reel = 0; reel < 5; reel++) {
      _reels[reel].tape = _column(reel, board);
    }
    if (!_motion) {
      _fallFrom.fillRange(0, 15, 0);
      _paint();
      return;
    }
    _fallStart = _now;
    _wake(pace.fall + .3);
    await _wait(pace.fall + .12);
    _fallFrom.fillRange(0, 15, 0);
  }

  /// Free spins: each WILD on [reels] grows over its whole reel.
  Future<void> expand(List<int> reels) async {
    final origin = <int, int>{};
    for (final reel in reels) {
      var row = 1;
      for (var r = 0; r < 3; r++) {
        if (board[r * 5 + reel] == 'wild') {
          row = r;
          break;
        }
      }
      origin[reel] = row;
    }
    _expanding = origin;
    _expandStart = _now;
    if (_motion) {
      _wake(1);
      await _wait(.75);
    }
    for (final reel in reels) {
      for (var row = 0; row < 3; row++) {
        board[row * 5 + reel] = 'wild';
      }
      _reels[reel].tape = _column(reel, board);
    }
    _expanding = const {};
    _paint();
  }

  /// Coins thrown up from the machine (a medium win).
  void coinBurst({int count = 16}) {
    if (!_motion || _size == Size.zero) return;
    _particles.coins(
      Offset.zero & _size,
      from: Offset(_size.width / 2, _size.height * .6),
      count: widget.lite ? count ~/ 3 : count,
      scale: _scale,
    );
    _wake(1.5);
  }

  double _expandReach(double t) => Curves.easeOutBack.transform(t.clamp(0, 1));

  @override
  Widget build(BuildContext context) {
    final free = widget.freeSpins;
    final frame = free
        ? const [
            Color(0xFFFFD6F5),
            Color(0xFFFF6FD0),
            Color(0xFFB03CE0),
            Color(0xFF6A1FA8),
          ]
        : const [
            Color(0xFFFFF6B8),
            yummyGold,
            Color(0xFFFFA726),
            Color(0xFFE67A00),
          ];
    final cabinet = Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: frame,
          stops: const [0, .35, .75, 1],
        ),
        boxShadow: [
          const BoxShadow(
            color: Color(0x88043180),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
          BoxShadow(
            color: (free ? const Color(0x88FF6FD0) : const Color(0x55FFE57A)),
            blurRadius: 30,
            spreadRadius: -4,
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(19),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: free
                ? const [Color(0xFF3A0B5E), Color(0xFF8E2BC9)]
                : const [Color(0xFF0A2A6B), Color(0xFF1176DC)],
          ),
        ),
        child: AspectRatio(
          aspectRatio: 5 / 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                _size = constraints.biggest;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    RepaintBoundary(
                      child: CustomPaint(
                        painter: _MachinePainter(this),
                        isComplex: true,
                        willChange: true,
                      ),
                    ),
                    _semantics(),
                    if (_label != null)
                      IgnorePointer(
                        child: Center(
                          child: _WinLabel(
                            key: ValueKey('label-$_labelId'),
                            text: _label!,
                            animate: _motion,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    final clock = widget.clock;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: CustomPaint(
        foregroundPainter: _BulbsPainter(this, clock),
        child: clock == null || widget.lite
            ? cabinet
            : YummyShine(
                clock: clock,
                period: 6,
                intensity: .55,
                child: cabinet,
              ),
      ),
    );
  }

  Widget _semantics() => Column(
        children: [
          for (var row = 0; row < 3; row++)
            Expanded(
              child: Row(
                children: [
                  for (var reel = 0; reel < 5; reel++)
                    Expanded(
                      child: Semantics(
                        label: widget.strings.text(board[row * 5 + reel]),
                        image: true,
                        selected: _winCells.contains(row * 5 + reel),
                        child: const SizedBox.expand(),
                      ),
                    ),
                ],
              ),
            ),
        ],
      );
}

class _Repaint extends ChangeNotifier {
  void ping() => notifyListeners();
}

class _WinLabel extends StatelessWidget {
  final String text;
  final bool animate;
  const _WinLabel({super.key, required this.text, required this.animate});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: animate ? 0 : 1, end: 1),
        duration: const Duration(milliseconds: 650),
        curve: Curves.elasticOut,
        builder: (context, t, child) => Transform.scale(
          scale: .4 + .6 * t,
          child: Opacity(opacity: t.clamp(0, 1), child: child),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xCC1A0B3D),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: yummyGold, width: 2),
            boxShadow: const [
              BoxShadow(color: Color(0x88FFB300), blurRadius: 14),
            ],
          ),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: yummyGold,
              fontFeatures: [FontFeature.tabularFigures()],
              shadows: [Shadow(color: Color(0xAA000000), blurRadius: 4)],
            ),
          ),
        ),
      );
}

class _MachinePainter extends CustomPainter {
  final YummyMachineState m;
  _MachinePainter(this.m) : super(repaint: m._repaint);

  static final Map<String, TextPainter> _emoji = {};
  static final List<ui.FragmentShader?> _shaders = List.filled(15, null);
  static final Paint _image = Paint()..filterQuality = FilterQuality.medium;
  static final Paint _fill = Paint();

  double get _clock => m.widget.clock?.value ?? 0;

  @override
  void paint(Canvas canvas, Size size) {
    m._size = size;
    final w = size.width / 5, h = size.height / 3;
    _background(canvas, size, w);
    for (var reel = 0; reel < 5; reel++) {
      final state = m._reels[reel];
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(reel * w, 0, w, size.height));
      if (state.phase == _Phase.idle) {
        _restingReel(canvas, reel, w, h);
      } else {
        _movingReel(canvas, reel, state, w, h);
      }
      canvas.restore();
      if (state.anticipating) _anticipation(canvas, reel, w, size.height);
    }
    _shade(canvas, size);
    if (m._wins.isNotEmpty) _lines(canvas, size);
    m._particles.paint(canvas);
  }

  void _background(Canvas canvas, Size size, double w) {
    final free = m.widget.freeSpins;
    for (var reel = 0; reel < 5; reel++) {
      final rect = Rect.fromLTWH(reel * w, 0, w, size.height);
      _fill.color = const Color(0xFFFFFFFF);
      _fill.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: free
            ? (reel.isEven
                ? const [Color(0xFFFFF0FB), Color(0xFFFFD9F2)]
                : const [Color(0xFFFFE6F7), Color(0xFFFFCDEB)])
            : (reel.isEven
                ? const [Color(0xFFFFFDF2), Color(0xFFFFF0C8)]
                : const [Color(0xFFFFF8E6), Color(0xFFFFE9BC)]),
      ).createShader(rect);
      canvas.drawRect(rect, _fill);
    }
    _fill.shader = null;
    _fill.color = free ? const Color(0x55E07BC6) : const Color(0x66E2C88A);
    for (var reel = 1; reel < 5; reel++) {
      canvas.drawRect(Rect.fromLTWH(reel * w - .5, 0, 1, size.height), _fill);
    }
  }

  void _restingReel(Canvas canvas, int reel, double w, double h) {
    final now = m._now;
    final sinceWin = now - m._winStart;
    final dimming = m._winCells.isNotEmpty;
    final sinceLand = now - m._reels[reel].landedAt;
    if (m._expanding.containsKey(reel)) {
      _expandGlow(
        canvas,
        reel,
        w,
        h * 3,
        m._expandReach((now - m._expandStart) / .7),
      );
    }
    for (var row = 0; row < 3; row++) {
      final cell = row * 5 + reel;
      final symbol = m.board[cell];
      var rect = Rect.fromLTWH(reel * w, row * h, w, h);
      var sx = 1.0, sy = 1.0, alpha = 1.0, flash = 0.0;
      // Falling in after a tumble, with a squash on landing.
      final fall = m._fallFrom[cell];
      if (fall != 0) {
        final t =
            ((now - m._fallStart - reel * .03) / m.pace.fall).clamp(0.0, 1.0);
        final drop = Curves.easeInQuad.transform(t);
        rect = rect.shift(Offset(0, fall * h * (1 - drop)));
        if (t >= 1) {
          final after = (now - m._fallStart - reel * .03 - m.pace.fall) / .18;
          if (after < 1) {
            final squash = math.sin(after.clamp(0.0, 1.0) * math.pi) * .14;
            sx += squash;
            sy -= squash;
          }
        }
      }
      // Popping.
      if (m._popping.contains(cell)) {
        final t = ((now - m._popStart) / m.pace.pop).clamp(0.0, 1.0);
        final grow = t < .5 ? 1 + t * .5 : 1.25 * (1 - (t - .5) * 2);
        sx *= grow;
        sy *= grow;
        alpha = t < .5 ? 1 : 1 - (t - .5) * 2;
        flash = t;
      }
      final winning = m._winCells.contains(cell);
      if (winning) {
        _winGlow(canvas, rect, sinceWin);
        if (sinceWin < 2.4) {
          // Squash and bounce, a beat per cell along the line.
          final beat = sinceWin * 6 - reel * .55;
          final b = math.max(0.0, math.sin(beat)) * (1 - sinceWin / 2.4);
          sy *= 1 + b * .16;
          sx *= 1 - b * .08;
          rect = rect.shift(Offset(0, -b * h * .07));
          flash = math.max(flash, b * .8);
        }
      } else if (dimming && !m._popping.contains(cell)) {
        alpha *= .45;
      }
      // Landing bounce of the whole reel already happened in settling; give
      // premium symbols an extra hop when they land.
      if (sinceLand < .35 && _premium.contains(symbol)) {
        final hop = math.sin(sinceLand / .35 * math.pi) * .1;
        sx *= 1 + hop;
        sy *= 1 + hop;
      }
      // Expanding WILD: the reel fills from the WILD's row outwards.
      final origin = m._expanding[reel];
      String drawn = symbol;
      if (origin != null) {
        final reach = m._expandReach((now - m._expandStart) / .7);
        final distance = (row - origin).abs().toDouble();
        if (reach * 1.05 >= distance) {
          drawn = 'wild';
          final grow = distance == 0
              ? 1.0
              : ((reach - distance + 1) * 1.2).clamp(0.0, 1.0);
          sx *= .4 + .6 * grow;
          sy *= .4 + .6 * grow;
          flash = math.max(flash, 1 - grow * .6);
        }
      }
      // Idle glint on premium symbols, staggered per cell.
      var glint = -1.0;
      final clock = m.widget.clock;
      if (clock != null && clock.running && _premium.contains(drawn)) {
        glint = ((_clock + cell * .37) % 3.2) / .8;
      }
      _symbol(
        canvas,
        cell,
        drawn,
        rect,
        sx: sx,
        sy: sy,
        alpha: alpha,
        flash: flash,
        glint: glint,
      );
    }
  }

  void _movingReel(Canvas canvas, int reel, _Reel state, double w, double h) {
    final blurry =
        state.phase == _Phase.spinning && state.speed > 6 && !m.widget.lite;
    for (var k = 0; k < 4; k++) {
      final rect = Rect.fromLTWH(reel * w, (k - 1 + state.y) * h, w, h);
      final symbol = state.tape[k];
      if (blurry) {
        // Motion ghosts stand in for a blur filter (cheap on any phone).
        final stretch = math.min(.35, state.speed / 60);
        _symbol(
          canvas,
          -1,
          symbol,
          rect.shift(Offset(0, -h * .18)),
          sy: 1 + stretch,
          alpha: .28,
        );
        _symbol(canvas, -1, symbol, rect, sy: 1 + stretch * .6, alpha: .8);
      } else {
        _symbol(canvas, -1, symbol, rect);
      }
    }
  }

  void _anticipation(Canvas canvas, int reel, double w, double height) {
    final pulse = .5 + .5 * math.sin(m._now * 10);
    final rect = Rect.fromLTWH(reel * w + 2, 2, w - 4, height - 4);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));
    _fill
      ..shader = null
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = yummyGold.withValues(alpha: .6 + .4 * pulse)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawRRect(rrect, _fill);
    _fill
      ..maskFilter = null
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: .8);
    canvas.drawRRect(rrect, _fill);
    _fill.style = PaintingStyle.fill;
  }

  void _winGlow(Canvas canvas, Rect rect, double since) {
    final pulse = .5 + .5 * math.sin(since * 7);
    final inner = rect.deflate(3);
    _fill.color = const Color(0xFFFFFFFF);
    _fill.shader = RadialGradient(
      colors: [
        Colors.white.withValues(alpha: .95),
        Color.lerp(const Color(0xFFFFE880), yummyGold, pulse)!
            .withValues(alpha: .9),
      ],
    ).createShader(inner);
    final rrect = RRect.fromRectAndRadius(inner, const Radius.circular(12));
    canvas.drawRRect(rrect, _fill);
    _fill
      ..shader = null
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white;
    canvas.drawRRect(rrect, _fill);
    _fill.style = PaintingStyle.fill;
  }

  void _expandGlow(
    Canvas canvas,
    int reel,
    double w,
    double height,
    double reach,
  ) {
    final rect = Rect.fromLTWH(reel * w, 0, w, height);
    _fill.color = const Color(0xFFFFFFFF);
    _fill.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        yummyGold.withValues(alpha: 0),
        yummyGold.withValues(alpha: .45 * reach.clamp(0.0, 1.0)),
        yummyGold.withValues(alpha: 0),
      ],
    ).createShader(rect);
    canvas.drawRect(rect, _fill);
    _fill.shader = null;
  }

  void _symbol(
    Canvas canvas,
    int cell,
    String symbol,
    Rect rect, {
    double sx = 1,
    double sy = 1,
    double alpha = 1,
    double flash = 0,
    double glint = -1,
  }) {
    if (alpha <= 0.01) return;
    final pad = rect.shortestSide * .07;
    final box = Rect.fromCenter(
      center: rect.center,
      width: rect.shortestSide - pad * 2,
      height: rect.shortestSide - pad * 2,
    );
    canvas.save();
    canvas.translate(box.center.dx, box.bottom);
    canvas.scale(sx, sy);
    final local =
        Rect.fromLTWH(-box.width / 2, -box.height, box.width, box.height);
    final image = YummyAtlas.images[symbol];
    if (image == null) {
      final painter = _emoji.putIfAbsent(
        '$symbol@${box.width.round()}',
        () => TextPainter(
          text: TextSpan(
            text: yummyEmoji[symbol] ?? '?',
            style: TextStyle(fontSize: box.width * .68),
          ),
          textDirection: TextDirection.ltr,
        )..layout(),
      );
      if (alpha < 1) {
        canvas.saveLayer(
          local,
          Paint()..color = Color.fromRGBO(0, 0, 0, alpha),
        );
      }
      painter.paint(
        canvas,
        local.center - Offset(painter.width / 2, painter.height / 2),
      );
      if (alpha < 1) canvas.restore();
      canvas.restore();
      return;
    }
    final program = m.widget.lite ? null : YummyShaders.symbol;
    final shaded = cell >= 0 &&
        program != null &&
        ((glint >= 0 && glint <= 1) || flash > 0);
    if (shaded) {
      final shader = _shaders[cell] ??= program.fragmentShader();
      shader
        ..setFloat(0, local.left)
        ..setFloat(1, local.top)
        ..setFloat(2, local.width)
        ..setFloat(3, local.height)
        ..setFloat(4, glint >= 0 && glint <= 1 ? glint : -1)
        ..setFloat(5, flash.clamp(0, 1))
        ..setFloat(6, alpha.clamp(0, 1))
        ..setImageSampler(0, image);
      canvas.drawRect(local, Paint()..shader = shader);
    } else {
      _image.color = Color.fromRGBO(255, 255, 255, alpha.clamp(0, 1));
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        local,
        _image,
      );
      if (flash > 0) {
        _image.color =
            Color.fromRGBO(255, 255, 255, (flash * .35 * alpha).clamp(0, 1));
        _image.blendMode = BlendMode.plus;
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          local,
          _image,
        );
        _image.blendMode = BlendMode.srcOver;
      }
    }
    canvas.restore();
  }

  void _shade(Canvas canvas, Size size) {
    _fill.color = const Color(0xFFFFFFFF);
    _fill.shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0x40000000),
        Color(0x00000000),
        Color(0x00000000),
        Color(0x33000000),
      ],
      stops: [0, .14, .86, 1],
    ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, _fill);
    _fill.shader = null;
  }

  static const _lineColors = [
    Color(0xFFFF2D6F),
    Color(0xFF1E7BFF),
    Color(0xFF9B4DFF),
    Color(0xFF00B386),
    Color(0xFFFF7A00),
    Color(0xFFE81FC6),
    Color(0xFF2E55D9),
    Color(0xFF55B800),
    Color(0xFFE5373F),
  ];

  void _lines(Canvas canvas, Size size) {
    final since = m._now - m._winStart;
    final progress = m.widget.reduced
        ? 1.0
        : Curves.easeOutCubic
            .transform((since / m.pace.lineDraw).clamp(0.0, 1.0));
    final pulse = .5 + .5 * math.sin(since * 7);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final win in m._wins) {
      final full = Path();
      for (var reel = 0; reel < 5; reel++) {
        final point = Offset(
          (reel + .5) * size.width / 5,
          (yummyPaylines[win.line][reel] + .5) * size.height / 3,
        );
        reel == 0
            ? full.moveTo(point.dx, point.dy)
            : full.lineTo(point.dx, point.dy);
      }
      final path = Path();
      for (final metric in full.computeMetrics()) {
        path.addPath(
          metric.extractPath(0, metric.length * progress),
          Offset.zero,
        );
      }
      final color = _lineColors[win.line % _lineColors.length];
      canvas.drawPath(
        path,
        stroke
          ..color = color.withValues(alpha: .5)
          ..strokeWidth = 12
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      stroke.maskFilter = null;
      canvas.drawPath(
        path,
        stroke
          ..color = Colors.white
          ..strokeWidth = 6.5,
      );
      canvas.drawPath(
        path,
        stroke
          ..color = color
          ..strokeWidth = 3.4 + pulse * 1.2,
      );
      // A spark riding the head of the line while it draws.
      if (progress < 1) {
        for (final metric in full.computeMetrics()) {
          final at = metric.getTangentForOffset(metric.length * progress);
          if (at != null) {
            _fill.color = Colors.white;
            canvas.drawCircle(at.position, 5, _fill);
          }
        }
      }
    }
  }

  @override
  // A rebuild means the state changed (wins, skin); ticks repaint via [m._repaint].
  bool shouldRepaint(_MachinePainter old) => true;
}

/// Bulbs around the cabinet. Every third bulb is lit and the pattern chases
/// while the machine or the ambient clock runs; free spins chase faster.
class _BulbsPainter extends CustomPainter {
  final YummyMachineState m;
  final YummyClock? clock;
  _BulbsPainter(this.m, this.clock)
      : super(
          repaint: Listenable.merge([m._repaint, if (clock != null) clock]),
        );

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 6.5;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(28),
    ).deflate(inset);
    final metric = (Path()..addRRect(rect)).computeMetrics().first;
    final count = (metric.length / 22).floor();
    final speed = m.widget.freeSpins || m.spinning ? 9 : 3;
    final time = math.max(m._now, clock?.value ?? 0);
    final shift = (time * speed).floor() % 3;
    final free = m.widget.freeSpins;
    for (var i = 0; i < count; i++) {
      final at = metric.getTangentForOffset(metric.length * i / count)!;
      final lit = (i + shift) % 3 == 0;
      if (lit) {
        canvas.drawCircle(
          at.position,
          5.5,
          Paint()
            ..color = const Color(0xCCFFFFFF)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }
      canvas.drawCircle(
        at.position,
        2.6,
        Paint()
          ..color = lit
              ? Colors.white
              : free
                  ? const Color(0xFF8E1F8A)
                  : const Color(0xFFB8620A),
      );
    }
  }

  @override
  bool shouldRepaint(_BulbsPainter old) => old.m != m || old.clock != clock;
}
