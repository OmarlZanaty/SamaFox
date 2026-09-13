import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/dio_client.dart';

/// Blocks an out-of-date build and sends the user to Play.
///
/// The server publishes `minSupportedBuild` on the public `/settings` endpoint.
/// A device whose own build number is lower gets a screen it cannot dismiss —
/// no back button, no tap-outside — because the point is that the old client is
/// no longer allowed to talk to the server, not that the user is being asked
/// nicely.
///
/// Three deliberate choices:
///
///  • **Fails OPEN.** If the check throws, times out, or the server is
///    unreachable, the app carries on as normal. A version gate that blocks
///    users when the network hiccups is worse than no gate: it turns a brief
///    outage into "the app is dead" for everyone at once.
///  • **Default 0 = disabled.** A missing or unparseable setting never locks
///    anyone out. Locking the whole user base out has to be a deliberate act.
///  • **Checked once at startup**, not on every resume. Nobody should be thrown
///    out mid-sentence in a room because a setting changed while they talked.
class ForceUpdateGate {
  ForceUpdateGate._();

  /// True when this build is older than the server's minimum.
  ///
  /// Never throws: every failure path returns false.
  static Future<UpdateVerdict?> check() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final mine = int.tryParse(info.buildNumber) ?? 0;
      if (mine <= 0) return null; // Can't tell; don't guess, don't block.

      final resp = await DioClient.dio.get('/settings');
      final data = (resp.data is Map ? resp.data['data'] : null);
      if (data is! Map) return null;

      final min = (data['minSupportedBuild'] as num?)?.toInt() ?? 0;
      if (min <= 0 || mine >= min) return null;

      return UpdateVerdict(
        title: data['updateTitle']?.toString() ?? 'تحديث جديد متاح',
        message: data['updateMessage']?.toString() ??
            'نزّل آخر إصدار عشان تكمل استخدام التطبيق.',
        storeUrl: data['updateStoreUrl']?.toString() ??
            'https://play.google.com/store/apps/details?id=com.almobarmg.samafox',
        mine: mine,
        required: min,
      );
    } catch (e) {
      // Fail open — see the class doc.
      debugPrint('[ForceUpdateGate] check skipped: $e');
      return null;
    }
  }

  /// Runs the check and, if this build is too old, shows the blocking screen.
  static Future<void> enforce(BuildContext context) async {
    final verdict = await check();
    if (verdict == null || !context.mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        barrierDismissible: false,
        pageBuilder: (_, __, ___) => UpdateRequiredScreen(verdict: verdict),
      ),
    );
  }
}

class UpdateVerdict {
  const UpdateVerdict({
    required this.title,
    required this.message,
    required this.storeUrl,
    required this.mine,
    required this.required,
  });

  final String title;
  final String message;
  final String storeUrl;
  final int mine;
  final int required;
}

/// The screen an out-of-date build ends on.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key, required this.verdict});

  final UpdateVerdict verdict;

  Future<void> _openStore(BuildContext context) async {
    final uri = Uri.parse(verdict.storeUrl);
    try {
      // externalApplication so it opens the Play app rather than a web view —
      // a store page inside the app cannot install anything.
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok || !context.mounted) return;
    } catch (_) {
      // fall through to the message below
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('افتح Google Play وابحث عن سما فوكس')),
    );
  }

  @override
  Widget build(BuildContext context) {
    // PopScope with canPop:false is what makes this a gate rather than a
    // suggestion — back, gesture and the system button all do nothing.
    return PopScope(
      canPop: false,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF2A1655), Color(0xFF14082B)],
              ),
            ),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFFF4081).withValues(alpha: 0.16),
                          border: Border.all(
                            color: const Color(0xFFFF4081).withValues(alpha: 0.5),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.rocket_launch_rounded,
                          size: 52,
                          color: Color(0xFFFF4081),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        verdict.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        verdict.message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF4081),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () => _openStore(context),
                          icon: const Icon(Icons.system_update_alt_rounded),
                          label: const Text(
                            'تحديث الآن',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      // Quiet, but present: someone reporting "it won't let me
                      // in" can read these two numbers out and the answer is
                      // immediate.
                      Text(
                        'الإصدار الحالي ${verdict.mine} • المطلوب ${verdict.required}',
                        style: const TextStyle(
                          color: Colors.white30,
                          fontSize: 11,
                        ),
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
}
