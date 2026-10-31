import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// A room picture ready to upload: the bytes and a filename whose extension
/// matches them.
class RoomPicture {
  const RoomPicture(this.bytes, this.filename);
  final Uint8List bytes;
  final String filename;
}

/// «صورة الغرفه المتحركه بال vip مش شغاله»: the room pickers passed
/// `imageQuality` / `maxWidth`, and on Android image_picker then re-encodes
/// the picked file — a GIF came back as a still JPEG, so the animation was
/// gone before the VIP check on the server ever saw it.
///
/// The file is now picked untouched. An animated GIF / WebP is uploaded as
/// it is; a still photo over 1.5 MB is scaled down to 1280 px wide.
///
/// Weak phones (31/10, Huawei STK-L21) kill the app while the gallery is
/// open; the native picker then stays "already_active" and every later tap
/// threw, so the room was never created. A second tap while a pick is
/// running returns null, and a stale pick is collected or restarted.
Future<RoomPicture?> pickRoomPicture() async {
  if (_picking) return null;
  _picking = true;
  try {
    final picked = await _pickOnce();
    if (picked == null) return null;
    return roomPictureFrom(await picked.readAsBytes(), picked.name);
  } finally {
    _picking = false;
  }
}

bool _picking = false;

Future<XFile?> _pickOnce() async {
  final picker = ImagePicker();
  try {
    return await picker.pickImage(source: ImageSource.gallery);
  } on PlatformException catch (e) {
    if (e.code != 'already_active' || !_isAndroid) rethrow;
    final lost = await picker.retrieveLostData();
    return lost.file ?? await picker.pickImage(source: ImageSource.gallery);
  }
}

bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// The picture chosen just before Android killed the app, if any.
Future<RoomPicture?> recoverLostRoomPicture() async {
  if (!_isAndroid) return null;
  try {
    final lost = await ImagePicker().retrieveLostData();
    final file = lost.file;
    if (file == null) return null;
    return roomPictureFrom(await file.readAsBytes(), file.name);
  } catch (_) {
    return null;
  }
}

const _maxUploadBytes = 4 * 1024 * 1024;
const _scaleAboveBytes = 1536 * 1024;

Future<RoomPicture> roomPictureFrom(Uint8List raw, String name) async {
  final animated = isAnimatedImageBytes(raw);
  if (animated || raw.length <= _scaleAboveBytes) {
    return RoomPicture(raw, _nameFor(raw, name, animated));
  }
  final codec = await ui.instantiateImageCodec(raw, targetWidth: 1280);
  final frame = await codec.getNextFrame();
  final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  frame.image.dispose();
  codec.dispose();
  final scaled = png!.buffer.asUint8List();
  // A PNG of a photo can outgrow the JPEG it came from.
  if (scaled.length > raw.length && raw.length <= _maxUploadBytes) {
    return RoomPicture(raw, _nameFor(raw, name, false));
  }
  return RoomPicture(scaled, 'room_picture.png');
}

/// GIF, or a WebP whose VP8X header has the animation flag.
bool isAnimatedImageBytes(Uint8List b) {
  if (b.length >= 6 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return true; // GIF8
  if (b.length >= 21 &&
      String.fromCharCodes(b.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(b.sublist(8, 12)) == 'WEBP' &&
      String.fromCharCodes(b.sublist(12, 16)) == 'VP8X') {
    return (b[20] & 0x02) != 0;
  }
  return false;
}

String _nameFor(Uint8List b, String name, bool animated) {
  if (!animated) return name.isNotEmpty ? name : 'room_picture.jpg';
  return b[0] == 0x47 ? 'room_picture.gif' : 'room_picture.webp';
}
