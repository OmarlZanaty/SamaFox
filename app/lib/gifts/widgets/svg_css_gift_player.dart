import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/gift.dart';

/// Renders an SVG_CSS gift via a transparent WebView.
/// Hard rules per spec:
///  - JavaScript disabled
///  - Transparent background
///  - Pointer events ignored
///  - Forced completion timer with 500ms grace
class SvgCssGiftPlayer extends StatefulWidget {
  const SvgCssGiftPlayer({
    super.key,
    required this.gift,
    required this.onComplete,
    this.onError,
  });

  final Gift gift;
  final VoidCallback onComplete;
  final VoidCallback? onError;

  @override
  State<SvgCssGiftPlayer> createState() => _SvgCssGiftPlayerState();
}

class _SvgCssGiftPlayerState extends State<SvgCssGiftPlayer> {
  late final WebViewController _controller;
  Timer? _hardTimer;
  Timer? _loadFallback;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    final html = widget.gift.animationHtml;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setBackgroundColor(const Color(0x00000000));

    if (html == null || html.isEmpty) {
      // Schedule completion next frame to avoid setState during build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onError?.call();
        _markComplete();
      });
    } else {
      _controller.loadHtmlString(html, baseUrl: 'about:blank');
      _loadFallback = Timer(const Duration(milliseconds: 500), () {
        // visible content should be present by now; if not we still proceed.
      });
    }

    _hardTimer = Timer(
      Duration(milliseconds: widget.gift.animationMs + 500),
      _markComplete,
    );
  }

  void _markComplete() {
    if (_completed) return;
    _completed = true;
    widget.onComplete();
  }

  @override
  void dispose() {
    _hardTimer?.cancel();
    _loadFallback?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final html = widget.gift.animationHtml;
    if (html == null || html.isEmpty) {
      return Center(
        child: Image.network(
          widget.gift.iconUrl,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      );
    }
    return IgnorePointer(
      ignoring: true,
      child: WebViewWidget(controller: _controller),
    );
  }
}
