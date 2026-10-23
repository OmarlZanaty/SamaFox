import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:samafox/services/device_tier.dart';
import 'package:samafox/services/gpu_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late bool previousLite;
  late bool previousUltraLite;
  late List<MethodCall> calls;

  setUp(() {
    previousLite = DeviceTier.lite;
    previousUltraLite = DeviceTier.ultraLite;
    DeviceTier.lite = false;
    DeviceTier.ultraLite = false;
    calls = [];
    messenger.setMockMethodCallHandler(SystemChannels.skia, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    DeviceTier.lite = previousLite;
    DeviceTier.ultraLite = previousUltraLite;
    messenger.setMockMethodCallHandler(SystemChannels.skia, null);
  });

  test('apply sends the budget for each device tier', () async {
    expect(GpuCache.budgetBytes, 128 << 20);
    await GpuCache.apply();
    DeviceTier.lite = true;
    expect(GpuCache.budgetBytes, 64 << 20);
    await GpuCache.apply();
    DeviceTier.ultraLite = true;
    expect(GpuCache.budgetBytes, 48 << 20);
    await GpuCache.apply();

    expect(calls.map((call) => call.method),
        everyElement('Skia.setResourceCacheMaxBytes'));
    expect(
        calls.map((call) => call.arguments), [128 << 20, 64 << 20, 48 << 20]);
  });

  test('purge lowers and restores the budget and ignores overlap', () async {
    final first = GpuCache.purge();
    await GpuCache.purge();
    expect(calls.map((call) => call.arguments), [8 << 20]);
    await first;
    expect(
        calls.map((call) => call.arguments), [8 << 20, GpuCache.budgetBytes]);

    await GpuCache.purge();
    expect(calls.map((call) => call.arguments),
        [8 << 20, GpuCache.budgetBytes, 8 << 20, GpuCache.budgetBytes]);
    expect(calls.map((call) => call.method),
        everyElement('Skia.setResourceCacheMaxBytes'));
  });

  test('apply and purge complete with no Skia handler', () async {
    messenger.setMockMethodCallHandler(SystemChannels.skia, null);
    await expectLater(GpuCache.apply(), completes);
    await expectLater(GpuCache.purge(), completes);
  });

  test('channel errors are swallowed and restoration is still attempted',
      () async {
    messenger.setMockMethodCallHandler(SystemChannels.skia, (call) async {
      calls.add(call);
      throw PlatformException(code: 'unsupported');
    });
    await expectLater(GpuCache.apply(), completes);
    await expectLater(GpuCache.purge(), completes);
    expect(calls.map((call) => call.arguments),
        [GpuCache.budgetBytes, 8 << 20, GpuCache.budgetBytes]);

    calls.clear();
    messenger.setMockMethodCallHandler(SystemChannels.skia, (call) async {
      calls.add(call);
      throw MissingPluginException();
    });
    await expectLater(GpuCache.purge(), completes);
    expect(
        calls.map((call) => call.arguments), [8 << 20, GpuCache.budgetBytes]);
  });
}
