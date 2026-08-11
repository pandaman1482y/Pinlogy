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
        '共有した投稿文と、端末で読み取った文字をAIで解析して、店名や住所の候補を高精度に探します。\n\n'
        '画像ファイル、個人メモ、保存済みの位置情報はAIへ送りません。設定からいつでもOFFにできます。',
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
