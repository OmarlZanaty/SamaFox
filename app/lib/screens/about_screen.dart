import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../providers/locale_provider.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  /// The installed build, read once. The screen used to say "1.0.0" forever.
  static final Future<PackageInfo> _info = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = theme.textTheme.bodyMedium?.color?.withOpacity(0.7);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A0E3E) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.iconTheme.color),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          strings.about,
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              // Full width so the column centres on a tablet or desktop too.
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 48,
                minWidth: constraints.maxWidth - 40,
              ),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    const Spacer(),
                    // SamaFox first and largest: this is the app's own page.
                    Image.asset('assets/images/logo.png',
                        width: 120, height: 120),
                    const SizedBox(height: 20),
                    Text(
                      strings.appName,
                      style: TextStyle(
                        color: theme.textTheme.bodyLarge?.color,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<PackageInfo>(
                      future: _info,
                      builder: (context, snap) => Text(
                        snap.hasData
                            ? '${strings.version} ${snap.data!.version} (${snap.data!.buildNumber})'
                            : ' ',
                        style: TextStyle(color: secondary, fontSize: 15),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      strings.splashTagline,
                      style: TextStyle(color: secondary, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const Spacer(flex: 2),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
