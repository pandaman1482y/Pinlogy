import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'share_receiver_service.dart';

/// OS横断の共有受信ブリッジ。
/// Android Intent / iOS Share Extension の両方から同じ MethodChannel で受け取る。
class PlatformShareBridge {
  PlatformShareBridge({
    this.channelName = 'com.pinlogy/share',
    MethodChannel? channel,
  }) : _channel = channel ?? MethodChannel(channelName);

  final String channelName;
  final MethodChannel _channel;

  bool _attached = false;

  /// 共有を受け取るたびに呼ばれる。
  Future<void> Function(SharedContent content)? onShared;

  Future<void> attach() async {
    if (_attached) return;
    _attached = true;

    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    _channel.setMethodCallHandler(_handleMethodCall);

    try {
      final initial = await _channel
          .invokeMethod<dynamic>('getInitialSharedMedia')
          .timeout(const Duration(seconds: 3));
      await _dispatch(initial);
    } on TimeoutException {
      // テストや未配線環境では応答がないことがある
    } catch (_) {
      // 未配線環境でもアプリ起動を止めない
    }
  }

  Future<void> detach() async {
    if (!_attached) return;
    _attached = false;
    _channel.setMethodCallHandler(null);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onShared':
        await _dispatch(call.arguments);
        return true;
      default:
        throw PlatformException(
          code: 'unsupported',
          message: '未対応のメソッド: ${call.method}',
        );
    }
  }

  Future<void> _dispatch(dynamic raw) async {
    if (raw is List) {
      for (final item in raw) {
        await _dispatch(item);
      }
      return;
    }
    final content = SharedContent.tryParse(raw);
    if (content == null || content.isEmpty) return;
    final handler = onShared;
    if (handler != null) {
      await handler(content);
    }
  }
}
