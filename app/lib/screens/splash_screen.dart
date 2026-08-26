import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/localization_provider.dart';
import '../theme/app_theme.dart';

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
    await Future.wait([
      Future<void>.delayed(_minSplash),
      ref.read(authStateProvider.notifier).checkAuthStatus(),
    ]);

    if (!mounted) return;

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
