import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  bool get enabled => _enabled;
  bool get firebaseReady => _firebaseReady;

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
      if (_enabled) {
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      }
      debugPrint('pinlogy_notifications_ready enabled=$_enabled');
    } catch (error) {
      _firebaseReady = false;
      debugPrint('pinlogy_notifications_init_failed $error');
    }
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
    return true;
  }

  Future<String?> tokenForAnalysis() async {
    if (!_enabled || !_firebaseReady) return null;
    // iOSではAPNs tokenの登録より先にFCM tokenを要求すると失敗する。
    // 実機登録を少し待ってから再試行し、通知付きジョブにtokenを確実に載せる。
    for (var attempt = 0; attempt < 20; attempt++) {
      try {
        final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        if (apnsToken != null && apnsToken.isNotEmpty) {
          final token = await FirebaseMessaging.instance.getToken();
          if (token != null && token.isNotEmpty) {
            debugPrint('pinlogy_notification_token_ready');
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
}
