import 'package:shared_preferences/shared_preferences.dart';

class RoutePrivacyConsent {
  static const _key = 'route_coordinate_sharing_consent_v1';

  Future<bool> hasConsented() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  Future<void> grant() async =>
      (await SharedPreferences.getInstance()).setBool(_key, true);
}
