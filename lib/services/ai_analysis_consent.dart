import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AiAnalysisConsent {
  static const _key = 'ai_post_analysis_consent_v1';
  static const _decisionKey = 'ai_post_analysis_consent_decided_v1';

  Future<bool> hasConsented() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  /// 初回説明でON/OFFのどちらかを選択済みか。
  /// OFFを選んだ利用者へ起動のたびに確認を繰り返さないため、同意値とは分けて保存する。
  Future<bool> hasMadeChoice() async =>
      (await SharedPreferences.getInstance()).getBool(_decisionKey) ?? false;

  Future<void> setConsented(bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_key, value);
    await preferences.setBool(_decisionKey, true);
    await syncShareExtension();
  }

  Future<void> syncShareExtension() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    final enabled = await hasConsented();
    final saved = await const MethodChannel('com.pinlogy/share')
        .invokeMethod<bool>('configureBackgroundIntake', {
          'aiAnalysisEnabled': enabled,
        });
    if (saved != true)
      throw StateError('共有機能のAI解析設定を保存できませんでした。アプリを再起動して設定を確認してください。');
  }
}
