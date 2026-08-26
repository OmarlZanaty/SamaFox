import 'dart:async';

/// A21 — how long an in-app banner stays, and where it sits.
///
/// The client's complaint (17/08 23:01) was specific: two banners *"مدتهم
/// طويلة جداً وبيغطوا على شريط الهدايا فوق"* — the agent-percentage banner and
/// the gift-received notification. His instructions, verbatim in outline:
///
///   • gift-received notice → **1 to 1.5 seconds max**, with the notifications
///     list kept as the place to review one you missed
///   • agent-percentage banner → same system, but (1) moved to sit **directly
///     below** the gift bar instead of on top of it, and (2) capped at ~1.5s
///   • the gift bar itself → **do not touch** its position or duration
///
/// So the banner keeps one look and one code path; only its dwell time and its
/// top offset vary, and both are properties of the event that raised it.
class GlobalNotificationEvent {
  final String title;
  final String message;
  final String? routeName;

  /// How long the banner stays before sliding away.
  final Duration duration;

  /// Extra space above the banner, in logical pixels. Used to drop a banner
  /// below the room's gift bar so it never covers it.
  final double topOffset;

  const GlobalNotificationEvent({
    required this.title,
    required this.message,
    this.routeName,
    this.duration = kNotificationDefaultDuration,
    this.topOffset = 0,
  });
}

/// Ordinary notices (follows, relations, messages) keep a readable dwell time —
/// the client's cap was aimed at the two banners that fight the gift bar.
const Duration kNotificationDefaultDuration = Duration(seconds: 6);

/// The cap the client asked for on the gift-received and agent-percentage
/// banners: "من ثانية إلى ثانية ونصف بالكثير".
const Duration kNotificationBriefDuration = Duration(milliseconds: 1500);

/// Height reserved for the room's top gift bar. A banner raised with this
/// offset starts *below* the bar rather than over it, which is the whole of
/// the client's position complaint. Matches the broadcast banner's own
/// AspectRatio box plus its padding.
const double kBelowGiftBarOffset = 96;

class GlobalNotificationService {
  GlobalNotificationService._();
  static final GlobalNotificationService instance = GlobalNotificationService._();

  final _controller = StreamController<GlobalNotificationEvent>.broadcast();
  Stream<GlobalNotificationEvent> get stream => _controller.stream;

  void show(GlobalNotificationEvent event) => _controller.add(event);

  void dispose() => _controller.close();
}
