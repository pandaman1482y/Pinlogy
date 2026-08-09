import 'package:shared_preferences/shared_preferences.dart';

class GeocodingPrivacyConsent {
  static const _key = 'address_geocoding_consent_v1';

  Future<bool> hasConsented() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  Future<void> grant() async =>
      (await SharedPreferences.getInstance()).setBool(_key, true);
}
