import 'dart:async';
import 'dart:io';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'room_share_service.dart';
import 'active_room.dart';
import 'package:dio/dio.dart';
import '../widgets/room/room_jump.dart';

/// One pending invitation survives authentication and process restarts. Home
/// signals readiness after its route replaces login/splash, avoiding a race in
/// which the login navigation removes the invitation room immediately.
class RoomLinkHandler {
  RoomLinkHandler._();
  static final instance = RoomLinkHandler._();
  final _links = AppLinks();
  static const _channel = MethodChannel('samafox/room_audio');
  static const _pendingKey = 'pending_room_share_token';
  StreamSubscription<Uri>? _subscription;
  GlobalKey<NavigatorState>? _navigator;
  String? _pending;
  String? _active;
  bool _ready = false;
  bool _opening = false;

  Future<void> initialize(GlobalKey<NavigatorState> navigator) async {
    _navigator = navigator;
    final preferences = await SharedPreferences.getInstance();
    _pending = preferences.getString(_pendingKey);
    _subscription = _links.uriLinkStream.listen((uri) {
      final token = RoomShareService.tokenFromUri(uri);
      if (token != null) unawaited(accept(token));
    }, onError: (Object error) { debugPrint('[RoomLink] $error'); });
    try {
      final initial = await _links.getInitialLink();
      final token = initial == null ? null : RoomShareService.tokenFromUri(initial);
      if (token != null) await accept(token);
      if (!kIsWeb && Platform.isAndroid) {
        final referrer = await _channel.invokeMethod<String>('installReferrer');
        final deferred = referrer == null ? null : Uri.splitQueryString(referrer)['room_token'];
        if (_pending == null && deferred != null && RoomShareService.validToken(deferred)) await accept(deferred);
        // Acknowledge only after Dart has durably stored the deferred token.
        if (referrer != null) await _channel.invokeMethod<void>('ackInstallReferrer');
      }
    } catch (error) { debugPrint('[RoomLink] $error'); }
    await _openPending();
  }

  void homeReady() { _ready = true; unawaited(_openPending()); }
  void signedOut() { _ready = false; RoomShareService.joinTokens.clear(); }

  Future<void> accept(String token) async {
    if (!RoomShareService.validToken(token) || token == _active) return;
    _pending = token;
    await (await SharedPreferences.getInstance()).setString(_pendingKey, token);
    await _openPending();
  }

  Future<void> _openPending() async {
    if (!_ready || _opening || _pending == null || _navigator?.currentState == null) return;
    _opening = true;
    final token = _pending!;
    try {
      final roomId = await RoomShareService.resolve(token);
      if (!_ready || token != _pending) return;
      _pending = null;
      await (await SharedPreferences.getInstance()).remove(_pendingKey);
      _active = token;
      if (ActiveRoom.instance.roomId != null) {
        // Already in a room: the shared «الانتقال إلى هذه الغرفة؟» flow leaves
        // the current room properly instead of stacking a second one.
        await confirmAndJumpToRoom(roomId, question: 'لديك دعوة إلى غرفة — هل تريد الانتقال إليها؟');
        if (_active == token) _active = null;
      } else {
        unawaited(_navigator!.currentState!.pushNamed('/room', arguments: roomId).whenComplete(() {
          if (_active == token) _active = null;
        }));
      }
    } catch (error) {
      // The server refused this invitation (expired, banned, closed): it can
      // never succeed, so forget it. Only a network failure keeps it for later.
      if (error is DioException && error.response != null && token == _pending) {
        _pending = null;
        await (await SharedPreferences.getInstance()).remove(_pendingKey);
      }
      final context = _navigator?.currentContext;
      if (context != null && context.mounted) {
        // A dialog works above Navigator; ScaffoldMessenger may have no current
        // scaffold at this context during a route transition.
        await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
          content: Text(RoomShareService.errorMessage(error)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
        ));
      }
      // Keep the token for a network failure/relaunch. A later link replaces it.
    } finally { _opening = false; }
    if (_pending != null && _pending != token) unawaited(_openPending());
  }

  void dispose() { _subscription?.cancel(); }
}
