import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../repositories/fruit_jackpot_repository.dart';
import 'fruit_jackpot_engine.dart';
import 'fruit_jackpot_strings.dart';

class FruitJackpotFairness extends StatefulWidget {
  final FruitJackpotRepository repository;
  final FruitJackpotRound? round;
  final FruitJackpotStrings strings;
  const FruitJackpotFairness({
    super.key,
    required this.repository,
    required this.strings,
    this.round,
  });
  @override
  State<FruitJackpotFairness> createState() => _FruitJackpotFairnessState();
}

class _FruitJackpotFairnessState extends State<FruitJackpotFairness> {
  final _client = TextEditingController();
  final _server = TextEditingController();
  Map<String, dynamic> _fair = {};
  bool _busy = true;
  String? _notice;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _client.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _notice = widget.strings.text('error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _run(() async {
    final result = await widget.repository.request('fair');
    if (!mounted) return;
    setState(
      () => _fair = Map<String, dynamic>.from(result['fairness'] as Map),
    );
    _client.text = _fair['clientSeed']?.toString() ?? '';
  });
  Future<void> _save() => _run(() async {
    final result = await widget.repository.request(
      'seed',
      data: {'clientSeed': _client.text},
    );
    if (mounted) {
      setState(() {
        _fair = Map<String, dynamic>.from(result['fairness'] as Map);
        _notice = widget.strings.text('seedSaved');
      });
    }
  });
  Future<void> _rotate() => _run(() async {
    final result = await widget.repository.request('seed/rotate', data: {});
    if (!mounted) return;
    _server.text = (result['revealed'] as Map)['serverSeed'] as String;
    setState(() {
      _fair = {
        ..._fair,
        'serverSeedHash': result['serverSeedHash'],
        'nonce': 0,
      };
      _notice = null;
    });
  });
  Future<void> _verify() => _run(() async {
    final round = widget.round;
    if (round == null) {
      setState(() => _notice = widget.strings.text('noRound'));
      return;
    }
    final result = await widget.repository.request(
      'verify',
      data: {
        'serverSeed': _server.text.trim(),
        'clientSeed': round.clientSeed,
        'nonce': round.nonce,
        'betPerLine': round.betPerLine,
        'activeLines': round.activeLines,
      },
    );
    final spin = Map<String, dynamic>.from(result['spin'] as Map);
    final matches =
        spin['serverSeedHash'] == round.serverSeedHash &&
        listEquals(List<String>.from(spin['grid'] as List), round.grid) &&
        spin['totalPrize'] == round.requestedPrize &&
        spin['bonusMultiplier'] == round.bonusMultiplier;
    if (mounted) {
      setState(
        () => _notice = widget.strings.text(matches ? 'verified' : 'mismatch'),
      );
    }
  });
  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(strings.text('fairHelp')),
        const SizedBox(height: 16),
        Text(strings.text('commitment')),
        SelectableText(
          _fair['serverSeedHash']?.toString() ?? '…',
          textDirection: TextDirection.ltr,
        ),
        Text('${strings.text('nonce')}: ${_fair['nonce'] ?? '…'}'),
        const SizedBox(height: 12),
        TextField(
          controller: _client,
          maxLength: 64,
          decoration: InputDecoration(labelText: strings.text('clientSeed')),
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(strings.text('save')),
            ),
            OutlinedButton(
              onPressed: _busy ? null : _rotate,
              child: Text(strings.text('rotate')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _server,
          maxLength: 64,
          decoration: InputDecoration(labelText: strings.text('revealed')),
        ),
        FilledButton(
          onPressed: _busy ? null : _verify,
          child: Text(strings.text('verify')),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_notice != null) Semantics(liveRegion: true, child: Text(_notice!)),
      ],
    );
  }
}
