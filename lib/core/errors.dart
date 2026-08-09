/// ユーザー向けの日本語エラーメッセージへ変換する。
String toUserMessage(Object error) {
  final text = error.toString();
  final stateMessage = error is StateError ? error.message.trim() : null;
  final probe = [
    if (stateMessage != null && stateMessage.isNotEmpty) stateMessage,
    if (text.startsWith('Bad state: '))
      text.substring('Bad state: '.length).trim(),
    text,
  ].join(' ');

  if (probe.contains('SocketException') ||
      probe.contains('Failed host lookup')) {
    return 'ネットワークに接続できません。接続を確認して再試行してください。';
  }
  if (probe.contains('TimeoutException')) {
    return '応答がタイムアウトしました。しばらくしてから再試行してください。';
  }
  if (probe.contains('FormatException')) {
    return 'データの形式が正しくありません。';
  }
  if (probe.contains('Permission denied') ||
      probe.contains('MissingPluginException')) {
    return 'この機能を使う準備ができていません。アプリを再起動して試してください。';
  }
  if (probe.contains('anonymous_provider_disabled') ||
      probe.contains('Anonymous sign-ins are disabled')) {
    return 'クラウド同期を使うには「アカウントを設定」から新規登録またはログインしてください。端末内のデータは消えていません。';
  }
  if (probe.contains('invalid_credentials') ||
      probe.contains('Invalid login credentials')) {
    return 'メールアドレスまたはパスワードが正しくありません。パスワードが分からない場合は「パスワードを忘れた場合」から再設定してください。';
  }
  if (probe.contains('email_not_confirmed') ||
      probe.contains('Email not confirmed')) {
    return 'メール認証が完了していません。確認メールの最新リンクを開いてから、もう一度ログインしてください。';
  }
  if (probe.contains('over_email_send_rate_limit') ||
      probe.contains('email rate limit') ||
      probe.contains('rate limit')) {
    return 'メール送信の回数制限中です。しばらく待ってから再試行してください。';
  }
  if (probe.contains('user_already_exists') ||
      probe.contains('User already registered')) {
    return 'このメールアドレスは登録済みです。「ログイン」を使用してください。';
  }

  if (stateMessage != null && stateMessage.isNotEmpty) {
    return stateMessage;
  }
  if (text.startsWith('Bad state: ')) {
    final message = text.substring('Bad state: '.length).trim();
    if (message.isNotEmpty) return message;
  }
  return '処理に失敗しました。もう一度お試しください。';
}
