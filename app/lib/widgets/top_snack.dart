import 'package:flutter/material.dart';

/// Shows a SnackBar at the TOP of the screen. The default floating snackbar
/// sits at the bottom and covers the bottom navigation / room icons (client
/// 3/11: "شيل الاشعار اللي تحت ده بيغطي علي كل الايقونات"). A big bottom margin
/// pushes it up to the top safe area instead.
void showTopSnackBar(BuildContext context, SnackBar bar) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final mq = MediaQuery.of(context);
  final bottom = (mq.size.height - mq.padding.top - 120).clamp(0.0, double.infinity);
  messenger.showSnackBar(
    SnackBar(
      content: bar.content,
      action: bar.action,
      backgroundColor: bar.backgroundColor,
      duration: bar.duration,
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(12, 0, 12, bottom),
    ),
  );
}
