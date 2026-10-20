import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/permission_gate.dart';

class ScreenRecordService {
  ScreenRecordService._() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'stateChanged' && call.arguments is Map) {
        final state = Map<String, dynamic>.from(call.arguments as Map);
        recording.value = state['recording'] == true;
        _events.add(state);
      }
    });
  }
  static final instance = ScreenRecordService._();
  static const _channel = MethodChannel('samafox/screen_record');
  final recording = ValueNotifier(false);
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _events.stream;
  bool get supported => !kIsWeb && Platform.isAndroid;
  static const fallbackHint = 'قد لا يتضمن التسجيل أصوات الغرفة على هذا الجهاز';

  Future<bool> get isRecording async {
    if (!supported) return false;
    try { return await _channel.invokeMethod<bool>('isRecording') ?? false; }
    on PlatformException { return false; }
    on MissingPluginException { return false; }
  }

  Future<bool> get roomAudioIncluded async {
    if (!supported) return false;
    try { return await _channel.invokeMethod<bool>('roomAudioIncluded') ?? false; }
    on PlatformException { return false; }
    on MissingPluginException { return false; }
  }

  Future<bool> start() async {
    if (!supported) return false;
    try {
      if (!(await PermissionGate.request(Permission.microphone)).isGranted) {
        _events.add({'recording': false, 'error': 'اسمح بالوصول إلى الميكروفون للتسجيل'});
        return false;
      }
      final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      if (sdk >= 33) await PermissionGate.request(Permission.notification);
      if (sdk <= 28 && !(await PermissionGate.request(Permission.storage)).isGranted) {
        _events.add({'recording': false, 'error': 'اسمح بحفظ الفيديو في الاستوديو'});
        return false;
      }
      return await _channel.invokeMethod<bool>('start') ?? false;
    } on PlatformException catch (e) {
      debugPrint('[ScreenRecord] ${e.message}');
      _events.add({'recording': false, 'error': 'تعذر بدء التسجيل'});
      return false;
    } on MissingPluginException { return false; }
  }

  /// Completes only after codecs/muxer finish and MediaStore publishes the MP4.
  Future<String?> stop() async {
    if (!supported) return null;
    try { return await _channel.invokeMethod<String>('stop'); }
    on PlatformException { return null; }
    on MissingPluginException { return null; }
  }
}
