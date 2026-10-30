import 'dart:typed_data';
import 'dart:ui' as ui;

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
/// it is; only a still picture over the 5 MB upload cap is scaled down.
Future<RoomPicture?> pickRoomPicture() async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (picked == null) return null;
  return roomPictureFrom(await picked.readAsBytes(), picked.name);
}

const _maxUploadBytes = 4 * 1024 * 1024;

Future<RoomPicture> roomPictureFrom(Uint8List raw, String name) async {
  final animated = isAnimatedImageBytes(raw);
  if (animated || raw.length <= _maxUploadBytes) {
    return RoomPicture(raw, _nameFor(raw, name, animated));
  }
  final codec = await ui.instantiateImageCodec(raw, targetWidth: 1600);
  final frame = await codec.getNextFrame();
  final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  frame.image.dispose();
  codec.dispose();
  return RoomPicture(png!.buffer.asUint8List(), 'room_picture.png');
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
