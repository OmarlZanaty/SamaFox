import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/dio_client.dart';
import '../widgets/home/cp_ranking_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/localization_provider.dart';
import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/force_update_gate.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  HomeCpEntry? _cp;
  final _cpCancel = CancelToken();
  static const _cpKey = 'home_cp_top_one';
  @override
  void initState() {
    super.initState();
    unawaited(_loadCp());
    _initialize();
  }

  Future<void> _loadCp() async {
    // Cache/network work never joins the navigation initialization future.
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cpKey);
      if (cached != null && mounted) {
        setState(() => _cp = HomeCpEntry(Map<String, dynamic>.from(jsonDecode(cached) as Map)));
      }
    } catch (_) { /* A damaged cache must not prevent the live request. */ }
    if (!mounted) return;
    try {
      final response = await DioClient.dio.get('/cp/top', queryParameters: {'limit': 1},
        cancelToken: _cpCancel).timeout(const Duration(milliseconds: 1500), onTimeout: () {
          _cpCancel.cancel('Splash CP deadline');
          throw TimeoutException('Splash CP deadline');
        });
      final rows = response.data['data'] as List;
      final next = rows.isEmpty ? null : HomeCpEntry(Map<String, dynamic>.from(rows.first as Map));
      if (mounted) setState(() => _cp = next);
      if (next == null) { await prefs?.remove(_cpKey); }
      else { await prefs?.setString(_cpKey, jsonEncode(next.json)); }
    } catch (_) { /* Keep the last known pair; startup continues independently. */ }
  }

  @override
  void dispose() {
    _cpCancel.cancel('Splash closed');
    super.dispose();
  }

  /// How long the logo is guaranteed to stay up. Long enough to read, short
  /// enough not to be felt.
  static const Duration _minSplash = Duration(milliseconds: 900);

  Future<void> _initialize() async {
    // A12 — "التطبيق ثقيل … بيفتح لكن بطيء جداً".
    //
    // Boot used to sleep a flat 2 seconds and only THEN start the auth request,
    // so every cold start cost 2s plus a full network round trip in series —
    // and on a slow connection that is exactly the "hangs on open" the client
    // described. The two now overlap: the splash lasts however long the slower
    // of the timer and the auth check takes, not the sum of both.
    // The update gate rides along with the auth check rather than after it:
    // both are network calls the splash is already waiting on, so checking the
    // version costs no extra time on a cold start. It fails open, so a slow or
    // unreachable server never turns into a locked-out user.
    // Started first so it runs alongside the two below rather than after them.
    final updateCheck = ForceUpdateGate.check();

    await Future.wait([
      Future<void>.delayed(_minSplash),
      ref.read(authStateProvider.notifier).checkAuthStatus(),
    ]);
    final verdict = await updateCheck;

    if (!mounted) return;

    // An out-of-date build stops here and never reaches home or login: the old
    // client is no longer allowed to talk to the server, so there is nothing
    // useful past this screen.
    if (verdict != null) {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => UpdateRequiredScreen(verdict: verdict),
        ),
      );
      return;
    }

    final authState = ref.read(authStateProvider);

    if (authState.isAuthenticated) {
      Navigator.of(context).pushReplacementNamed('/home');
    } else {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }


  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundDarkPurple,
      body: SafeArea(child: _appIdentity(strings)),
    );
  }

  Widget _appIdentity(AppStrings strings) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Custom Logo
            if (_cp != null) ...[
              const Text('♛', style: TextStyle(color: Color(0xFFFFD477), fontSize: 56)),
              SizedBox(width: 250, height: 210, child: Stack(alignment: Alignment.center, children: [
                const Icon(Icons.favorite, color: Color(0xFFFFD477), size: 245),
                const Icon(Icons.favorite, color: Color(0xFF702E71), size: 228),
                Padding(padding: const EdgeInsets.only(bottom: 26),
                  child: CpPairAvatars(pair: _cp!.pair, size: 84)),
              ])),
              Text('${_cp!.pair.a.name} ❤ ${_cp!.pair.b.name}', textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 22)),
              const Text('CP Top 1', style: TextStyle(color: Color(0xFFFFD477), fontSize: 24, fontWeight: FontWeight.bold)),
              CpLevelBadge(pair: _cp!.pair),
            ] else Image.asset(
              'assets/images/logo.png',
              width: 200,
              height: 200,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 24),
            // Tagline
            Text(
              strings.splashTagline,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 48),
            // Loading indicator
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryPurple),
            ),
          ],
        ),
      ),
    );
  }
}
