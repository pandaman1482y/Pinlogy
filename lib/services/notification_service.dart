import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

/// FCMの初期化と「解析完了通知」のユーザー設定を一か所で管理する。
/// GoogleService-Info.plist未配置の開発環境では静かに無効化する。
class PinlogyNotificationService {
  PinlogyNotificationService._();

  static final instance = PinlogyNotificationService._();
  // v2は解析完了通知を初期ONにする。ユーザーが設定画面でOFFにした後は
  // 保存済みのv2設定を優先し、次回起動時にもOFFを維持する。
  static const _enabledKey = 'analysis_completion_notifications_v2';

  bool _firebaseReady = false;
  bool _enabled = true;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  final _completionController = StreamController<String?>.broadcast();
  String? _initialCompletionSourcePostId;
  static const _shareChannel = MethodChannel('com.pinlogy/share');
  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _key = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _deviceIdKey = 'ai_quota_device_id_v1';

  bool get enabled => _enabled;
  bool get firebaseReady => _firebaseReady;
  Stream<String?> get completionSourcePostIds => _completionController.stream;

  String? consumeInitialCompletionSourcePostId() {
    final value = _initialCompletionSourcePostId;
    _initialCompletionSourcePostId = null;
    return value;
  }

  Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    _enabled = preferences.getBool(_enabledKey) ?? true;
    try {
      await Firebase.initializeApp();
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          );
      _firebaseReady = true;
      _tokenSubscription?.cancel();
      _tokenSubscription = FirebaseMessaging.instance.onTokenRefresh.listen(
        (token) => unawaited(_publishShareSettings(token: token)),
      );
      _openedSubscription?.cancel();
      _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        _handleOpenedMessage,
      );
      final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null &&
          initialMessage.data['type'] == 'analysis_completed') {
        _initialCompletionSourcePostId =
            initialMessage.data['source_post_id']?.toString();
      }
      if (_enabled) {
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      }
      debugPrint('pinlogy_notifications_ready enabled=$_enabled');
      unawaited(_publishShareSettings());
      if (_enabled) unawaited(tokenForAnalysis());
    } catch (error) {
      _firebaseReady = false;
      debugPrint('pinlogy_notifications_init_failed $error');
    }
  }

  void _handleOpenedMessage(RemoteMessage message) {
    if (message.data['type'] != 'analysis_completed') return;
    final sourcePostId = message.data['source_post_id']?.toString();
    _completionController.add(
      sourcePostId == null || sourcePostId.isEmpty ? null : sourcePostId,
    );
  }

  Future<bool> setEnabled(bool value) async {
    if (value && !_firebaseReady) return false;
    if (value) {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return false;
      }
    }
    _enabled = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey, value);
    await _publishShareSettings();
    return true;
  }

  Future<String?> tokenForAnalysis() async {
    if (!_enabled || !_firebaseReady) return null;
    // iOSではAPNs tokenの登録より先にFCM tokenを要求すると失敗する。
    // 実機登録を少し待ってから再試行し、通知付きジョブにtokenを確実に載せる。
    for (var attempt = 0; attempt < 20; attempt++) {
      try {
        final apnsReady = defaultTargetPlatform != TargetPlatform.iOS ||
            ((await FirebaseMessaging.instance.getAPNSToken())?.isNotEmpty ??
                false);
        if (apnsReady) {
          final token = await FirebaseMessaging.instance.getToken();
          if (token != null && token.isNotEmpty) {
            debugPrint('pinlogy_notification_token_ready');
            await _publishShareSettings(token: token);
            return token;
          }
        }
      } catch (_) {
        // APNs登録直後は一時的に失敗するため次の試行へ進む。
      }
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }
    debugPrint('pinlogy_notification_token_unavailable');
    return null;
  }

  Future<NotificationDiagnostics> diagnostics() async {
    if (!_firebaseReady) {
      return const NotificationDiagnostics(
        firebaseReady: false,
        permission: '未接続',
        tokenReady: false,
      );
    }
    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      final token = await FirebaseMessaging.instance.getToken();
      final apnsReady = defaultTargetPlatform != TargetPlatform.iOS ||
          ((await FirebaseMessaging.instance.getAPNSToken())?.isNotEmpty ??
              false);
      final authorization = settings.authorizationStatus;
      final permission = authorization == AuthorizationStatus.authorized
          ? '許可済み'
          : authorization == AuthorizationStatus.provisional
          ? '仮許可'
          : authorization == AuthorizationStatus.denied
          ? '拒否'
          : '未選択';
      return NotificationDiagnostics(
        firebaseReady: true,
        permission: permission,
        tokenReady: token?.isNotEmpty == true && apnsReady,
      );
    } catch (_) {
      return const NotificationDiagnostics(
        firebaseReady: true,
        permission: '確認できません',
        tokenReady: false,
      );
    }
  }

  Future<bool> sendTestNotification() async {
    final token = await tokenForAnalysis();
    if (token == null || !_url.startsWith('https://') || _key.isEmpty) {
      return false;
    }
    final preferences = await SharedPreferences.getInstance();
    var deviceId = preferences.getString(_deviceIdKey);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await preferences.setString(_deviceIdKey, deviceId);
    }
    try {
      final response = await http
          .post(
            Uri.parse(
              '${_url.replaceAll(RegExp(r'/$'), '')}/functions/v1/enqueue-analysis',
            ),
            headers: {
              'Authorization': 'Bearer $_key',
              'apikey': _key,
              'Content-Type': 'application/json',
              'X-Pinlogy-Device': deviceId,
            },
            body: jsonEncode({
              'action': 'test_notification',
              'notification_token': token,
            }),
          )
          .timeout(const Duration(seconds: 20));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> _publishShareSettings({String? token}) async {
    try {
      await _shareChannel.invokeMethod<void>('configureBackgroundIntake', {
        'notificationEnabled': _enabled,
        if (token != null && token.isNotEmpty) 'notificationToken': token,
      });
    } catch (_) {
      // iOS以外や起動直後にチャネルが未準備でも通常通知は継続する。
    }
  }
}

class NotificationDiagnostics {
  const NotificationDiagnostics({
    required this.firebaseReady,
    required this.permission,
    required this.tokenReady,
  });

  final bool firebaseReady;
  final String permission;
  final bool tokenReady;
}
