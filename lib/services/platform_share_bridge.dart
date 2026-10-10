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

  Future<void> configureBackgroundIntake({
    required String supabaseUrl,
    required String supabaseAnonKey,
    String? supabaseAccessToken,
    bool? notificationEnabled,
    String? notificationToken,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('configureBackgroundIntake', {
        'supabaseUrl': supabaseUrl,
        'supabaseAnonKey': supabaseAnonKey,
        'supabaseAccessToken': supabaseAccessToken ?? '',
        if (notificationEnabled != null)
          'notificationEnabled': notificationEnabled,
        if (notificationToken != null && notificationToken.isNotEmpty)
          'notificationToken': notificationToken,
      });
    } catch (_) {
      // 事前設定に失敗しても通常の本体取り込みは継続する。
    }
  }

  Future<void> attach() async {
    if (_attached) return;
    _attached = true;

    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    _channel.setMethodCallHandler(_handleMethodCall);
    await pullPendingShares();
  }

  /// Share Extensionがバックグラウンド中に保存したキューを取り込む。
  /// 初回起動だけでなく、アプリがforegroundへ戻るたびに呼び出す。
  Future<void> pullPendingShares() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      final initial = await _channel
          .invokeMethod<dynamic>('getInitialSharedMedia')
          .timeout(const Duration(seconds: 3));
      final processedIds = await _dispatch(initial);
      if (processedIds.isNotEmpty) {
        await _channel.invokeMethod<bool>(
          'acknowledgeSharedMedia',
          processedIds,
        );
      }
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
        return _dispatch(call.arguments);
      default:
        throw PlatformException(
          code: 'unsupported',
          message: '未対応のメソッド: ${call.method}',
        );
    }
  }

  Future<List<String>> _dispatch(dynamic raw) async {
    if (raw is List) {
      final processedIds = <String>[];
      for (final item in raw) {
        processedIds.addAll(await _dispatch(item));
      }
      return processedIds;
    }
    final content = SharedContent.tryParse(raw);
    if (content == null || content.isEmpty) return const [];
    final handler = onShared;
    if (handler != null) {
      await handler(content);
      final sourcePostId = content.sourcePostId?.trim();
      return sourcePostId == null || sourcePostId.isEmpty
          ? const []
          : [sourcePostId];
    }
    return const [];
  }
}
