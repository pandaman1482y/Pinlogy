import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../app/app_scope.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/feedback.dart';
import '../../widgets/map_tiles.dart';
import '../../widgets/place_map_view.dart';
import '../../widgets/source_post_tile.dart';

/// 場所の編集・詳細画面。
class PlaceDetailPage extends StatefulWidget {
  const PlaceDetailPage({super.key, required this.placeId});

  final String placeId;

  @override
  State<PlaceDetailPage> createState() => _PlaceDetailPageState();
}

class _PlaceDetailPageState extends State<PlaceDetailPage> {
  late final TextEditingController nameController;
  late final TextEditingController addressController;
  late final TextEditingController categoryController;
  late final TextEditingController memoController;
  late final TextEditingController reasonController;
  late final TextEditingController tagController;
  late final TextEditingController latController;
  late final TextEditingController lngController;
  VisitStatus visitStatus = VisitStatus.wantToGo;
  TimeOfDay? openingTime;
  TimeOfDay? closingTime;
  Set<int> closedWeekdays = {};
  bool saving = false;
  bool initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (initialized) return;
    final place = _place;
    if (place == null) return;
    nameController = TextEditingController(text: place.name);
    addressController = TextEditingController(text: place.address ?? '');
    categoryController = TextEditingController(text: place.category ?? '');
    memoController = TextEditingController(text: place.userMemo ?? '');
    reasonController = TextEditingController(text: place.saveReason ?? '');
    tagController = TextEditingController();
    latController = TextEditingController(
      text: place.latitude?.toString() ?? '',
    );
    lngController = TextEditingController(
      text: place.longitude?.toString() ?? '',
    );
    visitStatus = place.visitStatus;
    openingTime = _timeOfDay(place.openingTimeMinutes);
    closingTime = _timeOfDay(place.closingTimeMinutes);
    closedWeekdays = place.closedWeekdays.toSet();
    initialized = true;
  }

  Place? get _place {
    final controller = AppScope.of(context);
    try {
      return controller.hub.snapshot.places.firstWhere(
        (p) => p.id == widget.placeId,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    if (initialized) {
      nameController.dispose();
      addressController.dispose();
      categoryController.dispose();
      memoController.dispose();
      reasonController.dispose();
      tagController.dispose();
      latController.dispose();
      lngController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final place = _place;
    if (place == null || !initialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('詳細')),
        body: const Center(child: Text('場所が見つかりません')),
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
    final tags = controller.hub.snapshot.placeTags
        .where((pt) => pt.placeId == place.id)
        .map((pt) {
          try {
            return controller.hub.snapshot.tags.firstWhere(
              (t) => t.id == pt.tagId,
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<Tag>()
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '場所の詳細',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => _save(context, place),
            child: Text(saving ? '保存中…' : '保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SizedBox(
            height: 140,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: IgnorePointer(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: PlaceMapView.pointFor(place),
                    initialZoom: place.latitude == null ? 5.5 : 13,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    PinlogyMapTiles.buildLayer(),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: PlaceMapView.pointFor(place),
                          width: 36,
                          height: 36,
                          alignment: Alignment.topCenter,
                          child: const Icon(
                            Icons.place_rounded,
                            color: mossDeep,
                            size: 32,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: '正式名称 / スポット名'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: addressController,
            decoration: const InputDecoration(labelText: '住所'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: categoryController,
            decoration: const InputDecoration(labelText: 'カテゴリ'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _TimeTile(
                  label: '開店',
                  value: openingTime,
                  onTap: () async {
                    final value = await showTimePicker(
                      context: context,
                      initialTime:
                          openingTime ?? const TimeOfDay(hour: 10, minute: 0),
                    );
                    if (value != null) setState(() => openingTime = value);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TimeTile(
                  label: '閉店',
                  value: closingTime,
                  onTap: () async {
                    final value = await showTimePicker(
                      context: context,
                      initialTime:
                          closingTime ?? const TimeOfDay(hour: 20, minute: 0),
                    );
                    if (value != null) setState(() => closingTime = value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: List.generate(7, (index) {
              final weekday = index + 1;
              const labels = ['月', '火', '水', '木', '金', '土', '日'];
              return FilterChip(
                label: Text('${labels[index]}休'),
                selected: closedWeekdays.contains(weekday),
                onSelected: (selected) => setState(() {
                  if (selected) {
                    closedWeekdays.add(weekday);
                  } else {
                    closedWeekdays.remove(weekday);
                  }
                }),
              );
            }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<VisitStatus>(
            initialValue: visitStatus,
            decoration: const InputDecoration(labelText: '訪問状態'),
            items: VisitStatus.values
                .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => visitStatus = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: reasonController,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '保存した理由'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: memoController,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'ユーザーメモ'),
          ),
          const SizedBox(height: 16),
          const Text('タグ', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...tags.map(
                (t) => InputChip(
                  label: Text(t.name),
                  onDeleted: () async {
                    await controller.tags.removeTagFromPlace(
                      placeId: place.id,
                      tagId: t.id,
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: tagController,
                  decoration: const InputDecoration(hintText: 'タグを追加'),
                  onSubmitted: (_) => _addTag(context, place),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: () => _addTag(context, place),
                child: const Text('追加'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('所属マップ', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...maps.map(
                (m) => InputChip(
                  label: Text('${m.icon} ${m.name}'),
                  onDeleted: maps.length <= 1
                      ? null
                      : () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('マップから外しますか？'),
                              content: Text('「${m.name}」からのみ外します。場所自体は残ります。'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('キャンセル'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('外す'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) {
                            await controller.places.removeFromMap(
                              placeId: place.id,
                              mapId: m.id,
                            );
                          }
                        },
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('マップに追加'),
                onPressed: () => _addToMap(context, place, maps),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('座標', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: latController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(labelText: '緯度'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: lngController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(labelText: '経度'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _info('訪問回数', '${place.visitCount}'),
          _info('初回訪問', place.firstVisitedAt?.toLocal().toString() ?? '—'),
          _info('最終訪問', place.lastVisitedAt?.toLocal().toString() ?? '—'),
          _info('Place ID', place.externalPlaceId ?? '未設定'),
          _info('登録日時', place.createdAt.toLocal().toString()),
          _info('更新日時', place.updatedAt.toLocal().toString()),
          const SizedBox(height: 20),
          Text('元の投稿', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final posts = controller.sourcesForPlace(place.id);
              if (posts.isEmpty) {
                return Text(
                  '関連投稿なし',
                  style: TextStyle(color: Colors.grey.shade600),
                );
              }
              return Column(
                children: posts
                    .map(
                      (post) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SourcePostTile(post: post),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: saving ? null : () => _save(context, place),
            child: Text(saving ? '保存中…' : '変更を保存'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () async {
              await controller.visits.markVisited(place.id);
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('訪問済みにしました')));
              }
            },
            child: const Text('行った（訪問回数+1）'),
          ),
        ],
      ),
    );
  }

  Future<void> _addTag(BuildContext context, Place place) async {
    final name = tagController.text.trim();
    if (name.isEmpty) return;
    final controller = AppScope.read(context);
    final current = await controller.tags.tagsForPlace(place.id);
    final names = {...current.map((t) => t.name), name}.toList();
    await controller.tags.setPlaceTags(placeId: place.id, tagNames: names);
    tagController.clear();
  }

  Future<void> _addToMap(
    BuildContext context,
    Place place,
    List<PinMap> currentMaps,
  ) async {
    final controller = AppScope.read(context);
    final candidates = controller.hub.snapshot.maps
        .where((m) => !currentMaps.any((c) => c.id == m.id))
        .toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('追加できるマップがありません')));
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '追加先マップ',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            ...candidates.map(
              (m) => ListTile(
                title: Text('${m.icon} ${m.name}'),
                onTap: () => Navigator.pop(ctx, m.id),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null) {
      await controller.places.addToMap(placeId: place.id, mapId: selected);
    }
  }

  Future<void> _save(BuildContext context, Place place) async {
    if (saving) return;
    setState(() => saving = true);
    final controller = AppScope.read(context);
    try {
      final lat = double.tryParse(latController.text.trim());
      final lng = double.tryParse(lngController.text.trim());
      await controller.places.update(
        place.copyWith(
          name: nameController.text.trim().isEmpty
              ? place.name
              : nameController.text.trim(),
          address: addressController.text.trim(),
          category: categoryController.text.trim(),
          userMemo: memoController.text.trim(),
          saveReason: reasonController.text.trim(),
          visitStatus: visitStatus,
          latitude: lat ?? place.latitude,
          longitude: lng ?? place.longitude,
          openingTimeMinutes: _minutes(openingTime),
          closingTimeMinutes: _minutes(closingTime),
          closedWeekdays: closedWeekdays.toList()..sort(),
        ),
      );
      if (visitStatus != place.visitStatus) {
        await controller.visits.setStatus(place.id, visitStatus);
      }
      if (context.mounted) {
        showInfoSnackBar(context, '保存しました');
      }
    } catch (error) {
      if (context.mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  TimeOfDay? _timeOfDay(int? minutes) => minutes == null
      ? null
      : TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

  int? _minutes(TimeOfDay? value) =>
      value == null ? null : value.hour * 60 + value.minute;

  Widget _info(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: TextStyle(color: Colors.grey.shade600)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final TimeOfDay? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.schedule_rounded),
      ),
      child: Text(value?.format(context) ?? '未設定'),
    ),
  );
}
