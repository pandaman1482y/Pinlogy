import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/ai_analysis_consent.dart';

const _onboardingKey = 'pinlogy_onboarding_v1_completed';

Future<void> showOnboardingIfNeeded(BuildContext context) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_onboardingKey) == true || !context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _OnboardingSheet(),
    );
    await prefs.setBool(_onboardingKey, true);
  } catch (_) {
    // チュートリアルの保存失敗でアプリ本体の起動を妨げない。
  }
}

/// マイページからいつでも読み返せる詳しい使い方。
class PinlogyHowToPage extends StatelessWidget {
  const PinlogyHowToPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('使い方・チュートリアル')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
      children: const [
        _HowToCard(
          number: '1',
          icon: Icons.ios_share_rounded,
          title: 'SNSの投稿を共有',
          body:
              'TikTokやInstagramの共有先でPinlogyを選びます。投稿文、共有画像、動画サムネイルから店名や住所のヒントを探します。',
        ),
        _HowToCard(
          number: '2',
          icon: Icons.fact_check_outlined,
          title: '候補を確認して保存',
          body:
              '1つの投稿に複数のお店がある場合は、見つかった候補から追加したいお店を選べます。候補はまとめて解析するため、1店ずつ解析し直す必要はありません。',
        ),
        _HowToCard(
          number: '3',
          icon: Icons.add_photo_alternate_outlined,
          title: '見つからないときはスクショ追加',
          body:
              '「手動で追加」→「AIでスクショから追加」から、関連するスクリーンショットを最大10枚選べます。画像内の文字も読み取ります。',
        ),
        _HowToCard(
          number: '4',
          icon: Icons.filter_7_rounded,
          title: '10枚中7枚目のお店を追加したい場合',
          body:
              '追加したいお店が写っている7枚目をスクリーンショットして選んでください。「7枚目のお店」などの短いヒントを添えると、ほかの候補と区別しやすくなります。画像番号の入力は必須ではありません。',
        ),
        _HowToCard(
          number: '5',
          icon: Icons.video_camera_back_outlined,
          title: '動画の途中にだけヒントがある場合',
          body:
              '共有だけでは動画の全場面を取得できない場合があります。店名、住所、メニューが表示された場面をスクリーンショットして追加してください。',
        ),
        _HowToCard(
          number: '6',
          icon: Icons.map_outlined,
          title: 'マップと旅行プランで活用',
          body: '保存した場所はマップで確認でき、旅行プランの立ち寄り先にも使えます。移動手段や所要時間も区間ごとに編集できます。',
        ),
      ],
    ),
  );
}

class _HowToCard extends StatelessWidget {
  const _HowToCard({
    required this.number,
    required this.icon,
    required this.title,
    required this.body,
  });

  final String number;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, size: 22),
                Align(
                  alignment: Alignment.bottomRight,
                  child: CircleAvatar(
                    radius: 8,
                    child: Text(number, style: const TextStyle(fontSize: 9)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(body, style: const TextStyle(height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// 投稿内容をクラウドAIへ送る前に、一度だけ明示的な選択を求める。
/// 選択後は設定画面で変更でき、起動のたびには表示しない。
Future<bool> showAiAnalysisConsentIfNeeded(BuildContext context) async {
  final consent = AiAnalysisConsent();
  if (await consent.hasMadeChoice()) return consent.hasConsented();
  if (!context.mounted) return false;

  final enabled = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.auto_awesome_outlined),
      title: const Text('AIで場所を見つけやすく'),
      content: const Text(
        '共有した投稿文、取り込みメモ、共有画像・動画サムネイルをAIで解析して、店名や住所の候補を高精度に探します。\n\n'
        'これらはSupabase経由でOpenAIへ送信されます。保存済みの位置情報や場所の個人メモは送りません。設定からいつでもOFFにできます。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('端末内のみで使う'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(dialogContext, true),
          icon: const Icon(Icons.auto_awesome_rounded),
          label: const Text('AI解析を使う'),
        ),
      ],
    ),
  );
  final selected = enabled ?? false;
  await consent.setConsented(selected);
  return selected;
}

class _OnboardingSheet extends StatefulWidget {
  const _OnboardingSheet();
  @override
  State<_OnboardingSheet> createState() => _OnboardingSheetState();
}

class _OnboardingSheetState extends State<_OnboardingSheet> {
  int page = 0;
  static const items = [
    (
      Icons.ios_share_rounded,
      '投稿をPinlogyへ共有',
      'InstagramやTikTokの共有先でPinlogyを選びます。',
    ),
    (
      Icons.document_scanner_outlined,
      '候補を確認',
      '投稿文と画像内の文字から店名・住所を探します。複数ある場合は選べます。',
    ),
    (
      Icons.add_photo_alternate_outlined,
      '足りない場面はスクショで',
      'SNSから取得できない画像や動画の途中に店名が出る場合は、対象の場面をスクショして最大10枚まで追加できます。',
    ),
    (Icons.map_outlined, '自分の地図に保存', '場所を選んで保存。あとから経路、旅行プラン、共有に使えます。'),
  ];

  @override
  Widget build(BuildContext context) {
    final item = items[page];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F1EC),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Icon(item.$1, size: 38),
            ),
            const SizedBox(height: 22),
            Text(
              item.$2,
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              item.$3,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(height: 1.55),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                items.length,
                (index) => Container(
                  width: index == page ? 22 : 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: index == page
                        ? const Color(0xFF244C3B)
                        : const Color(0xFFD8E0DC),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => page == items.length - 1
                    ? Navigator.pop(context)
                    : setState(() => page++),
                child: Text(page == items.length - 1 ? 'はじめる' : '次へ'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
