import 'package:flutter/widgets.dart';
import '../services/gift_animation_service.dart';
import '../widgets/mega_gift_layer.dart';

typedef GiftAnimationBuilder =
Widget Function(GiftAnimationData data, VoidCallback onFinish);

class GiftAnimationRegistry {

  static final Map<String, GiftAnimationBuilder> _registry = {

    "dragon_fly": (data, onFinish) =>
        MegaGiftLayer(data: data, onFinish: onFinish),

    "rocket_launch": (data, onFinish) =>
        MegaGiftLayer(data: data, onFinish: onFinish),

    "castle_explode": (data, onFinish) =>
        MegaGiftLayer(data: data, onFinish: onFinish),

  };

  static Widget? build(
      String? key,
      GiftAnimationData data,
      VoidCallback onFinish,
      ) {
    if (key == null) return null;

    final builder = _registry[key];

    if (builder == null) return null;

    return builder(data, onFinish);
  }
}