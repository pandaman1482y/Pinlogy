import 'package:shared_preferences/shared_preferences.dart';

class AiAnalysisConsent {
  static const _key = 'ai_post_analysis_consent_v1';

  Future<bool> hasConsented() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  Future<void> setConsented(bool value) async {
    await (await SharedPreferences.getInstance()).setBool(_key, value);
  }
}
