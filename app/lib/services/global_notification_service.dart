import 'dart:async';

class GlobalNotificationEvent {
  final String title;
  final String message;
  final String? routeName;

  const GlobalNotificationEvent({
    required this.title,
    required this.message,
    this.routeName,
  });
}

class GlobalNotificationService {
  GlobalNotificationService._();
  static final GlobalNotificationService instance = GlobalNotificationService._();

  final _controller = StreamController<GlobalNotificationEvent>.broadcast();
  Stream<GlobalNotificationEvent> get stream => _controller.stream;

  void show(GlobalNotificationEvent event) => _controller.add(event);

  void dispose() => _controller.close();
}
