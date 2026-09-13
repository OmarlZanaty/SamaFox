import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/localization_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/force_update_gate.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initialize();
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
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Custom Logo
            Image.asset(
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
