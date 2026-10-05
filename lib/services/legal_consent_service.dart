import 'package:shared_preferences/shared_preferences.dart';

/// 利用規約・プライバシーポリシーへの同意状態を端末に保持する。
/// 文書を重要変更した場合は [currentVersion] を更新し、再同意を求める。
class LegalConsentService {
  static const currentVersion = '2026-10-05';
  static const _acceptedVersionKey = 'legal_consent_accepted_version';
  static const _acceptedAtKey = 'legal_consent_accepted_at';

  Future<bool> hasAcceptedCurrentVersion() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_acceptedVersionKey) == currentVersion;
  }

  Future<void> acceptCurrentVersion() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_acceptedVersionKey, currentVersion);
    await preferences.setString(
      _acceptedAtKey,
      DateTime.now().toUtc().toIso8601String(),
    );
  }
}
