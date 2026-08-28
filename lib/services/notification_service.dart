import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// FCMの初期化と「解析完了通知」のユーザー設定を一か所で管理する。
/// GoogleService-Info.plist未配置の開発環境では静かに無効化する。
class PinlogyNotificationService {
  PinlogyNotificationService._();

  static final instance = PinlogyNotificationService._();
  static const _enabledKey = 'analysis_completion_notifications_v1';

  bool _firebaseReady = false;
  bool _enabled = false;

  bool get enabled => _enabled;
  bool get firebaseReady => _firebaseReady;

  Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    _enabled = preferences.getBool(_enabledKey) ?? false;
    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
      if (_enabled) {
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      }
    } catch (_) {
      _firebaseReady = false;
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
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }
}
