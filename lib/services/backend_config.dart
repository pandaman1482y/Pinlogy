/// バックエンド接続用の設定プレースホルダ。
/// 実際の値は環境変数やセキュアなビルド設定から注入する。
class BackendConfig {
  const BackendConfig({
    this.supabaseUrl,
    this.supabaseAnonKey,
    this.analysisEndpoint,
    this.geocodingEndpoint,
    this.placesEndpoint,
  });

  final String? supabaseUrl;
  final String? supabaseAnonKey;
  final String? analysisEndpoint;
  final String? geocodingEndpoint;
  final String? placesEndpoint;

  bool get isConfigured =>
      supabaseUrl != null &&
      supabaseUrl!.isNotEmpty &&
      supabaseAnonKey != null &&
      supabaseAnonKey!.isNotEmpty;

  /// 未設定時はローカルモック運用。
  static const unset = BackendConfig();
}

/// Supabase / 専用API 接続の将来実装用インターフェース。
abstract class BackendClient {
  Future<void> signInAnonymously();
  Future<void> syncAll();
}

class UnconfiguredBackendClient implements BackendClient {
  @override
  Future<void> signInAnonymously() async {
    throw UnsupportedError('Supabase が未設定です。.env.example を参照してください。');
  }

  @override
  Future<void> syncAll() async {
    throw UnsupportedError('同期はバックエンド設定後に有効になります。');
  }
}
