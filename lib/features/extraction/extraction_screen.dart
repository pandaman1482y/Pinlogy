import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/geocoding_privacy_consent.dart';
import '../../services/location_services.dart';
import '../../widgets/sheet_layout.dart';
import '../maps/maps_tab.dart';

class ExtractionScreen extends StatefulWidget {
  const ExtractionScreen({super.key, required this.sourcePostId});

  final String sourcePostId;

  @override
  State<ExtractionScreen> createState() => _ExtractionScreenState();
}

class _AnalysisSourceBanner extends StatelessWidget {
  const _AnalysisSourceBanner({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final isAi = source == 'ai' || source == 'ai_cache';
    final isFallback = source == 'local_fallback' || source == 'quota_fallback';
    final color = isFallback ? Colors.orange.shade50 : mintSoft;
    final icon = isAi ? Icons.auto_awesome_rounded : Icons.info_outline_rounded;
    final message = switch (source) {
      'ai' => 'AIで投稿内容と画像を解析しました',
      'ai_cache' => '保存済みのAI解析結果を再利用しました',
      'local_fallback' => 'AI通信に失敗したため、端末内の簡易解析結果を表示しています',
      'quota_fallback' => '本日のAI取り込み上限に達したため、端末内の簡易解析結果を表示しています',
      _ => '解析結果を表示しています。住所とピン位置を確認してください',
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 19,
              color: isFallback ? Colors.orange.shade900 : moss,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExtractionScreenState extends State<ExtractionScreen> {
  final selected = <String>{};
  final reviewed = <String>{};
  final resolved = <String, ExtractionCandidate>{};
  String? mapId;
  bool submitting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppScope.of(context);
    final candidates = controller.candidatesForPost(widget.sourcePostId);
    if (selected.isEmpty) {
      for (final c in candidates) {
        if (c.match != PlaceMatchConfidence.unresolved && !_requiresReview(c)) {
          selected.add(c.id);
        }
      }
    }
    mapId ??= controller.hub.snapshot.maps.isNotEmpty
        ? controller.hub.snapshot.maps.first.id
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final candidates = controller.candidatesForPost(widget.sourcePostId);
    final maps = controller.hub.snapshot.maps;
    final analysisSource = _analysisSource(controller);
    final identifiedCount = candidates
        .where(controller.isIdentifiedPlaceCandidate)
        .length;
    final resultMessage = identifiedCount > 0
        ? '$identifiedCount件の場所を特定しました。'
        : candidates.isNotEmpty
        ? '${candidates.length}件の候補がありますが、場所は未確定です。'
        : '場所を特定できませんでした。';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '場所を確認',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          TextButton(
            onPressed: () => setState(
              () => selected
                ..clear()
                ..addAll(candidates.map((c) => c.id)),
            ),
            child: const Text('全選択'),
          ),
          TextButton(
            onPressed: () => setState(selected.clear),
            child: const Text('解除'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: mint,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, color: moss),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '1. 候補を確認  2. 正しい支店を検索  3. マップへ追加\n'
                    '$resultMessage'
                    '住所が違う・不明な場合は検索してください。',
                    style: const TextStyle(
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _AnalysisSourceBanner(source: analysisSource),
          const SizedBox(height: 22),
          const Text(
            '追加する場所',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          if (candidates.isEmpty)
            const Text('候補がありません。解析結果を確認してください。')
          else
            ...candidates.map((c) {
              final needsReview = c.match != PlaceMatchConfidence.high;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: CheckboxListTile(
                    value: selected.contains(c.id),
                    onChanged: (value) => setState(() {
                      if (value == true) {
                        selected.add(c.id);
                      } else {
                        selected.remove(c.id);
                      }
                    }),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: const EdgeInsets.all(10),
                    title: Text(
                      c.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text((resolved[c.id] ?? c).address ?? '住所未確定'),
                          const SizedBox(height: 6),
                          Text(
                            c.match.label,
                            style: TextStyle(
                              color: needsReview
                                  ? Colors.orange.shade800
                                  : moss,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (c.evidenceSummary != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              c.evidenceSummary!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                          if (_requiresReview(c)) ...[
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: () => _resolveWithSearch(context, c),
                              icon: const Icon(Icons.manage_search_rounded),
                              label: const Text('店名・住所で正しい場所を検索'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          const SizedBox(height: 8),
          const Text(
            '保存先マップ',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: mapId,
            items: [
              ...maps.map(
                (m) => DropdownMenuItem(
                  value: m.id,
                  child: Text('${m.icon}  ${m.name}'),
                ),
              ),
            ],
            onChanged: (value) => setState(() => mapId = value),
          ),
        ],
      ),
      bottomSheet: SafeArea(
        child: Container(
          color: canvas,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          width: double.infinity,
          child: FilledButton.icon(
            onPressed:
                selected.isEmpty ||
                    mapId == null ||
                    submitting ||
                    _hasUnreviewed(candidates)
                ? null
                : () => _submit(context),
            icon: submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_location_alt_outlined),
            label: Text(
              _hasUnreviewed(candidates)
                  ? 'オレンジの候補を確認してください'
                  : '選択した${selected.length}件を追加',
            ),
          ),
        ),
      ),
    );
  }

  String _analysisSource(dynamic controller) {
    final job = controller.jobForPost(widget.sourcePostId);
    final raw = job?.resultJson;
    if (raw == null || raw.isEmpty) return 'unknown';
    try {
      final value = jsonDecode(raw) as Map<String, dynamic>;
      return value['analysis_source'] as String? ?? 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  Future<void> _submit(BuildContext context) async {
    final controller = AppScope.read(context);
    final candidates = controller
        .candidatesForPost(widget.sourcePostId)
        .where((c) => selected.contains(c.id))
        .map((c) => resolved[c.id] ?? c)
        .toList();
    var resolveAddresses = false;
    if (candidates.any(
      (c) =>
          c.address?.isNotEmpty == true &&
          (c.latitude == null || c.longitude == null),
    )) {
      final consent = GeocodingPrivacyConsent();
      resolveAddresses = await consent.hasConsented();
      if (!resolveAddresses && context.mounted) {
        resolveAddresses =
            await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                icon: const Icon(Icons.location_searching_outlined),
                title: const Text('住所からピンを置く'),
                content: const Text(
                  '選択した住所を座標へ変換するため、住所文字列を国土地理院・OpenStreetMapの検索サービスへ送信します。'
                  '投稿画像や投稿文全体は送信しません。送信せずに住所だけ保存することもできます。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('住所だけ保存'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('同意してピンを置く'),
                  ),
                ],
              ),
            ) ??
            false;
        if (resolveAddresses) await consent.grant();
      }
    }
    if (!mounted) return;
    setState(() => submitting = true);
    try {
      final existingIds = controller.hub.snapshot.places
          .map((place) => place.id)
          .toSet();
      final addedPlaces = await controller.addCandidatesToMap(
        candidates: candidates,
        mapId: mapId!,
        sourcePostId: widget.sourcePostId,
        resolveAddresses: resolveAddresses,
      );
      if (context.mounted) {
        final mapName = controller.hub.snapshot.maps
            .firstWhere((m) => m.id == mapId)
            .name;
        final duplicateCount = addedPlaces
            .where((place) => existingIds.contains(place.id))
            .length;
        final navigator = Navigator.of(context);
        final messenger = ScaffoldMessenger.of(context);
        navigator.pop();
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 5),
            content: Text(
              duplicateCount == 0
                  ? '${addedPlaces.length}件を「$mapName」に保存しました'
                  : '${addedPlaces.length}件を「$mapName」に保存しました（$duplicateCount件は登録済みの場所に追加）',
            ),
            action: SnackBarAction(
              label: '地図で見る',
              onPressed: () => navigator.push(
                MaterialPageRoute(builder: (_) => MapScreen(mapId: mapId!)),
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  bool _hasUnreviewed(List<ExtractionCandidate> candidates) => candidates.any(
    (c) =>
        selected.contains(c.id) &&
        _requiresReview(c) &&
        !reviewed.contains(c.id),
  );

  bool _requiresReview(ExtractionCandidate candidate) =>
      candidate.hasAddressMismatch ||
      candidate.address?.isNotEmpty != true ||
      (candidate.confidencePercent ?? 0) < 60;

  Future<void> _resolveWithSearch(
    BuildContext context,
    ExtractionCandidate candidate,
  ) async {
    final result = await _searchCandidate(context, candidate);
    if (result == null || !mounted) return;
    setState(() {
      resolved[candidate.id] = result;
      reviewed.add(candidate.id);
      selected.add(candidate.id);
    });
  }

  Future<ExtractionCandidate?> _searchCandidate(
    BuildContext context,
    ExtractionCandidate candidate,
  ) async {
    final queryController = TextEditingController(
      text: candidate.name == '名称を確認してください'
          ? candidate.postAddress ?? candidate.address ?? ''
          : [candidate.name, candidate.postAddress ?? candidate.address]
                .whereType<String>()
                .where((value) => value.trim().isNotEmpty)
                .join(' '),
    );
    try {
      final query = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.location_searching_rounded),
          title: const Text('正しい場所を検索'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('TikTokの画面に表示された店名、または住所を入力してください。'),
              const SizedBox(height: 12),
              TextField(
                controller: queryController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  labelText: '店名・住所',
                  hintText: '例：喫茶ソワレ 京都',
                ),
                onSubmitted: (value) =>
                    Navigator.pop(dialogContext, value.trim()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, queryController.text.trim()),
              child: const Text('検索'),
            ),
          ],
        ),
      );
      if (query == null || query.isEmpty || !context.mounted) return null;
      final hits = await AppScope.read(context).placeSearch.searchByName(
        query,
        nearAddress: candidate.postAddress ?? candidate.address,
      );
      if (!context.mounted) return null;
      if (hits.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('場所が見つかりませんでした。住所を追加して再検索してください。')),
        );
        return null;
      }
      final hit = await showModalBottomSheet<PlaceSearchHit>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 20),
            children: [
              const ListTile(
                title: Text(
                  '追加する場所を選択',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text('店名と住所を確認してください'),
              ),
              ...hits.map(
                (hit) => ListTile(
                  leading: const Icon(Icons.place_outlined),
                  title: Text(hit.name),
                  subtitle: Text(hit.address ?? '住所情報なし'),
                  onTap: () => Navigator.pop(sheetContext, hit),
                ),
              ),
            ],
          ),
        ),
      );
      if (hit == null) return null;
      return ExtractionCandidate(
        id: candidate.id,
        name: hit.name,
        address: hit.address,
        reason: candidate.reason,
        evidenceSummary: 'ユーザーが店名・住所検索から確認',
        confidencePercent: 100,
        match: PlaceMatchConfidence.high,
        postAddress: candidate.postAddress,
        searchCandidateName: hit.name,
        searchCandidateAddress: hit.address,
        latitude: hit.latitude,
        longitude: hit.longitude,
      );
    } finally {
      // ダイアログの退場アニメーション後に安全に破棄する。
      disposeAfterFrame([queryController]);
    }
  }

  // ignore: unused_element
  Future<ExtractionCandidate?> _showMismatch(
    BuildContext context,
    ExtractionCandidate candidate,
  ) async {
    var choice = 1;
    return showModalBottomSheet<ExtractionCandidate>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                '住所を確認してください',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text('投稿住所と店名検索の結果が異なる可能性があります。'),
              const SizedBox(height: 12),
              if (candidate.evidenceSummary != null)
                Text(
                  candidate.evidenceSummary!,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              const SizedBox(height: 18),
              RadioListTile<int>(
                value: 1,
                // ignore: deprecated_member_use
                groupValue: choice,
                // ignore: deprecated_member_use
                onChanged: (v) => setModalState(() => choice = v ?? 1),
                title: const Text('投稿に書かれた住所へピンを置く'),
                subtitle: Text(
                  candidate.postAddress ?? candidate.address ?? '',
                ),
              ),
              RadioListTile<int>(
                value: 2,
                // ignore: deprecated_member_use
                groupValue: choice,
                // ignore: deprecated_member_use
                onChanged: (v) => setModalState(() => choice = v ?? 2),
                title: const Text('店名検索で見つかった場所を使用する'),
                subtitle: Text(
                  '${candidate.searchCandidateName ?? ''}\n${candidate.searchCandidateAddress ?? ''}',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit_location_alt_outlined),
                title: const Text('地図上で位置を選ぶ'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('地図ピン選択は実地図接続後に有効になります')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.bookmark_border),
                title: const Text('場所を特定せず投稿だけ保存する'),
                onTap: () => Navigator.pop(context),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    final useSearch =
                        choice == 2 &&
                        candidate.searchCandidateAddress?.isNotEmpty == true;
                    Navigator.pop(
                      context,
                      ExtractionCandidate(
                        id: candidate.id,
                        name:
                            useSearch &&
                                candidate.searchCandidateName?.isNotEmpty ==
                                    true
                            ? candidate.searchCandidateName!
                            : candidate.name,
                        address: useSearch
                            ? candidate.searchCandidateAddress
                            : (candidate.postAddress ?? candidate.address),
                        postAddress: candidate.postAddress,
                        reason: candidate.reason,
                        evidenceSummary: candidate.evidenceSummary,
                        confidencePercent: candidate.confidencePercent,
                        match: PlaceMatchConfidence.high,
                        latitude: candidate.latitude,
                        longitude: candidate.longitude,
                        mapPinX: candidate.mapPinX,
                        mapPinY: candidate.mapPinY,
                        openingTimeMinutes: candidate.openingTimeMinutes,
                        closingTimeMinutes: candidate.closingTimeMinutes,
                        closedWeekdays: candidate.closedWeekdays,
                      ),
                    );
                  },
                  child: const Text('この選択を使う'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
