import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/app_scope.dart';
import '../../core/errors.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/location_services.dart';
import '../../services/route_privacy_consent.dart';
import '../../services/share_receiver_service.dart';
import '../../widgets/feedback.dart';
import '../../widgets/place_photo.dart';
import '../../widgets/sheet_layout.dart';
import '../../widgets/source_post_tile.dart';
import '../routes/route_preview_page.dart';
import 'place_edit_page.dart';

bool _placeDetailsVisible = false;

Future<void> showPlaceDetails(BuildContext context, Place place) async {
  if (_placeDetailsVisible || ModalRoute.of(context)?.isCurrent != true) return;
  _placeDetailsVisible = true;
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => PlaceDetailsSheet(placeId: place.id),
    );
  } finally {
    _placeDetailsVisible = false;
  }
}

class PlaceDetailsSheet extends StatelessWidget {
  const PlaceDetailsSheet({super.key, required this.placeId});

  final String placeId;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final place = controller.hub.snapshot.places.cast<Place?>().firstWhere(
      (p) => p!.id == placeId,
      orElse: () => null,
    );
    if (place == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('場所が見つかりません'),
      );
    }

    final maps = controller.hub.snapshot.mapPlaces
        .where((mp) => mp.placeId == place.id)
        .map((mp) {
          try {
            return controller.hub.snapshot.maps.firstWhere(
              (m) => m.id == mp.mapId,
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<PinMap>()
        .toList();

    final posts = controller.sourcesForPlace(place.id);
    final primary = controller.primarySourceForPlace(place.id);
    final canOpenPrimary = controller.sourceLinks.canOpen(primary);
    final sourceImagePath = primary?.displayThumbnailPath;
    final imagePath = place.coverImagePath ?? sourceImagePath;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .86,
      minChildSize: .45,
      maxChildSize: .94,
      builder: (_, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
        children: [
          if (imagePath != null) ...[
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: SizedBox(
                    height: 220,
                    child: PlacePhoto(
                      path: imagePath,
                      onRefreshSource: primary?.url == null
                          ? null
                          : () async {
                              final refreshed = await controller.shareReceiver
                                  .refreshOfficialPreview(
                                    primary!,
                                    force: true,
                                  );
                              return refreshed.displayThumbnailPath;
                            },
                      fallback: ColoredBox(
                        color: mint,
                        child: const Center(
                          child: Icon(Icons.image_not_supported_outlined),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: _PhotoMenu(
                    hasCustomPhoto: place.coverImagePath != null,
                    onChange: () => _pickCoverPhoto(context, place),
                    onRemove: () => _removeCoverPhoto(context, place),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
          ] else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: const SizedBox(
                height: 220,
                child: Image(
                  image: AssetImage('assets/images/place_fallback.webp'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (primary?.url != null)
                  FilledButton.tonalIcon(
                    onPressed: () => _fetchPostPhoto(context, primary!),
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: const Text('投稿画像を取得'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _pickCoverPhoto(context, place),
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('写真を選ぶ'),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  place.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              if (canOpenPrimary)
                IconButton.filledTonal(
                  tooltip: '投稿を開く',
                  onPressed: () => openSourcePostOrWarn(context, primary),
                  icon: Icon(controller.sourceLinks.iconFor(primary)),
                ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'delete') {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('場所を削除しますか？'),
                        content: const Text('この操作は元に戻せません。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('キャンセル'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('削除'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true && context.mounted) {
                      final deleted = await runGuardedAction(
                        context,
                        () => controller.places.delete(place.id),
                      );
                      if (deleted && context.mounted) Navigator.pop(context);
                    }
                  } else if (value == 'favorite') {
                    await controller.visits.setStatus(
                      place.id,
                      VisitStatus.favorite,
                    );
                  } else if (value == 'open_post') {
                    await openSourcePostOrWarn(context, primary);
                  } else if (value == 'add_map') {
                    await _addToAnotherMap(context, place);
                  } else if (value == 'add_plan') {
                    await _addToPlan(context, place);
                  } else if (value == 'edit') {
                    if (context.mounted) {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PlaceDetailPage(placeId: place.id),
                        ),
                      );
                    }
                  }
                },
                itemBuilder: (_) => [
                  if (canOpenPrimary)
                    const PopupMenuItem(
                      value: 'open_post',
                      child: Text('元の投稿を開く'),
                    ),
                  const PopupMenuItem(value: 'edit', child: Text('編集する')),
                  const PopupMenuItem(
                    value: 'add_map',
                    child: Text('別のマップにも追加'),
                  ),
                  const PopupMenuItem(value: 'add_plan', child: Text('プランに追加')),
                  const PopupMenuItem(
                    value: 'favorite',
                    child: Text('お気に入りにする'),
                  ),
                  const PopupMenuItem(value: 'delete', child: Text('削除')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            place.address ?? '住所未設定',
            style: TextStyle(color: Colors.grey.shade700, height: 1.4),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text(place.visitStatus.label)),
              if (place.category != null) Chip(label: Text(place.category!)),
              if (place.visitCount > 0)
                Chip(label: Text('${place.visitCount}回訪問')),
              if (place.openingTimeMinutes != null &&
                  place.closingTimeMinutes != null)
                Chip(
                  avatar: Icon(
                    Icons.schedule_rounded,
                    size: 17,
                    color: place.isOpenAt(DateTime.now()) ? moss : null,
                  ),
                  label: Text(
                    place.isOpenAt(DateTime.now())
                        ? '営業中・${place.openingHoursLabel}'
                        : place.openingHoursLabel,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _QuickAction(
                  onPressed: () => _openRoute(context, place),
                  icon: Icons.directions_outlined,
                  label: '経路',
                  emphasized: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickAction(
                  onPressed: () async {
                    await controller.visits.markVisited(place.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('訪問済みにしました')),
                      );
                    }
                  },
                  icon: Icons.check_circle_outline,
                  label: '行った',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickAction(
                  onPressed: () => _sharePlace(context, place),
                  icon: Icons.ios_share_rounded,
                  label: '共有',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('保存した理由', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: mint,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              place.saveReason?.isNotEmpty == true
                  ? place.saveReason!
                  : 'まだ理由が記録されていません',
              style: const TextStyle(height: 1.55),
            ),
          ),
          if (place.userMemo?.isNotEmpty == true) ...[
            const SizedBox(height: 22),
            Text('メモ', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(place.userMemo!),
          ],
          const SizedBox(height: 22),
          Text('元の投稿', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (posts.isEmpty)
            Text('関連投稿なし', style: TextStyle(color: Colors.grey.shade600))
          else
            ...posts.map(
              (post) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SourcePostTile(post: post),
              ),
            ),
          const Divider(height: 30),
          Text('所属マップ', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: maps
                .map((m) => Chip(label: Text('${m.icon} ${m.name}')))
                .toList(),
          ),
          const SizedBox(height: 18),
          Text(
            place.evidenceSummary ??
                (place.confidencePercent != null
                    ? '一致度 ${place.confidencePercent}%'
                    : ''),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCoverPhoto(BuildContext context, Place place) async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 84,
    );
    if (image == null || !context.mounted) return;
    final controller = AppScope.read(context);
    await controller.places.update(
      place.copyWith(coverImagePath: image.path, updatedAt: DateTime.now()),
    );
  }

  Future<void> _fetchPostPhoto(BuildContext context, SourcePost post) async {
    final ok = await runGuardedAction(
      context,
      () => AppScope.read(context).shareReceiver.refreshOfficialPreview(post),
    );
    if (ok && context.mounted) {
      showInfoSnackBar(context, '投稿の代表画像を取得しました');
    }
  }

  Future<void> _removeCoverPhoto(BuildContext context, Place place) async {
    await AppScope.read(context).places.update(
      place.copyWith(clearCoverImage: true, updatedAt: DateTime.now()),
    );
  }

  Future<void> _openRoute(BuildContext context, Place place) async {
    final controller = AppScope.read(context);
    if (place.latitude == null ||
        place.longitude == null ||
        !controller.inAppRoutes.isConfigured) {
      final ok = await controller.directions.openDirections(place);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('経路を開けませんでした。場所の住所を確認してください。')),
        );
      }
      return;
    }

    final consent = RoutePrivacyConsent();
    var allowed = await consent.hasConsented();
    if (!allowed && context.mounted) {
      allowed =
          await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              icon: const Icon(Icons.privacy_tip_outlined),
              title: const Text('経路表示について'),
              content: const Text(
                '経路を計算するため、現在地と目的地の座標を経路サービスへ送信します。'
                'バックグラウンドでの送信や、Pinlogyでの経路履歴保存は行いません。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('キャンセル'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('同意して表示'),
                ),
              ],
            ),
          ) ??
          false;
      if (allowed) await consent.grant();
    }
    if (!allowed || !context.mounted) return;

    final navigator = Navigator.of(context);
    navigator.pop();
    await navigator.push(
      MaterialPageRoute<void>(builder: (_) => RoutePreviewPage(place: place)),
    );
  }

  Future<void> _sharePlace(BuildContext context, Place place) async {
    final approved =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(Icons.share_outlined),
            title: const Text('場所を共有しますか？'),
            content: Text(
              '共有先には店名${place.address?.isNotEmpty == true ? '・住所' : ''}'
              '${place.latitude != null && place.longitude != null ? '・地図リンク' : ''}が送られます。'
              'メモや元投稿は共有しません。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('共有先を選ぶ'),
              ),
            ],
          ),
        ) ??
        false;
    if (!approved) return;
    final lines = <String>[
      place.name,
      if (place.address?.isNotEmpty == true) place.address!,
      if (place.latitude != null && place.longitude != null)
        'https://www.google.com/maps/search/?api=1&query=${place.latitude},${place.longitude}',
      'Pinlogyから共有',
    ];
    try {
      await SharePlus.instance.share(
        ShareParams(subject: place.name, text: lines.join('\n')),
      );
    } catch (error) {
      if (context.mounted) showErrorSnackBar(context, error);
    }
  }

  Future<void> _addToAnotherMap(BuildContext context, Place place) async {
    final controller = AppScope.read(context);
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    Navigator.pop(context);
    await Future<void>.delayed(Duration.zero);
    if (!rootContext.mounted) return;
    final maps = controller.hub.snapshot.maps;
    final selected = await showModalBottomSheet<String>(
      context: rootContext,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '追加先マップを選択',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            ...maps.map(
              (m) => ListTile(
                title: Text('${m.icon} ${m.name}'),
                onTap: () => Navigator.pop(ctx, m.id),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null && rootContext.mounted) {
      final added = await runGuardedAction(
        rootContext,
        () => controller.places.addToMap(placeId: place.id, mapId: selected),
      );
      if (added && rootContext.mounted) {
        showInfoSnackBar(rootContext, 'マップに追加しました（場所データは複製していません）');
      }
    }
  }

  Future<void> _addToPlan(BuildContext context, Place place) async {
    final controller = AppScope.read(context);
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    Navigator.pop(context);
    await Future<void>.delayed(Duration.zero);
    if (!rootContext.mounted) return;
    final plans = List<TripPlan>.of(controller.hub.snapshot.plans)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (plans.isEmpty) {
      if (rootContext.mounted) {
        ScaffoldMessenger.of(
          rootContext,
        ).showSnackBar(const SnackBar(content: Text('先にプランタブでプランをつくってください')));
      }
      return;
    }

    final planId = await showModalBottomSheet<String>(
      context: rootContext,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '追加先プランを選択',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            ...plans.map(
              (p) => ListTile(
                title: Text(p.title),
                subtitle: p.startDate == null
                    ? null
                    : Text(
                        '${p.startDate!.year}/${p.startDate!.month}/${p.startDate!.day}',
                      ),
                onTap: () => Navigator.pop(ctx, p.id),
              ),
            ),
          ],
        ),
      ),
    );
    if (planId == null || !rootContext.mounted) return;

    TripPlan? plan;
    for (final p in plans) {
      if (p.id == planId) {
        plan = p;
        break;
      }
    }
    final existingDays =
        controller.hub.snapshot.planStops
            .where((s) => s.planId == planId)
            .map((s) => s.dayDate)
            .toSet()
            .toList()
          ..sort((a, b) {
            if (a == null && b == null) return 0;
            if (a == null) return 1;
            if (b == null) return -1;
            return a.compareTo(b);
          });
    DateTime? day;
    if (existingDays.isEmpty) {
      day = plan?.startDate == null
          ? null
          : PlanStop.dateOnly(plan!.startDate!);
    } else if (existingDays.length == 1) {
      day = existingDays.first;
    } else {
      final pickedIndex = await showModalBottomSheet<int>(
        context: rootContext,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '追加する日を選択',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              for (var i = 0; i < existingDays.length; i++)
                ListTile(
                  title: Text(
                    existingDays[i] == null
                        ? '日付未定'
                        : '${existingDays[i]!.year}/${existingDays[i]!.month}/${existingDays[i]!.day}',
                  ),
                  onTap: () => Navigator.pop(ctx, i),
                ),
            ],
          ),
        ),
      );
      if (pickedIndex == null || !rootContext.mounted) return;
      day = existingDays[pickedIndex];
    }

    final added = await runGuarded(
      rootContext,
      () => controller.plans.addStop(
        PlanStop(
          planId: planId,
          placeId: place.id,
          dayDate: day,
          stayMinutes: 60,
        ),
      ),
    );
    if (added != null && rootContext.mounted) {
      showInfoSnackBar(rootContext, 'プランに追加しました');
    }
  }
}

class _PhotoMenu extends StatelessWidget {
  const _PhotoMenu({
    required this.hasCustomPhoto,
    required this.onChange,
    required this.onRemove,
  });

  final bool hasCustomPhoto;
  final VoidCallback onChange;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .94),
      borderRadius: BorderRadius.circular(999),
      child: PopupMenuButton<String>(
        tooltip: 'カバー写真を編集',
        icon: const Icon(Icons.photo_camera_outlined, color: mossDeep),
        onSelected: (value) {
          if (value == 'change') onChange();
          if (value == 'remove') onRemove();
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'change', child: Text('写真を選び直す')),
          if (hasCustomPhoto)
            const PopupMenuItem(value: 'remove', child: Text('選んだ写真を解除')),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Material(
    color: emphasized ? mossDeep : mintSoft,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: emphasized ? Colors.white : mossDeep),
            const SizedBox(height: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: emphasized ? Colors.white : mossDeep,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showAddPlaceSheet(
  BuildContext context, {
  required String mapId,
  void Function(Place place)? onPlaceAdded,
}) async {
  if (ModalRoute.of(context)?.isCurrent != true) return;
  FocusManager.instance.primaryFocus?.unfocus();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _AddPlaceSheet(mapId: mapId, onPlaceAdded: onPlaceAdded),
  );
}

class _AddPlaceSheet extends StatelessWidget {
  const _AddPlaceSheet({required this.mapId, this.onPlaceAdded});

  final String mapId;
  final void Function(Place place)? onPlaceAdded;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: modalSheetHeight(context, fraction: 0.85),
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            const Text(
              '場所を追加',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text('今見ているマップに追加します'),
            const SizedBox(height: 18),
            _AddOption(
              icon: Icons.search,
              title: '店名・住所で検索',
              subtitle: '国土地理院・OSMで場所を探す（無料）',
              onTap: () {
                Navigator.pop(context);
                _openSearch(context);
              },
            ),
            _AddOption(
              icon: Icons.touch_app_outlined,
              title: '地図上でピンを置く',
              subtitle: '登録されていない場所にも対応',
              onTap: () {
                Navigator.pop(context);
                _addFreePin(context);
              },
            ),
            _AddOption(
              icon: Icons.my_location,
              title: '現在地を追加',
              subtitle: '周辺のお店、または現在位置',
              onTap: () {
                Navigator.pop(context);
                _addCurrentLocation(context);
              },
            ),
            _AddOption(
              icon: Icons.link,
              title: 'SNSのURLを貼り付け',
              subtitle: '投稿から場所を抽出',
              onTap: () {
                Navigator.pop(context);
                _pasteUrl(context);
              },
            ),
            _AddOption(
              icon: Icons.edit_note_outlined,
              title: '投稿文を貼り付け',
              subtitle: 'テキストから場所を抽出',
              onTap: () {
                Navigator.pop(context);
                _pasteText(context);
              },
            ),
            _AddOption(
              icon: Icons.explore_outlined,
              title: '緯度・経度を指定',
              subtitle: '座標を直接入力してピンを追加',
              onTap: () {
                Navigator.pop(context);
                _addByCoordinates(context);
              },
            ),
            _AddOption(
              icon: Icons.image_outlined,
              title: '画像から探す',
              subtitle: '画像内の店名・住所を端末内で読み取る',
              onTap: () {
                Navigator.pop(context);
                _pickAndAnalyzeImage(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addByCoordinates(BuildContext context) async {
    final controller = AppScope.read(context);
    final nameController = TextEditingController();
    final latController = TextEditingController();
    final lngController = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('緯度・経度を指定'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(hintText: '場所の名前'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: latController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(hintText: '緯度（例: 35.6812）'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: lngController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    hintText: '経度（例: 139.7671）',
                  ),
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
      if (ok == true) {
        final lat = double.tryParse(latController.text.trim());
        final lng = double.tryParse(lngController.text.trim());
        final name = nameController.text.trim();
        if (name.isEmpty || lat == null || lng == null) {
          if (context.mounted) {
            showInfoSnackBar(context, '名前と有効な座標を入力してください');
          }
        } else if (context.mounted) {
          final place = await runGuarded(
            context,
            () => controller.runExclusive(() async {
              return controller.places.create(
                Place(
                  name: name,
                  latitude: lat,
                  longitude: lng,
                  category: '座標ピン',
                  saveReason: '緯度・経度を直接指定して追加',
                ),
                mapIds: [mapId],
              );
            }),
          );
          if (place != null) {
            onPlaceAdded?.call(place);
            if (context.mounted) {
              showInfoSnackBar(context, '「$name」を追加しました');
            }
          }
        }
      }
    } finally {
      disposeAfterFrame([nameController, latController, lngController]);
    }
  }

  Future<void> _openSearch(BuildContext context) async {
    final controller = AppScope.read(context);
    final hit = await showModalBottomSheet<PlaceSearchHit>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => const _PlaceSearchSheet(),
    );

    if (hit != null) {
      final place = await controller.places.create(
        Place(
          name: hit.name,
          address: hit.address,
          latitude: hit.latitude,
          longitude: hit.longitude,
          externalPlaceId: hit.externalPlaceId,
          saveReason: '店名検索から追加',
        ),
        mapIds: [mapId],
      );
      onPlaceAdded?.call(place);
      if (context.mounted) {
        showInfoSnackBar(context, '「${hit.name}」を追加しました');
      }
    }
  }

  Future<void> _addFreePin(BuildContext context) async {
    final controller = AppScope.read(context);
    final nameController = TextEditingController();
    final noteController = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('自由なピンを追加'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
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
      if (ok == true && nameController.text.trim().isNotEmpty) {
        await controller.places.create(
          Place(
            name: nameController.text.trim(),
            saveReason: noteController.text.trim(),
            latitude: 35.6812,
            longitude: 139.7671,
            mapPinX: 0.5,
            mapPinY: 0.5,
            category: '自由ピン',
          ),
          mapIds: [mapId],
        );
      }
    } finally {
      disposeAfterFrame([nameController, noteController]);
    }
  }

  Future<void> _addCurrentLocation(BuildContext context) async {
    final controller = AppScope.read(context);
    final located = await runGuarded(
      context,
      () => controller.deviceLocation.locateFast(),
    );
    if (located == null || !context.mounted) return;

    final created = await runGuarded(
      context,
      () => controller.places.create(
        Place(
          name: '現在地',
          saveReason: '現在地を保存',
          latitude: located.point.latitude,
          longitude: located.point.longitude,
          category: '現在地',
        ),
        mapIds: [mapId],
      ),
    );
    if (created != null) {
      onPlaceAdded?.call(created);
      if (context.mounted) {
        showInfoSnackBar(
          context,
          located.approximate ? 'おおよその現在地を追加しました' : '現在地を追加しました',
        );
      }
    }
  }

  Future<void> _pasteUrl(BuildContext context) async {
    final controller = AppScope.read(context);
    final textController = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('SNSのURLを貼り付け'),
          content: TextField(
            controller: textController,
            decoration: const InputDecoration(hintText: 'https://...'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('受信箱へ'),
            ),
          ],
        ),
      );
      if (ok == true && textController.text.trim().isNotEmpty) {
        await controller.shareIntake.ingest(
          SharedContent(url: textController.text.trim()),
        );
      }
    } finally {
      disposeAfterFrame([textController]);
    }
  }

  Future<void> _pasteText(BuildContext context) async {
    final controller = AppScope.read(context);
    final textController = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('投稿文を貼り付け'),
          content: SingleChildScrollView(
            child: TextField(
              controller: textController,
              maxLines: 5,
              decoration: const InputDecoration(hintText: '投稿の文章を貼り付け'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('受信箱へ'),
            ),
          ],
        ),
      );
      if (ok == true && textController.text.trim().isNotEmpty) {
        await controller.shareIntake.ingest(
          SharedContent(text: textController.text.trim(), service: 'テキスト'),
        );
      }
    } finally {
      disposeAfterFrame([textController]);
    }
  }

  Future<void> _pickAndAnalyzeImage(BuildContext context) async {
    final images = await ImagePicker().pickMultiImage(
      imageQuality: 92,
      limit: 10,
    );
    if (!context.mounted) return;
    final paths = images.map((image) => image.path).toList();
    if (paths.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('画像ファイルを読み込めませんでした')));
      return;
    }
    final controller = AppScope.read(context);
    await controller.shareIntake.ingest(
      SharedContent(service: 'スクリーンショット', title: '画像から追加', imagePaths: paths),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('画像を受信箱へ追加し、端末内で解析しています')));
    }
  }
}

class _PlaceSearchSheet extends StatefulWidget {
  const _PlaceSearchSheet();

  @override
  State<_PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<_PlaceSearchSheet> {
  final textController = TextEditingController();
  List<PlaceSearchHit> results = const [];
  bool searching = false;
  String? errorMessage;
  bool searched = false;

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = textController.text.trim();
    if (query.isEmpty) return;
    setState(() {
      searching = true;
      errorMessage = null;
      searched = true;
    });
    try {
      final hits = await AppScope.read(context).placeSearch.searchByName(query);
      if (!mounted) return;
      setState(() {
        results = hits;
        searching = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        results = const [];
        searching = false;
        errorMessage = toUserMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: modalSheetHeight(context, fraction: 0.78),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '場所を検索',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              '国土地理院・OpenStreetMap（無料）',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              autofocus: false,
              decoration: const InputDecoration(
                hintText: '例: 東京駅、京都市下京区…',
                prefixIcon: Icon(Icons.search),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: searching ? null : _search,
              child: Text(searching ? '検索中…' : '検索'),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: searching
                  ? const Center(child: CircularProgressIndicator())
                  : errorMessage != null
                  ? Center(
                      child: Text(errorMessage!, textAlign: TextAlign.center),
                    )
                  : results.isEmpty
                  ? Center(
                      child: Text(
                        searched
                            ? '候補が見つかりませんでした\n住所や駅名で試してみてください'
                            : 'キーワードを入力して検索',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    )
                  : ListView.separated(
                      itemCount: results.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final hit = results[i];
                        return ListTile(
                          title: Text(
                            hit.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: hit.address == null
                              ? null
                              : Text(
                                  hit.address!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onTap: () => Navigator.pop(context, hit),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddOption extends StatelessWidget {
  const _AddOption({
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
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: mint,
        foregroundColor: moss,
        child: Icon(icon),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
