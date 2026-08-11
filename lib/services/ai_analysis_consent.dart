import 'package:shared_preferences/shared_preferences.dart';

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
  }
}
