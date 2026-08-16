import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../app/app_scope.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/directions_service.dart';
import '../../services/in_app_route_service.dart';
import '../../services/route_privacy_consent.dart';
import '../../services/source_link_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/feedback.dart';
import '../../widgets/place_map_view.dart';
import '../../widgets/place_photo.dart';
import '../../widgets/sheet_layout.dart';

class PlanDetailPage extends StatelessWidget {
  const PlanDetailPage({super.key, required this.planId});

  final String planId;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    TripPlan? plan;
    for (final p in controller.hub.snapshot.plans) {
      if (p.id == planId) {
        plan = p;
        break;
      }
    }
    if (plan == null) {
      return PinlogyBackdrop(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(title: const Text('プラン')),
          body: const EmptyState(
            icon: Icons.route_rounded,
            title: 'プランが見つかりません',
            message: '削除されたか、読み込めませんでした。',
          ),
        ),
      );
    }

    final stops =
        controller.hub.snapshot.planStops
            .where((s) => s.planId == planId)
            .toList()
          ..sort((a, b) {
            final day = _compareNullableDay(a.dayDate, b.dayDate);
            if (day != 0) return day;
            return a.sortOrder.compareTo(b.sortOrder);
          });

    final days = <DateTime?>[];
    for (final stop in stops) {
      if (!days.any((d) => _sameDay(d, stop.dayDate))) {
        days.add(stop.dayDate);
      }
    }
    if (days.isEmpty && plan.startDate != null) {
      days.add(PlanStop.dateOnly(plan.startDate!));
    }

    return PinlogyBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(plan.title),
          actions: [
            if (stops.isNotEmpty)
              IconButton(
                tooltip: 'プランマップを表示',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlanMapPage(planId: planId),
                  ),
                ),
                icon: const Icon(Icons.map_outlined),
              ),
            IconButton(
              tooltip: '日を追加',
              onPressed: () => _addDay(context, plan!),
              icon: const Icon(Icons.calendar_month_rounded),
            ),
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'edit') {
                  await _editPlan(context, plan!);
                } else if (value == 'delete') {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('プランを削除しますか？'),
                      content: Text('「${plan!.title}」を削除します。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('キャンセル'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text(
                            '削除',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (ok == true && context.mounted) {
                    final deleted = await runGuardedAction(
                      context,
                      () => AppScope.read(context).plans.delete(planId),
                    );
                    if (deleted && context.mounted) Navigator.pop(context);
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('プランを編集')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('削除', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: days.isEmpty
              ? () => _addDay(context, plan!)
              : () => _addStop(context, planId, days.last),
          icon: Icon(
            days.isEmpty
                ? Icons.calendar_today_rounded
                : Icons.add_location_alt_rounded,
          ),
          label: Text(days.isEmpty ? '日付を決める' : '場所を追加'),
        ),
        body: days.isEmpty
            ? EmptyState(
                icon: Icons.route_rounded,
                title: 'まだ行程がない',
                message: '日付はあとからでも大丈夫。\nまずは行きたい場所を足してみよう。',
                action: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton(
                      onPressed: () => _addDay(context, plan!),
                      child: const Text('日付を追加'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => _addStop(context, planId, null),
                      child: const Text('日付なしで場所を追加'),
                    ),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 120),
                children: [
                  _PlanMapCard(
                    stopCount: stops.length,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlanMapPage(planId: planId),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (plan.notes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        plan.notes,
                        style: TextStyle(
                          color: ink.withValues(alpha: 0.55),
                          height: 1.45,
                        ),
                      ),
                    ),
                  for (final day in days) ...[
                    _DayHeader(
                      day: day,
                      totalMinutes: _dayTotalMinutes(
                        stops.where((s) => _sameDay(s.dayDate, day)).toList(),
                      ),
                      onNavigate:
                          stops.where((s) => _sameDay(s.dayDate, day)).length >=
                              2
                          ? () => _openDayInExternalNavigation(
                              context,
                              stops
                                  .where((s) => _sameDay(s.dayDate, day))
                                  .toList(),
                            )
                          : null,
                      onAddStop: () => _addStop(context, planId, day),
                    ),
                    const SizedBox(height: 10),
                    _DayTimeline(
                      planId: planId,
                      day: day,
                      startTimeMinutes: plan.startTimeMinutes,
                      stops: stops
                          .where((s) => _sameDay(s.dayDate, day))
                          .toList(),
                    ),
                    const SizedBox(height: 22),
                  ],
                ],
              ),
      ),
    );
  }

  static bool _sameDay(DateTime? a, DateTime? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return PlanStop.dateOnly(a) == PlanStop.dateOnly(b);
  }

  static int _compareNullableDay(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }

  static int _dayTotalMinutes(List<PlanStop> stops) {
    var total = 0;
    for (var i = 0; i < stops.length; i++) {
      total += stops[i].stayMinutes ?? 0;
      if (i < stops.length - 1) {
        total += stops[i].transitMinutes ?? 0;
      }
    }
    return total;
  }

  static Future<void> _addDay(BuildContext context, TripPlan plan) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: plan.startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !context.mounted) return;
    final day = PlanStop.dateOnly(picked);
    final controller = AppScope.read(context);
    if (plan.startDate == null || day.isBefore(plan.startDate!)) {
      await runGuardedAction(
        context,
        () => controller.plans.update(plan.copyWith(startDate: day)),
      );
    }
    if (!context.mounted) return;
    await _addStop(context, plan.id, day);
  }

  static Future<void> _editPlan(BuildContext context, TripPlan plan) async {
    final titleController = TextEditingController(text: plan.title);
    final notesController = TextEditingController(text: plan.notes);
    var startTimeMinutes = plan.startTimeMinutes;
    try {
      final ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding: EdgeInsets.fromLTRB(
              22,
              22,
              22,
              MediaQuery.viewInsetsOf(ctx).bottom + 22,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'プランを編集',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(hintText: 'プラン名'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(hintText: 'メモ'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.schedule_rounded),
                    label: Text('1日の開始時刻  ${_timeLabel(startTimeMinutes)}'),
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay(
                          hour: startTimeMinutes ~/ 60,
                          minute: startTimeMinutes % 60,
                        ),
                      );
                      if (picked != null) {
                        setSheetState(() {
                          startTimeMinutes = picked.hour * 60 + picked.minute;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () {
                      if (titleController.text.trim().isEmpty) return;
                      Navigator.pop(ctx, true);
                    },
                    child: const Text('保存'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final title = titleController.text.trim();
      final notes = notesController.text.trim();
      if (ok != true || !context.mounted) return;
      await runGuardedAction(
        context,
        () => AppScope.read(context).plans.update(
          plan.copyWith(
            title: title,
            notes: notes,
            startTimeMinutes: startTimeMinutes,
          ),
        ),
      );
    } finally {
      disposeAfterFrame([titleController, notesController]);
    }
  }

  static String _timeLabel(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  static Future<void> _addStop(
    BuildContext context,
    String planId,
    DateTime? day,
  ) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!context.mounted) return;
    final controller = AppScope.read(context);
    final places = List<Place>.of(controller.hub.snapshot.places)
      ..sort((a, b) => a.name.compareTo(b.name));
    if (places.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('先にマップへ場所を保存してください')));
      return;
    }

    final tagEntries = await Future.wait(
      places.map(
        (place) async => MapEntry(
          place.id,
          (await controller.tags.tagsForPlace(
            place.id,
          )).map((tag) => tag.name).toList(),
        ),
      ),
    );
    if (!context.mounted) return;
    final tagsByPlace = Map<String, List<String>>.fromEntries(tagEntries);
    final genres =
        places
            .expand(
              (place) => [
                if (place.category?.trim().isNotEmpty == true)
                  place.category!.trim(),
                ...(tagsByPlace[place.id] ?? const <String>[]),
              ],
            )
            .where((label) => !_broadPlaceCategories.contains(label))
            .toSet()
            .toList()
          ..sort();

    String query = '';
    String scope = 'all';
    String? genre;
    final selected = await showModalBottomSheet<Place>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = places.where((p) {
              final labels = <String>[
                if (p.category != null) p.category!,
                ...(tagsByPlace[p.id] ?? const <String>[]),
              ];
              final matchesQuery =
                  query.isEmpty ||
                  p.name.toLowerCase().contains(query.toLowerCase()) ||
                  (p.address?.toLowerCase().contains(query.toLowerCase()) ??
                      false) ||
                  labels.any(
                    (label) =>
                        label.toLowerCase().contains(query.toLowerCase()),
                  );
              final isFood = _isFoodPlace(p, labels);
              final matchesScope =
                  scope == 'all' ||
                  (scope == 'food' && isFood) ||
                  (scope == 'spot' && !isFood);
              final matchesGenre = genre == null || labels.contains(genre);
              return matchesQuery && matchesScope && matchesGenre;
            }).toList();
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
                      Text(
                        '場所を選ぶ',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        autofocus: false,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: '店名・住所',
                        ),
                        onChanged: (v) => setModalState(() => query = v),
                      ),
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final option in const [
                              ('all', 'すべて'),
                              ('food', 'グルメ'),
                              ('spot', '観光・おでかけ'),
                            ]) ...[
                              FilterChip(
                                label: Text(option.$2),
                                selected: scope == option.$1,
                                onSelected: (_) => setModalState(() {
                                  scope = option.$1;
                                  genre = null;
                                }),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                      if (genres.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              FilterChip(
                                label: const Text('種類すべて'),
                                selected: genre == null,
                                onSelected: (_) =>
                                    setModalState(() => genre = null),
                              ),
                              const SizedBox(width: 8),
                              for (final label in genres) ...[
                                FilterChip(
                                  label: Text(label),
                                  selected: genre == label,
                                  onSelected: (_) =>
                                      setModalState(() => genre = label),
                                ),
                                const SizedBox(width: 8),
                              ],
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Expanded(
                        child: filtered.isEmpty
                            ? const Center(child: Text('条件に合う場所がありません'))
                            : ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (context, index) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, i) {
                                  final place = filtered[i];
                                  final labels = <String>[
                                    if (place.category?.isNotEmpty == true)
                                      place.category!,
                                    ...(tagsByPlace[place.id] ??
                                        const <String>[]),
                                  ];
                                  final detail = [
                                    if (labels.isNotEmpty) labels.join('・'),
                                    if (place.address?.isNotEmpty == true)
                                      place.address!,
                                  ].join('\n');
                                  return ListTile(
                                    title: Text(
                                      place.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: detail.isEmpty
                                        ? null
                                        : Text(
                                            detail,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                    onTap: () => Navigator.pop(ctx, place),
                                  );
                                },
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
    if (selected == null || !context.mounted) return;
    await runGuarded(
      context,
      () => controller.plans.addStop(
        PlanStop(
          planId: planId,
          placeId: selected.id,
          dayDate: day,
          stayMinutes: 60,
        ),
      ),
    );
  }

  static const _broadPlaceCategories = {'飲食店', '観光・レジャー', '宿泊', '買い物', 'その他'};

  static bool _isFoodPlace(Place place, List<String> labels) {
    final text = '${place.name} ${labels.join(' ')}';
    return RegExp(
      r'飲食|グルメ|カフェ|喫茶|コーヒー|スイーツ|菓子|ラーメン|つけ麺|寿司|鮨|焼肉|居酒屋|和食|洋食|イタリアン|中華|カレー|パン|レストラン|食堂|うどん|そば',
    ).hasMatch(text);
  }

  Future<void> _openDayInExternalNavigation(
    BuildContext context,
    List<PlanStop> stops,
  ) async {
    final controller = AppScope.read(context);
    final placesById = {
      for (final place in controller.hub.snapshot.places) place.id: place,
    };
    final places = stops
        .map((stop) => placesById[stop.placeId])
        .whereType<Place>()
        .toList();
    if (places.length < 2) {
      showInfoSnackBar(context, '経路に使える場所が2件以上必要です');
      return;
    }
    if (places.length > DirectionsService.maxExternalStops) {
      showInfoSnackBar(
        context,
        '外部ナビには先頭から${DirectionsService.maxExternalStops}件を渡します',
      );
    }
    final opened = await controller.directions.openMultiStopDirections(places);
    if (!opened && context.mounted) {
      showInfoSnackBar(context, '外部ナビを開けませんでした');
    }
  }
}

class _PlanMapCard extends StatelessWidget {
  const _PlanMapCard({required this.stopCount, required this.onTap});

  final int stopCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: mintSoft,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: mint,
              foregroundColor: mossDeep,
              child: Icon(Icons.map_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'プランマップ',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text('$stopCount件の場所を地図で確認'),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    ),
  );
}

/// プランの行程から常に最新の地図を生成する画面。
class PlanMapPage extends StatefulWidget {
  const PlanMapPage({super.key, required this.planId});

  final String planId;

  @override
  State<PlanMapPage> createState() => _PlanMapPageState();
}

class _PlanMapPageState extends State<PlanMapPage> {
  final MapController _mapController = MapController();
  DateTime? _selectedDay;
  bool _showAllDays = true;
  final Map<String, InAppRoute> _routesByStopId = {};
  bool _loadingRoutes = false;
  String? _routeNotice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRoutes());
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final plan = controller.hub.snapshot.plans
        .where((item) => item.id == widget.planId)
        .firstOrNull;
    final allStops =
        controller.hub.snapshot.planStops
            .where((stop) => stop.planId == widget.planId)
            .toList()
          ..sort((a, b) {
            final day = PlanDetailPage._compareNullableDay(
              a.dayDate,
              b.dayDate,
            );
            return day != 0 ? day : a.sortOrder.compareTo(b.sortOrder);
          });
    final days = <DateTime?>[];
    for (final stop in allStops) {
      if (!days.any((day) => PlanDetailPage._sameDay(day, stop.dayDate))) {
        days.add(stop.dayDate);
      }
    }
    final visibleStops = _showAllDays
        ? allStops
        : allStops
              .where(
                (stop) => PlanDetailPage._sameDay(stop.dayDate, _selectedDay),
              )
              .toList();
    final placeById = {
      for (final place in controller.hub.snapshot.places) place.id: place,
    };
    final places = visibleStops
        .map((stop) => placeById[stop.placeId])
        .whereType<Place>()
        .toList();
    final nextPlace =
        places.where((place) => !place.isVisited).firstOrNull ??
        places.firstOrNull;
    final markerLabels = <String, String>{};
    for (var i = 0; i < places.length; i++) {
      markerLabels[places[i].id] = '${i + 1}';
    }
    final routeLines = <Polyline>[];
    for (var i = 0; i < visibleStops.length - 1; i++) {
      final route = _routesByStopId[visibleStops[i].id];
      final from = placeById[visibleStops[i].placeId];
      final to = placeById[visibleStops[i + 1].placeId];
      final sameDay = _sameRouteDay(visibleStops[i], visibleStops[i + 1]);
      final points = !sameDay
          ? const <LatLng>[]
          : route?.points ??
                (from?.latitude != null &&
                        from?.longitude != null &&
                        to?.latitude != null &&
                        to?.longitude != null
                    ? [
                        LatLng(from!.latitude!, from.longitude!),
                        LatLng(to!.latitude!, to.longitude!),
                      ]
                    : const <LatLng>[]);
      if (points.length >= 2) {
        routeLines.add(
          Polyline(
            points: points,
            strokeWidth: route == null ? 4 : 6,
            color: route == null
                ? _routeColor(
                    visibleStops[i].transitToNext,
                  ).withValues(alpha: .58)
                : _routeColor(visibleStops[i].transitToNext),
            pattern: route == null
                ? const StrokePattern.dotted()
                : const StrokePattern.solid(),
          ),
        );
      }
    }

    return PinlogyBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(plan == null ? 'プランマップ' : '${plan.title}の地図'),
          actions: [
            IconButton(
              tooltip: '区間経路を更新',
              onPressed: _loadingRoutes ? null : _loadRoutes,
              icon: _loadingRoutes
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
            ),
            if (places.length >= 2)
              IconButton(
                tooltip: '外部マップを設定して開く',
                icon: const Icon(Icons.route_rounded),
                onPressed: () => _openExternalOptions(places),
              ),
          ],
        ),
        body: places.isEmpty
            ? const EmptyState(
                icon: Icons.map_outlined,
                title: '地図に表示できる場所がありません',
                message: 'プランへ場所を追加すると、自動で地図が生成されます。',
              )
            : Column(
                children: [
                  if (days.length > 1)
                    SizedBox(
                      height: 54,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 7,
                        ),
                        children: [
                          ChoiceChip(
                            label: const Text('全日程'),
                            selected: _showAllDays,
                            onSelected: (_) => setState(() {
                              _showAllDays = true;
                              _selectedDay = null;
                            }),
                          ),
                          const SizedBox(width: 8),
                          for (final day in days) ...[
                            ChoiceChip(
                              label: Text(_dayLabel(day)),
                              selected:
                                  !_showAllDays &&
                                  PlanDetailPage._sameDay(_selectedDay, day),
                              onSelected: (_) => setState(() {
                                _showAllDays = false;
                                _selectedDay = day;
                              }),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                  Expanded(
                    child: Stack(
                      children: [
                        PlaceMapView(
                          key: ValueKey(
                            '${_showAllDays ? 'all' : _selectedDay}:'
                            '${places.map((place) => place.id).join(',')}',
                          ),
                          places: places,
                          mapController: _mapController,
                          mapId: 'plan:${widget.planId}',
                          routePolylines: routeLines,
                          markerLabels: markerLabels,
                          clusterMarkers: false,
                          focusPlaceId: nextPlace?.id,
                        ),
                        if (_routeNotice != null)
                          Positioned(
                            top: 12,
                            left: 14,
                            right: 14,
                            child: Material(
                              color: Colors.white.withValues(alpha: .94),
                              borderRadius: BorderRadius.circular(14),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Text(
                                  _routeNotice!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          left: 14,
                          right: 14,
                          bottom: 14,
                          child: _PlanOrderBar(
                            stops: visibleStops,
                            placeById: placeById,
                            routesByStopId: _routesByStopId,
                          ),
                        ),
                        if (nextPlace != null)
                          Positioned(
                            right: 14,
                            bottom: 142,
                            child: FloatingActionButton.extended(
                              heroTag: 'plan-next-${widget.planId}',
                              onPressed: () => _openNextPlace(nextPlace),
                              icon: const Icon(Icons.navigation_rounded),
                              label: const Text('次の場所へ'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  String _dayLabel(DateTime? day) =>
      day == null ? '日付未定' : '${day.month}/${day.day}';

  Future<void> _loadRoutes() async {
    if (!mounted) return;
    final controller = AppScope.read(context);
    if (!controller.inAppRoutes.isConfigured) {
      setState(() => _routeNotice = '点線は概略経路です。経路API設定後は道路に沿って表示します。');
      return;
    }
    var allowed = await RoutePrivacyConsent().hasConsented();
    if (!allowed && mounted) {
      allowed =
          await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(Icons.privacy_tip_outlined),
              title: const Text('区間経路を取得'),
              content: const Text('道路に沿った経路と所要時間を計算するため、各地点の座標を経路サービスへ送信します。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('概略表示を使う'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('同意して取得'),
                ),
              ],
            ),
          ) ??
          false;
      if (allowed) await RoutePrivacyConsent().grant();
    }
    if (!allowed || !mounted) return;
    setState(() {
      _loadingRoutes = true;
      _routeNotice = null;
    });
    final snapshot = controller.hub.snapshot;
    final stops =
        snapshot.planStops
            .where((stop) => stop.planId == widget.planId)
            .toList()
          ..sort((a, b) {
            final day = PlanDetailPage._compareNullableDay(
              a.dayDate,
              b.dayDate,
            );
            return day != 0 ? day : a.sortOrder.compareTo(b.sortOrder);
          });
    final places = {for (final place in snapshot.places) place.id: place};
    var failures = 0;
    var approximate = 0;
    for (var i = 0; i < stops.length - 1; i++) {
      final from = places[stops[i].placeId];
      final to = places[stops[i + 1].placeId];
      if (from?.latitude == null ||
          from?.longitude == null ||
          to?.latitude == null ||
          to?.longitude == null ||
          !_sameRouteDay(stops[i], stops[i + 1])) {
        continue;
      }
      final mode = _routeMode(stops[i].transitToNext);
      if (mode == null) {
        approximate++;
        continue;
      }
      try {
        final route = await controller.inAppRoutes.route(
          origin: LatLng(from!.latitude!, from.longitude!),
          destination: LatLng(to!.latitude!, to.longitude!),
          mode: mode,
        );
        _routesByStopId[stops[i].id] = route;
        final estimatedMinutes = (route.durationSeconds / 60).ceil();
        if (!stops[i].transitTimeIsManual &&
            stops[i].transitMinutes != estimatedMinutes) {
          await controller.plans.updateStop(
            stops[i].copyWith(
              transitMinutes: estimatedMinutes,
              transitTimeIsManual: false,
            ),
          );
        }
      } catch (_) {
        failures++;
      }
    }
    if (mounted) {
      setState(() {
        _loadingRoutes = false;
        final unresolved = failures + approximate;
        _routeNotice = unresolved == 0
            ? null
            : '$unresolved区間は概略経路で表示しています。公共交通は外部マップで確認できます。';
      });
    }
  }

  bool _sameRouteDay(PlanStop a, PlanStop b) =>
      PlanDetailPage._sameDay(a.dayDate, b.dayDate);

  RouteTravelMode? _routeMode(TransitMode? mode) => switch (mode) {
    TransitMode.walk => RouteTravelMode.walking,
    TransitMode.bike => RouteTravelMode.cycling,
    TransitMode.car || TransitMode.taxi || null => RouteTravelMode.driving,
    TransitMode.train || TransitMode.bus || TransitMode.other => null,
  };

  Color _routeColor(TransitMode? mode) => switch (mode) {
    TransitMode.walk => const Color(0xFF32A06A),
    TransitMode.train => const Color(0xFF7656C9),
    TransitMode.bus => const Color(0xFFE08B31),
    TransitMode.bike => const Color(0xFF20A4B8),
    TransitMode.car => const Color(0xFF3977D5),
    TransitMode.taxi => const Color(0xFFF2B134),
    TransitMode.other || null => const Color(0xFF6B7771),
  };

  Future<void> _openNextPlace(Place place) async {
    final opened = await AppScope.read(
      context,
    ).directions.openDirections(place);
    if (!opened && mounted) showInfoSnackBar(context, '次の場所を外部マップで開けませんでした');
  }

  Future<void> _openExternalOptions(List<Place> places) async {
    var app = DirectionsApp.googleMaps;
    var mode = 'driving';
    var startAtFirst = true;
    final open = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '外部マップの設定',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              SegmentedButton<DirectionsApp>(
                segments: const [
                  ButtonSegment(
                    value: DirectionsApp.googleMaps,
                    label: Text('Google Maps'),
                  ),
                  ButtonSegment(
                    value: DirectionsApp.appleMaps,
                    label: Text('Apple Maps'),
                  ),
                ],
                selected: {app},
                onSelectionChanged: (value) =>
                    setModalState(() => app = value.first),
              ),
              if (app == DirectionsApp.appleMaps)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Apple Mapsではプランの出発地と最終目的地を開きます。区間ごとの案内は区間詳細から開けます。',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: mode,
                decoration: const InputDecoration(labelText: '移動手段'),
                items: const [
                  DropdownMenuItem(value: 'driving', child: Text('車')),
                  DropdownMenuItem(value: 'walking', child: Text('徒歩')),
                  DropdownMenuItem(value: 'bicycling', child: Text('自転車')),
                  DropdownMenuItem(value: 'transit', child: Text('公共交通')),
                ],
                onChanged: (value) => setModalState(() => mode = value ?? mode),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('最初の場所から案内を開始'),
                subtitle: const Text('OFFの場合は現在地から開始します'),
                value: startAtFirst,
                onChanged: (value) => setModalState(() => startAtFirst = value),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.navigation_rounded),
                label: const Text('外部マップで開く'),
              ),
            ],
          ),
        ),
      ),
    );
    if (open != true || !mounted) return;
    final opened = await AppScope.read(context).directions
        .openMultiStopDirections(
          places,
          travelMode: mode,
          preferred: app,
          startAtFirstPlace: startAtFirst,
        );
    if (!opened && mounted) showInfoSnackBar(context, '外部マップを開けませんでした');
  }
}

class _PlanOrderBar extends StatelessWidget {
  const _PlanOrderBar({
    required this.stops,
    required this.placeById,
    required this.routesByStopId,
  });

  final List<PlanStop> stops;
  final Map<String, Place> placeById;
  final Map<String, InAppRoute> routesByStopId;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxHeight: 120),
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .94),
      borderRadius: BorderRadius.circular(18),
      boxShadow: const [
        BoxShadow(
          color: Color(0x22000000),
          blurRadius: 14,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: stops.length,
      separatorBuilder: (_, _) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child: Icon(Icons.arrow_forward_rounded, size: 17, color: moss),
      ),
      itemBuilder: (context, index) {
        final place = placeById[stops[index].placeId];
        final nextPlace = index < stops.length - 1
            ? placeById[stops[index + 1].placeId]
            : null;
        final route = routesByStopId[stops[index].id];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: index >= stops.length - 1
              ? null
              : () => _showSegment(
                  context,
                  stops[index],
                  place,
                  nextPlace,
                  route,
                ),
          child: SizedBox(
            width: 104,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: mossDeep,
                  foregroundColor: Colors.white,
                  child: Text('${index + 1}'),
                ),
                const SizedBox(height: 5),
                Text(
                  place?.name ?? '削除された場所',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (index < stops.length - 1)
                  Text(
                    stops[index].transitTimeIsManual || route == null
                        ? '${stops[index].transitToNext?.label ?? '移動'} ${stops[index].transitMinutes ?? '--'}分'
                        : '${stops[index].transitToNext?.label ?? '移動'} 約${(route.durationSeconds / 60).ceil()}分',
                    style: TextStyle(
                      fontSize: 10,
                      color: ink.withValues(alpha: .55),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );

  static Future<void> _showSegment(
    BuildContext context,
    PlanStop stop,
    Place? place,
    Place? nextPlace,
    InAppRoute? route,
  ) async {
    var mode = stop.transitToNext ?? TransitMode.walk;
    var minutes =
        stop.transitMinutes ??
        (route == null ? 15 : (route.durationSeconds / 60).ceil());
    final minutesController = TextEditingController(text: '$minutes');
    try {
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setModalState) => Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              4,
              20,
              MediaQuery.viewInsetsOf(context).bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${place?.name ?? 'この場所'}から次の場所へ',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    route == null
                        ? '移動手段と予定所要時間を編集できます'
                        : '経路の目安 約${(route.durationSeconds / 60).ceil()}分・${(route.distanceMeters / 1000).toStringAsFixed(1)}km',
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<TransitMode>(
                    initialValue: mode,
                    decoration: const InputDecoration(
                      labelText: '移動手段',
                      prefixIcon: Icon(Icons.commute_rounded),
                    ),
                    items: [
                      for (final value in TransitMode.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setModalState(() => mode = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: minutesController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '所要時間',
                            suffixText: '分',
                            prefixIcon: Icon(Icons.schedule_rounded),
                          ),
                          onChanged: (value) {
                            final parsed = int.tryParse(value);
                            if (parsed != null) {
                              minutes = parsed.clamp(1, 1440).toInt();
                            }
                          },
                        ),
                      ),
                      if (route != null) ...[
                        const SizedBox(width: 10),
                        TextButton(
                          onPressed: () => setModalState(() {
                            minutes = (route.durationSeconds / 60).ceil();
                            minutesController.text = '$minutes';
                          }),
                          child: const Text('経路時間を使う'),
                        ),
                      ],
                    ],
                  ),
                  if (route?.steps.isNotEmpty == true) ...[
                    const SizedBox(height: 14),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: route!.steps.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, index) {
                          final step = route.steps[index];
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 13,
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            title: Text(step.instruction),
                            trailing: Text('${step.distanceMeters.round()}m'),
                          );
                        },
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    const Text('実経路を取得できない区間は、予定時間と概略線で表示します。'),
                  ],
                  if (place != null && nextPlace != null) ...[
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () async {
                        final opened = await AppScope.read(context).directions
                            .openMultiStopDirections(
                              [place, nextPlace],
                              travelMode: _externalMode(mode),
                              startAtFirstPlace: true,
                            );
                        if (!opened && context.mounted) {
                          showInfoSnackBar(context, 'この区間を外部マップで開けませんでした');
                        }
                      },
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('この区間を外部マップで開く'),
                    ),
                  ],
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('移動内容を保存'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (saved == true && context.mounted) {
        await runGuardedAction(
          context,
          () => AppScope.read(context).plans.updateStop(
            stop.copyWith(
              transitToNext: mode,
              transitMinutes: minutes,
              transitTimeIsManual: true,
            ),
          ),
        );
      }
    } finally {
      disposeAfterFrame([minutesController]);
    }
  }

  static String _externalMode(TransitMode? mode) => switch (mode) {
    TransitMode.walk => 'walking',
    TransitMode.bike => 'bicycling',
    TransitMode.train || TransitMode.bus => 'transit',
    _ => 'driving',
  };
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.day,
    required this.totalMinutes,
    required this.onAddStop,
    this.onNavigate,
  });

  final DateTime? day;
  final int totalMinutes;
  final VoidCallback onAddStop;
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context) {
    final durationLabel = totalMinutes == 0
        ? '想定時間なし'
        : () {
            final hours = totalMinutes ~/ 60;
            final mins = totalMinutes % 60;
            if (hours == 0) return '想定 $mins分';
            if (mins == 0) return '想定 $hours時間';
            return '想定 $hours時間$mins分';
          }();

    final title = day == null
        ? '日付未定'
        : () {
            final weekday = [
              '月',
              '火',
              '水',
              '木',
              '金',
              '土',
              '日',
            ][day!.weekday - 1];
            return '${day!.year}/${day!.month}/${day!.day}（$weekday）';
          }();

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                durationLabel,
                style: TextStyle(
                  color: ink.withValues(alpha: 0.5),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (onNavigate != null)
          SoftIconButton(
            icon: Icons.route_rounded,
            tooltip: 'この日の経由地を外部ナビで開く',
            onPressed: onNavigate!,
          ),
        SoftIconButton(
          icon: Icons.add_rounded,
          tooltip: 'この日に場所を追加',
          onPressed: onAddStop,
        ),
      ],
    );
  }
}

class _DayTimeline extends StatelessWidget {
  const _DayTimeline({
    required this.planId,
    required this.day,
    required this.stops,
    required this.startTimeMinutes,
  });

  final String planId;
  final DateTime? day;
  final List<PlanStop> stops;
  final int startTimeMinutes;

  @override
  Widget build(BuildContext context) {
    if (stops.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          'まだ場所がありません',
          style: TextStyle(color: ink.withValues(alpha: 0.45)),
        ),
      );
    }

    final placeById = {
      for (final p in AppScope.of(context).hub.snapshot.places) p.id: p,
    };

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: stops.length,
      onReorderItem: (oldIndex, newIndex) async {
        final target = newIndex;
        final ordered = List<PlanStop>.of(stops);
        final item = ordered.removeAt(oldIndex);
        ordered.insert(target, item);
        await runGuardedAction(
          context,
          () => AppScope.read(context).plans.reorderStops(
            planId: planId,
            dayDate: day,
            orderedStopIds: ordered.map((s) => s.id).toList(),
          ),
        );
      },
      itemBuilder: (context, index) {
        final stop = stops[index];
        var arrivalMinutes = startTimeMinutes;
        for (var i = 0; i < index; i++) {
          final scheduledArrival =
              stops[i].reservationTimeMinutes ??
              stops[i].arrivalDeadlineMinutes;
          final serviceStart = scheduledArrival == null
              ? arrivalMinutes
              : arrivalMinutes < scheduledArrival
              ? scheduledArrival
              : arrivalMinutes;
          arrivalMinutes = serviceStart + (stops[i].stayMinutes ?? 0);
          arrivalMinutes += stops[i].transitMinutes ?? 0;
          arrivalMinutes += stops[i].transitBufferMinutes;
        }
        final scheduledArrival =
            stop.reservationTimeMinutes ?? stop.arrivalDeadlineMinutes;
        final serviceStart = scheduledArrival == null
            ? arrivalMinutes
            : arrivalMinutes < scheduledArrival
            ? scheduledArrival
            : arrivalMinutes;
        final departureMinutes = serviceStart + (stop.stayMinutes ?? 0);
        final place = placeById[stop.placeId];
        final isLast = index == stops.length - 1;
        final nextPlace = isLast ? null : placeById[stops[index + 1].placeId];
        return _StopBlock(
          key: ValueKey(stop.id),
          index: index,
          stop: stop,
          place: place,
          sourcePost: place == null
              ? null
              : AppScope.of(context).primarySourceForPlace(place.id),
          showTransit: !isLast,
          arrivalMinutes: arrivalMinutes,
          departureMinutes: departureMinutes,
          day: day,
          onEdit: () => _editStop(context, stop, place),
          onEditTransit: isLast
              ? null
              : () => _PlanOrderBar._showSegment(
                  context,
                  stop,
                  place,
                  nextPlace,
                  null,
                ),
          onRemove: () => runGuardedAction(
            context,
            () => AppScope.read(context).plans.removeStop(stop.id),
          ),
        );
      },
    );
  }

  static Future<void> _editStop(
    BuildContext context,
    PlanStop stop,
    Place? place,
  ) async {
    var stay = stop.stayMinutes ?? 60;
    var transitMinutes = stop.transitMinutes ?? 15;
    var bufferMinutes = stop.transitBufferMinutes;
    var scheduledArrivalMinutes =
        stop.reservationTimeMinutes ?? stop.arrivalDeadlineMinutes;
    var mode = stop.transitToNext ?? TransitMode.walk;
    final noteController = TextEditingController(text: stop.note ?? '');

    try {
      final ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  22,
                  22,
                  22,
                  MediaQuery.viewInsetsOf(context).bottom + 22,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: modalSheetHeight(context, fraction: 0.85),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          place?.name ?? '地点を編集',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          '滞在の想定時間',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: ink.withValues(alpha: 0.7),
                          ),
                        ),
                        Slider(
                          value: stay.toDouble().clamp(15, 240),
                          min: 15,
                          max: 240,
                          divisions: 15,
                          label: '$stay分',
                          onChanged: (v) =>
                              setModalState(() => stay = v.round()),
                        ),
                        Text('$stay分', textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        Text(
                          '次の場所までの移動',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: ink.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final m in TransitMode.values)
                              FilterPill(
                                label: m.label,
                                selected: mode == m,
                                onTap: () => setModalState(() => mode = m),
                              ),
                          ],
                        ),
                        Slider(
                          value: transitMinutes.toDouble().clamp(5, 180),
                          min: 5,
                          max: 180,
                          divisions: 35,
                          label: '$transitMinutes分',
                          onChanged: (v) =>
                              setModalState(() => transitMinutes = v.round()),
                        ),
                        Text('$transitMinutes分', textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        Text(
                          '乗換・駐車などの余裕時間',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: ink.withValues(alpha: 0.7),
                          ),
                        ),
                        Slider(
                          value: bufferMinutes.toDouble().clamp(0, 60),
                          min: 0,
                          max: 60,
                          divisions: 12,
                          label: '$bufferMinutes分',
                          onChanged: (value) => setModalState(
                            () => bufferMinutes = value.round(),
                          ),
                        ),
                        Text('$bufferMinutes分', textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.event_available_rounded),
                                label: Text(
                                  scheduledArrivalMinutes == null
                                      ? '予約・到着時刻'
                                      : '予約・到着 ${_minuteLabel(scheduledArrivalMinutes!)}',
                                ),
                                onPressed: () async {
                                  final value = await _pickMinutes(
                                    context,
                                    scheduledArrivalMinutes,
                                  );
                                  if (value != null) {
                                    setModalState(
                                      () => scheduledArrivalMinutes = value,
                                    );
                                  }
                                },
                              ),
                            ),
                            if (scheduledArrivalMinutes != null)
                              IconButton(
                                tooltip: '予約・到着時刻を解除',
                                onPressed: () => setModalState(
                                  () => scheduledArrivalMinutes = null,
                                ),
                                icon: const Icon(Icons.close_rounded),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: noteController,
                          decoration: const InputDecoration(hintText: 'メモ（任意）'),
                        ),
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('保存'),
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
      final note = noteController.text.trim();
      if (ok != true || !context.mounted) return;
      await runGuarded(
        context,
        () => AppScope.read(context).plans.updateStop(
          stop.copyWith(
            stayMinutes: stay,
            transitToNext: mode,
            transitMinutes: transitMinutes,
            transitTimeIsManual: true,
            transitBufferMinutes: bufferMinutes,
            reservationTimeMinutes: scheduledArrivalMinutes,
            clearReservationTime: scheduledArrivalMinutes == null,
            clearArrivalDeadline: true,
            note: note.isEmpty ? null : note,
            clearNote: note.isEmpty,
          ),
        ),
      );
    } finally {
      disposeAfterFrame([noteController]);
    }
  }

  static Future<int?> _pickMinutes(BuildContext context, int? initial) async {
    final value = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: (initial ?? 9 * 60) ~/ 60,
        minute: (initial ?? 9 * 60) % 60,
      ),
    );
    return value == null ? null : value.hour * 60 + value.minute;
  }

  static String _minuteLabel(int value) =>
      '${(value ~/ 60).toString().padLeft(2, '0')}:'
      '${(value % 60).toString().padLeft(2, '0')}';
}

class _StopBlock extends StatelessWidget {
  const _StopBlock({
    super.key,
    required this.index,
    required this.stop,
    required this.place,
    required this.sourcePost,
    required this.showTransit,
    required this.arrivalMinutes,
    required this.departureMinutes,
    required this.day,
    required this.onEdit,
    this.onEditTransit,
    required this.onRemove,
  });

  final int index;
  final PlanStop stop;
  final Place? place;
  final SourcePost? sourcePost;
  final bool showTransit;
  final int arrivalMinutes;
  final int departureMinutes;
  final DateTime? day;
  final VoidCallback onEdit;
  final VoidCallback? onEditTransit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final warnings = _warnings();
    final sourceLinks = SourceLinkService();
    final imagePath = place?.coverImagePath ?? sourcePost?.displayThumbnailPath;
    final scheduledArrival =
        stop.reservationTimeMinutes ?? stop.arrivalDeadlineMinutes;
    return Column(
      children: [
        Material(
          color: Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onEdit,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4, right: 8),
                      child: Icon(
                        Icons.drag_handle_rounded,
                        color: ink.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: mossDeep,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox.square(
                      dimension: 44,
                      child: PlacePhoto(
                        path: imagePath,
                        fallback: ColoredBox(
                          color: mintSoft,
                          child: Icon(
                            sourcePost == null
                                ? Icons.place_outlined
                                : sourceLinks.iconFor(sourcePost),
                            color: mossDeep,
                            size: 21,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          place?.name ?? '不明な場所',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        if (place?.address != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            place!.address!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: ink.withValues(alpha: 0.45),
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _MetaChip(
                              icon: Icons.access_time_filled_rounded,
                              label:
                                  '${_clock(arrivalMinutes)}着 → '
                                  '${_clock(departureMinutes)}発',
                            ),
                            if (stop.stayMinutes != null)
                              _MetaChip(
                                icon: Icons.schedule_rounded,
                                label: '滞在 ${stop.stayMinutes}分',
                              ),
                            if (scheduledArrival != null)
                              _MetaChip(
                                icon: Icons.event_available_rounded,
                                label: '予約・到着 ${_clock(scheduledArrival)}',
                              ),
                            if (sourceLinks.canOpen(sourcePost))
                              ActionChip(
                                avatar: Icon(
                                  sourceLinks.iconFor(sourcePost),
                                  size: 16,
                                  color: mossDeep,
                                ),
                                label: Text(
                                  '${sourceLinks.serviceLabel(sourcePost)}を開く',
                                ),
                                onPressed: () async {
                                  await sourceLinks.openPost(sourcePost!);
                                },
                              ),
                            if (stop.transitBufferMinutes > 0)
                              _MetaChip(
                                icon: Icons.more_time_rounded,
                                label: '移動余裕 ${stop.transitBufferMinutes}分',
                              ),
                            if (stop.note != null && stop.note!.isNotEmpty)
                              _MetaChip(
                                icon: Icons.notes_rounded,
                                label: stop.note!,
                              ),
                          ],
                        ),
                        for (final warning in warnings) ...[
                          const SizedBox(height: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFE9D5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  size: 17,
                                  color: Color(0xFF9A571F),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    warning,
                                    style: const TextStyle(
                                      color: Color(0xFF7D461B),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onRemove,
                    icon: Icon(
                      Icons.close_rounded,
                      color: ink.withValues(alpha: 0.35),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showTransit)
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onEditTransit,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 28),
              child: Row(
                children: [
                  Container(
                    width: 2,
                    height: 28,
                    color: moss.withValues(alpha: 0.35),
                  ),
                  const SizedBox(width: 14),
                  Icon(
                    _transitIcon(stop.transitToNext),
                    size: 16,
                    color: mossDeep.withValues(alpha: 0.75),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      [
                        stop.transitToNext?.label ?? '移動',
                        if (stop.transitMinutes != null)
                          '${stop.transitMinutes}分',
                        if (stop.transitBufferMinutes > 0)
                          '余裕+${stop.transitBufferMinutes}分',
                      ].join(' · '),
                      style: TextStyle(
                        color: mossDeep.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.edit_rounded,
                    size: 16,
                    color: mossDeep.withValues(alpha: 0.55),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static String _clock(int rawMinutes) {
    final minutes = rawMinutes % (24 * 60);
    return '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
        '${(minutes % 60).toString().padLeft(2, '0')}';
  }

  List<String> _warnings() {
    final result = <String>[];
    final scheduledArrival =
        stop.reservationTimeMinutes ?? stop.arrivalDeadlineMinutes;
    if (scheduledArrival != null && arrivalMinutes > scheduledArrival) {
      result.add('予約・到着時刻に${arrivalMinutes - scheduledArrival}分遅れる予定です');
    }
    if (place != null && day != null) {
      if (place!.closedWeekdays.contains(day!.weekday)) {
        result.add('定休日として登録されています');
      }
      final opening = place!.openingTimeMinutes;
      final closing = place!.closingTimeMinutes;
      if (opening != null && closing != null && opening != closing) {
        final arrival = arrivalMinutes % (24 * 60);
        final departure = departureMinutes % (24 * 60);
        final arrivalInside = opening < closing
            ? arrival >= opening && arrival < closing
            : arrival >= opening || arrival < closing;
        final departureInside = opening < closing
            ? departure > opening && departure <= closing
            : departure > opening || departure <= closing;
        if (!arrivalInside) {
          result.add('到着予定が営業時間 ${_clock(opening)}〜${_clock(closing)} の外です');
        } else if (!departureInside) {
          result.add('退店予定が閉店 ${_clock(closing)} を過ぎます');
        }
      }
    }
    return result;
  }

  static IconData _transitIcon(TransitMode? mode) {
    return switch (mode) {
      TransitMode.walk => Icons.directions_walk_rounded,
      TransitMode.train => Icons.train_rounded,
      TransitMode.car => Icons.directions_car_rounded,
      TransitMode.taxi => Icons.local_taxi_rounded,
      TransitMode.bus => Icons.directions_bus_rounded,
      TransitMode.bike => Icons.pedal_bike_rounded,
      TransitMode.other || null => Icons.timeline_rounded,
    };
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: mintSoft.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: mossDeep),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: mossDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
