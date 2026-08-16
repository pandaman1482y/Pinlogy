import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/app_scope.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/location_services.dart';
import '../../services/share_receiver_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/feedback.dart';
import '../../widgets/ios_mapkit_view.dart';
import '../../widgets/place_map_view.dart';
import '../../widgets/sheet_layout.dart';
import '../../widgets/source_post_tile.dart';
import '../places/place_details_sheet.dart';
import '../onboarding/onboarding_sheet.dart';
import '../plans/plan_detail_page.dart';

class MapsTab extends StatelessWidget {
  const MapsTab({super.key});

  static bool _createMapSheetOpen = false;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final useSingleColumn = width < 420 || textScale > 1.3;
    final cardHeight = (190 + ((textScale - 1).clamp(0, 1) * 105)).toDouble();
    final maps = controller.hub.snapshot.maps.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final recentPlaces = controller.hub.snapshot.places.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return Column(
      children: [
        PageHeading(
          'Pinlogy',
          'SNSで見つけた場所を、自分の地図に。',
          action: SoftIconButton(
            onPressed: () => _showCreateMap(context),
            icon: Icons.add_rounded,
            tooltip: 'マップを追加',
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: QuietSearchField(
            readOnly: true,
            hintText: '場所やマップを探す',
            onTap: () => _openCrossSearch(context),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: useSingleColumn
              ? Column(
                  children: [
                    _AddMethodCard(
                      icon: Icons.ios_share_rounded,
                      title: 'SNSから追加',
                      subtitle: '投稿を共有するだけ',
                      onTap: () => _showShareGuide(context),
                    ),
                    const SizedBox(height: 10),
                    _AddMethodCard(
                      icon: Icons.add_location_alt_outlined,
                      title: '手動で追加',
                      subtitle: '店名・住所から検索',
                      onTap: () => _showManualAdd(context),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: _AddMethodCard(
                        icon: Icons.ios_share_rounded,
                        title: 'SNSから追加',
                        subtitle: '投稿を共有するだけ',
                        onTap: () => _showShareGuide(context),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _AddMethodCard(
                        icon: Icons.add_location_alt_outlined,
                        title: '手動で追加',
                        subtitle: '店名・住所から検索',
                        onTap: () => _showManualAdd(context),
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: maps.isEmpty
              ? EmptyState(
                  icon: Icons.terrain_rounded,
                  title: 'まだマップがない',
                  message: 'ごはん屋、旅行、撮影スポット…\n好きなテーマで地図をつくろう。',
                  action: FilledButton(
                    onPressed: () => _showCreateMap(context),
                    child: const Text('マップをつくる'),
                  ),
                )
              : maps.length == 1
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 100),
                  children: [
                    SizedBox(
                      height: cardHeight,
                      child: MapCard(map: maps.first),
                    ),
                    if (recentPlaces.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Text(
                            '最近追加した場所',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => _openCrossSearch(context),
                            child: const Text('すべて見る'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ...recentPlaces
                          .take(3)
                          .map((place) => _RecentPlaceTile(place: place)),
                    ],
                  ],
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 100),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: useSingleColumn ? 1 : 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent: useSingleColumn ? cardHeight : 190,
                  ),
                  itemCount: maps.length,
                  itemBuilder: (context, i) => MapCard(map: maps[i]),
                ),
        ),
      ],
    );
  }

  static Future<void> _openCrossSearch(BuildContext context) async {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!context.mounted) return;
    final controller = AppScope.read(context);
    final queryController = TextEditingController();
    PlaceFilterOption filter = PlaceFilterOption.all;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              final results = controller.queryPlaces(
                query: queryController.text,
                filter: filter,
              );
              final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
              return AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(bottom: keyboardHeight),
                child: SizedBox(
                  height: modalSheetHeight(context),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '横断検索',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: queryController,
                          autofocus: false,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: '店名・住所・タグ・メモ',
                          ),
                          onChanged: (_) => setModalState(() {}),
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final option
                                  in PlaceFilterOption.values) ...[
                                FilterChip(
                                  label: Text(option.label),
                                  selected: filter == option,
                                  onSelected: (_) =>
                                      setModalState(() => filter = option),
                                ),
                                const SizedBox(width: 8),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: results.isEmpty
                              ? const EmptyState(
                                  icon: Icons.search_off,
                                  title: '見つかりませんでした',
                                  message: 'キーワードや絞り込みを変えてみてください。',
                                )
                              : ListView.separated(
                                  itemCount: results.length,
                                  separatorBuilder: (_, index) =>
                                      const SizedBox(height: 8),
                                  itemBuilder: (_, i) =>
                                      PlaceListTile(place: results[i]),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      disposeAfterFrame([queryController]);
    }
  }

  static Future<void> _showCreateMap(BuildContext context) async {
    if (_createMapSheetOpen || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _createMapSheetOpen = true;
    final controller = AppScope.read(context);
    try {
      final result = await showModalBottomSheet<_CreateMapResult>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (ctx) => const _CreateMapSheet(),
      );
      if (result != null && context.mounted) {
        final created = await runGuarded(
          context,
          () => controller.createMap(
            name: result.name,
            description: result.description,
            icon: result.icon,
          ),
        );
        if (created != null && context.mounted) {
          showInfoSnackBar(context, '「${result.name}」を作成しました');
        }
      }
    } finally {
      _createMapSheetOpen = false;
    }
  }

  static Future<void> _showShareGuide(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SNSから追加',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            const Text(
              'TikTokやInstagramで投稿の「共有」を押し、Pinlogyを選んでください。メモなしでも場所を検索します。',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: mintSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded, color: moss),
                  SizedBox(width: 10),
                  Expanded(child: Text('無料プランでも利用できます。AI上限後は端末内解析と手動追加を使えます。')),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('わかりました'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _showManualAdd(BuildContext context) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!context.mounted) return;
    final controller = AppScope.read(context);
    if (controller.hub.snapshot.maps.isEmpty) {
      await _showCreateMap(context);
      if (!context.mounted || controller.hub.snapshot.maps.isEmpty) return;
    }
    final queryController = TextEditingController();
    var screenshotRequested = false;
    try {
      final query = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.add_location_alt_outlined),
          title: const Text('場所を手動で追加'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('店名だけで見つからない場合は、駅名や住所も一緒に入力してください。'),
                const SizedBox(height: 12),
                TextField(
                  controller: queryController,
                  autofocus: false,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    labelText: '店名・住所',
                    hintText: '例：喫茶ソワレ 京都',
                  ),
                  onSubmitted: (value) =>
                      Navigator.pop(dialogContext, value.trim()),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text('または'),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      screenshotRequested = true;
                      Navigator.pop(dialogContext);
                    },
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('AIでスクショから追加（最大5枚）'),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '投稿の途中にあるお店は、その画像や動画の場面をスクショしてください。',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
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
      if (screenshotRequested && context.mounted) {
        await _showScreenshotAiAdd(context);
        return;
      }
      if (query == null || query.isEmpty || !context.mounted) return;
      final hits = await runGuarded(
        context,
        () => controller.placeSearch.searchByName(query),
      );
      if (!context.mounted) return;
      if (hits == null) return;
      if (hits.isEmpty) {
        showInfoSnackBar(context, '場所が見つかりませんでした。住所や地域を追加して再検索してください');
        return;
      }
      final hit = await showModalBottomSheet<PlaceSearchHit>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) => SizedBox(
          height: modalSheetHeight(sheetContext),
          child: Column(
            children: [
              const ListTile(
                title: Text(
                  '追加する場所を選択',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text('無料の場所検索を利用しています'),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: hits
                      .map(
                        (item) => ListTile(
                          leading: const Icon(Icons.place_outlined),
                          title: Text(item.name),
                          subtitle: Text(item.address ?? '住所情報なし'),
                          onTap: () => Navigator.pop(sheetContext, item),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      );
      if (hit == null || !context.mounted) return;
      final map = await _selectDestinationMap(
        context,
        controller.hub.snapshot.maps,
      );
      if (map == null || !context.mounted) return;
      final created = await runGuarded(
        context,
        () => controller.places.create(
          Place(
            name: hit.name,
            address: hit.address,
            latitude: hit.latitude,
            longitude: hit.longitude,
            evidenceSummary: '手動検索から追加',
          ),
          mapIds: [map.id],
        ),
      );
      if (created != null && context.mounted) {
        showInfoSnackBar(context, '「${hit.name}」を「${map.name}」に追加しました');
      }
    } finally {
      disposeAfterFrame([queryController]);
    }
  }

  static Future<void> _showScreenshotAiAdd(BuildContext context) async {
    final aiEnabled = await showAiAnalysisConsentIfNeeded(context);
    if (!context.mounted) return;
    final images = await ImagePicker().pickMultiImage(
      imageQuality: 88,
      limit: 5,
    );
    if (images.isEmpty || !context.mounted) return;

    final hintController = TextEditingController();
    try {
      final hint = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.auto_awesome_outlined),
          title: Text('${images.length}枚のスクショを解析'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('店名・住所・料理名など、画像内のヒントをまとめて探します。入力なしでも解析できます。'),
              const SizedBox(height: 12),
              TextField(
                controller: hintController,
                autofocus: false,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '補足（任意）',
                  hintText: '例：7枚目に紹介されていた大阪のお店',
                ),
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
                  Navigator.pop(dialogContext, hintController.text.trim()),
              child: const Text('解析する'),
            ),
          ],
        ),
      );
      if (hint == null || !context.mounted) return;
      await AppScope.read(context).shareIntake.ingest(
        SharedContent(
          service: 'スクリーンショット',
          title: 'AIスクショから追加',
          text: hint,
          imagePaths: images.map((image) => image.path).toList(),
        ),
      );
      if (!context.mounted) return;
      showInfoSnackBar(
        context,
        aiEnabled
            ? '${images.length}枚を受信箱に追加し、AI解析を開始しました'
            : '${images.length}枚を受信箱に追加し、端末内解析を開始しました',
      );
    } finally {
      disposeAfterFrame([hintController]);
    }
  }

  static Future<PinMap?> _selectDestinationMap(
    BuildContext context,
    List<PinMap> maps,
  ) async {
    if (maps.length == 1) return maps.first;
    return showModalBottomSheet<PinMap>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const ListTile(
            title: Text(
              '保存先のマップを選択',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          ...maps.map(
            (map) => ListTile(
              leading: Text(map.icon, style: const TextStyle(fontSize: 24)),
              title: Text(map.name),
              subtitle: map.description.isEmpty ? null : Text(map.description),
              onTap: () => Navigator.pop(sheetContext, map),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddMethodCard extends StatelessWidget {
  const _AddMethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: .82),
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: mint,
              foregroundColor: mossDeep,
              child: Icon(icon, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RecentPlaceTile extends StatelessWidget {
  const _RecentPlaceTile({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: Colors.white.withValues(alpha: .62),
      borderRadius: BorderRadius.circular(18),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: mint,
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(Icons.place_rounded, color: mossDeep, size: 21),
        ),
        title: Text(
          place.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          place.address ?? '住所未設定',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => showPlaceDetails(context, place),
      ),
    ),
  );
}

class _CreateMapResult {
  const _CreateMapResult({
    required this.name,
    required this.description,
    required this.icon,
  });

  final String name;
  final String description;
  final String icon;
}

class _CreateMapSheet extends StatefulWidget {
  const _CreateMapSheet();

  @override
  State<_CreateMapSheet> createState() => _CreateMapSheetState();
}

class _CreateMapSheetState extends State<_CreateMapSheet> {
  final nameController = TextEditingController();
  final descController = TextEditingController();
  String icon = '📍';

  @override
  void dispose() {
    nameController.dispose();
    descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
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
            '新しいマップ',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: nameController,
            autofocus: true,
            decoration: const InputDecoration(hintText: '例：京都旅行、行きたいごはん屋'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: descController,
            decoration: const InputDecoration(hintText: '説明（任意）'),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: ['📍', '🍜', '☕', '✈️', '📷', '🏕️', '❤️']
                .map(
                  (e) => ChoiceChip(
                    label: Text(e),
                    selected: icon == e,
                    onSelected: (_) => setState(() => icon = e),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(
                  context,
                  _CreateMapResult(
                    name: name,
                    description: descController.text.trim(),
                    icon: icon,
                  ),
                );
              },
              child: const Text('作成する'),
            ),
          ),
        ],
      ),
    );
  }
}

class MapCard extends StatelessWidget {
  const MapCard({super.key, required this.map});

  final PinMap map;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final count = controller.placeCountForMap(map.id);
    final isShared = controller.hub.snapshot.mapMembers.any(
      (member) => member.mapId == map.id && member.role != 'owner',
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => MapScreen(mapId: map.id)),
        ),
        onLongPress: () => _showMapActions(context),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                map.themeColor.withValues(alpha: 0.95),
                Color.lerp(map.themeColor, mint, 0.45)!,
                Colors.white.withValues(alpha: 0.88),
              ],
              stops: const [0, 0.55, 1],
            ),
            boxShadow: [
              BoxShadow(
                color: mossDeep.withValues(alpha: 0.07),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .72),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        map.icon,
                        style: const TextStyle(fontSize: 23),
                      ),
                    ),
                    if (isShared) ...[
                      const SizedBox(width: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .62),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people_outline_rounded, size: 14),
                            SizedBox(width: 4),
                            Text(
                              '共有',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Spacer(),
                    Material(
                      color: Colors.white.withValues(alpha: .5),
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: 'マップの設定',
                        onPressed: () => _showMapActions(context),
                        icon: const Icon(Icons.more_horiz_rounded, size: 20),
                        color: mossDeep.withValues(alpha: .7),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  map.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: 20,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  map.description.isEmpty ? 'まだ説明がありません' : map.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .62),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$count スポット',
                        style: Theme.of(
                          context,
                        ).textTheme.labelLarge?.copyWith(color: mossDeep),
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 19,
                      color: mossDeep,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMapActions(BuildContext context) async {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    final controller = AppScope.read(context);
    final isShared = controller.hub.snapshot.mapMembers.any(
      (member) => member.mapId == map.id && member.role != 'owner',
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('マップを編集'),
              onTap: () {
                Navigator.pop(ctx);
                _editMap(context);
              },
            ),
            if (!isShared)
              ListTile(
                leading: Icon(map.isPublic ? Icons.lock_outline : Icons.public),
                title: Text(map.isPublic ? '公開を停止' : '公開マップにする'),
                subtitle: Text(
                  map.isPublic
                      ? '新しいユーザーから検索されなくなります'
                      : '場所名・住所・座標が公開され、他ユーザーが複製できます',
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  var approved = true;
                  if (!map.isPublic) {
                    approved =
                        await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('このマップを公開しますか？'),
                            content: const Text(
                              'マップ名、説明、登録した場所の店名・住所・座標がPinlogyユーザーに表示され、複製できるようになります。メモ、元投稿、訪問履歴は公開されません。',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                child: const Text('キャンセル'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, true),
                                child: const Text('理解して公開'),
                              ),
                            ],
                          ),
                        ) ??
                        false;
                  }
                  if (approved && context.mounted) {
                    await runGuardedAction(
                      context,
                      () => controller.maps.update(
                        map.copyWith(isPublic: !map.isPublic),
                      ),
                    );
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_rounded),
              title: const Text('旅行日程を自動作成'),
              subtitle: const Text('近い場所をまとめて順番に並べます'),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  final plan = await controller.createAutoPlanFromMap(map.id);
                  if (context.mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => PlanDetailPage(planId: plan.id),
                      ),
                    );
                  }
                } catch (error) {
                  if (context.mounted) showErrorSnackBar(context, error);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_all_outlined),
              title: const Text('自分用に複製'),
              subtitle: const Text('共有状態を外して編集できるコピーを作ります'),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  final copy = await controller.duplicateMap(map.id);
                  if (context.mounted) {
                    showInfoSnackBar(context, '「${copy.name}」を作成しました');
                  }
                } catch (error) {
                  if (context.mounted) showErrorSnackBar(context, error);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('マップを削除', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dCtx) => AlertDialog(
                    title: const Text('マップを削除しますか？'),
                    content: Text('「${map.name}」を削除します。場所データ自体は他のマップに残ります。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dCtx, false),
                        child: const Text('キャンセル'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dCtx, true),
                        child: const Text('削除'),
                      ),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  await runGuardedAction(
                    context,
                    () => controller.maps.delete(map.id),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editMap(BuildContext context) async {
    final controller = AppScope.read(context);
    final nameController = TextEditingController(text: map.name);
    final descController = TextEditingController(text: map.description);
    try {
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (ctx) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.viewInsetsOf(ctx).bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'マップを編集',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(hintText: 'マップ名'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(hintText: '説明'),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final name = nameController.text.trim();
      final description = descController.text.trim();
      if (saved == true && context.mounted) {
        await runGuarded(
          context,
          () => controller.maps.update(
            map.copyWith(name: name, description: description),
          ),
        );
      }
    } finally {
      disposeAfterFrame([nameController, descController]);
    }
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.mapId});

  final String mapId;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  bool listView = false;
  String query = '';
  String? category;
  PlaceFilterOption filter = PlaceFilterOption.all;
  PlaceSortOption sort = PlaceSortOption.registeredDesc;
  final TextEditingController _searchController = TextEditingController();
  final MapController _mapController = MapController();
  LatLng? _userLocation;
  bool _locating = false;
  String? _focusPlaceId;
  LatLngBounds? _searchBounds;

  @override
  void dispose() {
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final map = controller.hub.snapshot.maps.cast<PinMap?>().firstWhere(
      (m) => m!.id == widget.mapId,
      orElse: () => null,
    );
    if (map == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('マップ')),
        body: const EmptyState(
          icon: Icons.error_outline,
          title: 'マップが見つかりません',
          message: '削除されたか、データが読み込めませんでした。',
        ),
      );
    }

    final matchingPlaces = controller.queryPlaces(
      query: query,
      filter: filter,
      sort: sort,
      mapId: map.id,
    );
    final availableCategories =
        matchingPlaces
            .map((place) => place.category?.trim())
            .whereType<String>()
            .where((value) => value.isNotEmpty && value != 'その他')
            .toSet()
            .toList()
          ..sort();
    final effectiveCategory = availableCategories.contains(category)
        ? category
        : null;
    final categoryPlaces = effectiveCategory == null
        ? matchingPlaces
        : matchingPlaces
              .where((place) => place.category?.trim() == effectiveCategory)
              .toList(growable: false);
    final places = _searchBounds == null
        ? categoryPlaces
        : categoryPlaces
              .where(
                (place) =>
                    _searchBounds!.contains(PlaceMapView.pointFor(place)),
              )
              .toList(growable: false);
    return PinlogyBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${map.icon} ${map.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                '${places.length}スポット',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          actions: [
            if (defaultTargetPlatform == TargetPlatform.iOS)
              IconButton(
                tooltip: 'Appleマップで表示',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MapKitComparisonPage(places: places),
                  ),
                ),
                icon: const Icon(Icons.compare_rounded),
              ),
            IconButton(
              tooltip: listView ? '地図で表示' : '一覧で表示',
              onPressed: () => setState(() => listView = !listView),
              icon: Icon(
                listView ? Icons.map_rounded : Icons.view_list_rounded,
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            if (filter != PlaceFilterOption.all ||
                query.isNotEmpty ||
                effectiveCategory != null ||
                _searchBounds != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      if (query.isNotEmpty)
                        Chip(
                          label: Text('「$query」'),
                          onDeleted: () {
                            _searchController.clear();
                            setState(() => query = '');
                          },
                        ),
                      if (filter != PlaceFilterOption.all)
                        Chip(
                          label: Text(filter.label),
                          onDeleted: () =>
                              setState(() => filter = PlaceFilterOption.all),
                        ),
                      if (effectiveCategory != null)
                        Chip(
                          label: Text(effectiveCategory),
                          onDeleted: () => setState(() => category = null),
                        ),
                      if (_searchBounds != null)
                        Chip(
                          avatar: const Icon(Icons.map_outlined, size: 17),
                          label: const Text('地図の範囲内'),
                          onDeleted: () => setState(() => _searchBounds = null),
                        ),
                      Chip(label: Text(sort.label)),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: listView
                  ? _placeList(places, map.id)
                  : _mapCanvas(
                      places,
                      map.id,
                      availableCategories: availableCategories,
                      effectiveCategory: effectiveCategory,
                    ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => showAddPlaceSheet(
            context,
            mapId: map.id,
            onPlaceAdded: _focusOnPlace,
          ),
          icon: const Icon(Icons.add_rounded),
          label: const Text('場所を残す'),
        ),
      ),
    );
  }

  Future<void> _showFilterSheet(BuildContext context) async {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '絞り込み・並び替え',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '絞り込み',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in PlaceFilterOption.values)
                        ChoiceChip(
                          label: Text(option.label),
                          selected: filter == option,
                          onSelected: (_) {
                            setModalState(() => filter = option);
                            setState(() {});
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '並び替え',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in PlaceSortOption.values)
                        ChoiceChip(
                          label: Text(option.label),
                          selected: sort == option,
                          onSelected: (_) {
                            setModalState(() => sort = option);
                            setState(() {});
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('完了'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _placeList(List<Place> places, String mapId) {
    if (places.isEmpty) {
      return EmptyState(
        icon: Icons.place_outlined,
        title: 'スポットがありません',
        message: '右下のボタン、または地図の長押しで場所を追加できます。',
        action: FilledButton(
          onPressed: () => showAddPlaceSheet(
            context,
            mapId: mapId,
            onPlaceAdded: _focusOnPlace,
          ),
          child: const Text('場所を追加'),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: places.length,
      separatorBuilder: (_, index) => const SizedBox(height: 10),
      itemBuilder: (_, i) => PlaceListTile(
        place: places[i],
        onLocate: places[i].latitude != null && places[i].longitude != null
            ? () => _focusOnPlace(places[i])
            : null,
      ),
    );
  }

  Widget _mapCanvas(
    List<Place> places,
    String mapId, {
    required List<String> availableCategories,
    required String? effectiveCategory,
  }) {
    return Stack(
      children: [
        PlaceMapView(
          places: places,
          mapController: _mapController,
          mapId: mapId,
          userLocation: _userLocation,
          locating: _locating,
          focusPlaceId: _focusPlaceId,
          onLongPress: (point) => _addPinAt(context, mapId, point),
          onMyLocation: () => _goToMyLocation(context),
          onSearchArea: (camera) {
            FocusManager.instance.primaryFocus?.unfocus();
            setState(() => _searchBounds = camera.visibleBounds);
          },
          searchField: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'このマップを検索',
              suffixIcon: IconButton(
                icon: const Icon(Icons.tune),
                onPressed: () => _showFilterSheet(context),
              ),
            ),
            onChanged: (value) => setState(() => query = value),
          ),
        ),
        Positioned(
          top: 90,
          left: 14,
          right: 14,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final option in const [
                  PlaceFilterOption.all,
                  PlaceFilterOption.openNow,
                  PlaceFilterOption.unvisited,
                  PlaceFilterOption.nearby,
                ]) ...[
                  FilterPill(
                    label: option.label,
                    selected: option == PlaceFilterOption.all
                        ? filter == PlaceFilterOption.all &&
                              effectiveCategory == null
                        : filter == option,
                    onTap: () => setState(() {
                      filter = option;
                      if (option == PlaceFilterOption.all) category = null;
                    }),
                  ),
                  const SizedBox(width: 7),
                ],
                for (final item in availableCategories) ...[
                  FilterPill(
                    label: item,
                    selected: effectiveCategory == item,
                    onTap: () => setState(() {
                      category = effectiveCategory == item ? null : item;
                    }),
                  ),
                  const SizedBox(width: 7),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _focusOnPlace(Place place) {
    if (!mounted) return;
    setState(() {
      listView = false;
      _focusPlaceId = place.id;
    });
    final lat = place.latitude;
    final lng = place.longitude;
    if (lat == null || lng == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.move(LatLng(lat, lng), PlaceMapView.focusZoom);
    });
  }

  Future<void> _goToMyLocation(BuildContext context) async {
    if (_locating) return;
    setState(() => _locating = true);
    final location = AppScope.read(context).deviceLocation;
    try {
      final result = await runGuarded(context, location.locateFast);
      if (!mounted || result == null) return;

      setState(() => _userLocation = result.point);
      _mapController.move(result.point, 15);

      if (result.approximate) {
        showInfoSnackBar(this.context, 'おおよその現在地を表示しています');
        unawaited(_refineLocation());
      } else {
        showInfoSnackBar(this.context, '現在地を表示しました');
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _refineLocation() async {
    if (!mounted) return;
    final location = AppScope.read(context).deviceLocation;
    final precise = await runGuarded(context, location.locatePrecise);
    if (!mounted || precise == null) return;
    setState(() => _userLocation = precise);
    _mapController.move(precise, 15);
  }

  Future<void> _addPinAt(
    BuildContext context,
    String mapId,
    LatLng point,
  ) async {
    final nameController = TextEditingController();
    final noteController = TextEditingController();
    var name = '';
    var note = '';
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('ここにピンを追加'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: '場所の名前'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: noteController,
                  decoration: const InputDecoration(hintText: '保存理由・メモ'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('追加'),
            ),
          ],
        ),
      );
      name = nameController.text.trim();
      note = noteController.text.trim();
      if (ok == true && name.isNotEmpty && context.mounted) {
        final created = await runGuarded(
          context,
          () => AppScope.read(context).runExclusive(() async {
            return AppScope.read(context).places.create(
              Place(
                name: name,
                saveReason: note.isEmpty ? null : note,
                latitude: point.latitude,
                longitude: point.longitude,
                category: '自由ピン',
              ),
              mapIds: [mapId],
            );
          }),
        );
        if (created != null && context.mounted) {
          _focusOnPlace(created);
          showInfoSnackBar(context, '「$name」を追加しました');
        }
      }
    } finally {
      disposeAfterFrame([nameController, noteController]);
    }
  }
}

class PlaceListTile extends StatelessWidget {
  const PlaceListTile({super.key, required this.place, this.onLocate});

  final Place place;
  final VoidCallback? onLocate;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final source = controller.primarySourceForPlace(place.id);
    final canOpen = controller.sourceLinks.canOpen(source);

    return Material(
      color: Colors.white.withValues(alpha: 0.52),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => showPlaceDetails(context, place),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 10, 16),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: place.isVisited ? mossDeep : mint,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  place.isVisited ? Icons.check_rounded : Icons.place_rounded,
                  color: place.isVisited ? Colors.white : mossDeep,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      place.address ?? '住所未設定',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (source != null) ...[
                      const SizedBox(height: 7),
                      Text(
                        controller.sourceLinks.serviceLabel(source),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: moss,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onLocate != null)
                IconButton(
                  tooltip: '地図で見る',
                  onPressed: onLocate,
                  icon: const Icon(Icons.center_focus_strong_rounded),
                ),
              if (canOpen)
                IconButton(
                  tooltip: '投稿を開く',
                  onPressed: () => openSourcePostOrWarn(context, source),
                  icon: Icon(
                    controller.sourceLinks.iconFor(source),
                    color: mossDeep,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
