import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/services/platform_share_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.pinlogy/share-test');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('処理できた共有IDだけをネイティブへ確認済みとして返す', () async {
    Object? acknowledged;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getInitialSharedMedia') {
            return [
              {
                'sourcePostId': 'post-a',
                'url': 'https://www.instagram.com/p/ShareTest01/',
              },
              {
                'sourcePostId': 'post-b',
                'url': 'https://www.instagram.com/p/ShareTest02/',
              },
            ];
          }
          if (call.method == 'acknowledgeSharedMedia') {
            acknowledged = call.arguments;
            return true;
          }
          return null;
        });

    final received = <String>[];
    final bridge =
        PlatformShareBridge(
            channelName: 'com.pinlogy/share-test',
            channel: channel,
          )
          ..onShared = (content) async {
            received.add(content.sourcePostId!);
          };

    await bridge.attach();

    expect(received, ['post-a', 'post-b']);
    expect(acknowledged, ['post-a', 'post-b']);
    await bridge.detach();
  });

  test('共有処理が失敗した場合はキューを確認済みにしない', () async {
    var acknowledged = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getInitialSharedMedia') {
            return {
              'sourcePostId': 'post-failed',
              'url': 'https://www.instagram.com/p/ShareFail01/',
            };
          }
          if (call.method == 'acknowledgeSharedMedia') acknowledged = true;
          return null;
        });

    final bridge = PlatformShareBridge(
      channelName: 'com.pinlogy/share-test',
      channel: channel,
    )..onShared = (_) async => throw StateError('保存失敗');

    await bridge.attach();

    expect(acknowledged, isFalse);
    await bridge.detach();
  });
}
