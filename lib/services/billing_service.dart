import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class BillingStatus {
  const BillingStatus({
    required this.plan,
    required this.remaining,
    required this.includedRemaining,
    required this.bonusCredits,
    this.expiresAt,
  });

  final String plan;
  final int remaining;
  final int includedRemaining;
  final int bonusCredits;
  final DateTime? expiresAt;
  bool get subscribed => plan == 'monthly' || plan == 'annual';

  factory BillingStatus.fromJson(Map<String, dynamic> json) => BillingStatus(
    plan: json['plan']?.toString() ?? 'free',
    remaining: int.tryParse('${json['remaining']}') ?? 0,
    includedRemaining: int.tryParse('${json['included_remaining']}') ?? 0,
    bonusCredits: int.tryParse('${json['bonus_credits']}') ?? 0,
    expiresAt: DateTime.tryParse(
      json['entitlement_expires_at']?.toString() ?? '',
    ),
  );
}

class BillingService extends ChangeNotifier {
  BillingService._();
  static final instance = BillingService._();

  static const _deviceIdKey = 'ai_quota_device_id_v1';
  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _iosKey = String.fromEnvironment('REVENUECAT_IOS_API_KEY');
  static const _androidKey = String.fromEnvironment(
    'REVENUECAT_ANDROID_API_KEY',
  );

  BillingStatus? status;
  Offering? offering;
  bool loading = false;
  bool configured = false;
  String? error;
  String? _accessToken;
  String? _revenueCatUserId;

  Future<void> initialize() async {
    if (configured) return;
    final key = Platform.isIOS
        ? _iosKey
        : Platform.isAndroid
        ? _androidKey
        : '';
    if (key.isEmpty) {
      error = 'RevenueCat APIキーが未設定です';
      await refreshStatus();
      return;
    }
    final configuration = PurchasesConfiguration(key)
      ..appUserID = await deviceId();
    if (kDebugMode) {
      await Purchases.setLogLevel(LogLevel.debug);
    }
    await Purchases.configure(configuration);
    configured = true;
    Purchases.addCustomerInfoUpdateListener((_) => refreshStatus());
    await refresh();
  }

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      if (configured) offering = (await Purchases.getOfferings()).current;
      await refreshStatus();
    } catch (e) {
      error = '購入情報を取得できませんでした';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refreshStatus() async {
    if (!_url.startsWith('https://') || _anonKey.isEmpty) return;
    try {
      final response = await http
          .post(
            Uri.parse(
              '${_url.replaceAll(RegExp(r'/$'), '')}/functions/v1/billing-status',
            ),
            headers: {
              'Authorization': 'Bearer ${_accessToken ?? _anonKey}',
              'apikey': _anonKey,
              'Content-Type': 'application/json',
              'X-Pinlogy-Device': await deviceId(),
            },
            body: '{}',
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        status = BillingStatus.fromJson(
          Map<String, dynamic>.from(jsonDecode(response.body) as Map),
        );
        notifyListeners();
      }
    } catch (_) {
      // 残回数表示の更新失敗で、解析済みレシピや購入処理を失敗扱いにしない。
    }
  }

  /// RevenueCatの購入者とSupabaseのログインユーザーを同じIDへ揃える。
  /// 未ログイン購入からログインした場合、RevenueCat側のaliasも引き継がれる。
  Future<void> syncAuthenticatedUser({
    String? userId,
    String? accessToken,
  }) async {
    _accessToken = accessToken?.isNotEmpty == true ? accessToken : null;
    if (configured && userId != null && userId.isNotEmpty) {
      if (_revenueCatUserId != userId) {
        await Purchases.logIn(userId);
        _revenueCatUserId = userId;
      }
    } else if (configured && userId == null && _revenueCatUserId != null) {
      await Purchases.logOut();
      await Purchases.logIn(await deviceId());
      _revenueCatUserId = null;
    }
    await refreshStatus();
  }

  Future<void> purchase(Package package) async {
    if (!configured) throw StateError('課金設定が完了していません');
    await Purchases.purchase(PurchaseParams.package(package));
    await _waitForWebhook();
  }

  Future<void> restore() async {
    if (!configured) throw StateError('課金設定が完了していません');
    await Purchases.restorePurchases();
    await _waitForWebhook();
  }

  Future<void> _waitForWebhook() async {
    for (var attempt = 0; attempt < 5; attempt++) {
      await Future<void>.delayed(Duration(seconds: attempt == 0 ? 1 : 2));
      await refreshStatus();
    }
  }

  Package? packageFor(String productId) => offering?.availablePackages
      .where((item) => item.storeProduct.identifier == productId)
      .firstOrNull;

  Future<String> deviceId() async {
    final preferences = await SharedPreferences.getInstance();
    final current = preferences.getString(_deviceIdKey);
    if (current != null && current.isNotEmpty) return current;
    final created = const Uuid().v4();
    await preferences.setString(_deviceIdKey, created);
    return created;
  }
}
