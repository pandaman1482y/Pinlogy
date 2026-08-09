import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/directions_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/feedback.dart';
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
    try {
      final ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (ctx) {
          return Padding(
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
          );
        },
      );
      final title = titleController.text.trim();
      final notes = notesController.text.trim();
      if (ok != true || !context.mounted) return;
      await runGuardedAction(
        context,
        () => AppScope.read(
          context,
        ).plans.update(plan.copyWith(title: title, notes: notes)),
      );
    } finally {
      disposeAfterFrame([titleController, notesController]);
    }
  }

  static Future<void> _addStop(
    BuildContext context,
    String planId,
    DateTime? day,
  ) async {
    final controller = AppScope.read(context);
    final places = List<Place>.of(controller.hub.snapshot.places)
      ..sort((a, b) => a.name.compareTo(b.name));
    if (places.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('先にマップへ場所を保存してください')));
      return;
    }

    String query = '';
    final selected = await showModalBottomSheet<Place>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = places
                .where(
                  (p) =>
                      query.isEmpty ||
                      p.name.contains(query) ||
                      (p.address?.contains(query) ?? false),
                )
                .toList();
            return SizedBox(
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
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: '店名・住所',
                      ),
                      onChanged: (v) => setModalState(() => query = v),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final place = filtered[i];
                          return ListTile(
                            title: Text(
                              place.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: place.address == null
                                ? null
                                : Text(
                                    place.address!,
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
  });

  final String planId;
  final DateTime? day;
  final List<PlanStop> stops;

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
      onReorder: (oldIndex, newIndex) async {
        var target = newIndex;
        if (oldIndex < target) target -= 1;
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
        final place = placeById[stop.placeId];
        final isLast = index == stops.length - 1;
        return _StopBlock(
          key: ValueKey(stop.id),
          index: index,
          stop: stop,
          place: place,
          showTransit: !isLast,
          onEdit: () => _editStop(context, stop, place),
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
            note: note.isEmpty ? null : note,
            clearNote: note.isEmpty,
          ),
        ),
      );
    } finally {
      disposeAfterFrame([noteController]);
    }
  }
}

class _StopBlock extends StatelessWidget {
  const _StopBlock({
    super.key,
    required this.index,
    required this.stop,
    required this.place,
    required this.showTransit,
    required this.onEdit,
    required this.onRemove,
  });

  final int index;
  final PlanStop stop;
  final Place? place;
  final bool showTransit;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
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
                            if (stop.stayMinutes != null)
                              _MetaChip(
                                icon: Icons.schedule_rounded,
                                label: '滞在 ${stop.stayMinutes}分',
                              ),
                            if (stop.note != null && stop.note!.isNotEmpty)
                              _MetaChip(
                                icon: Icons.notes_rounded,
                                label: stop.note!,
                              ),
                          ],
                        ),
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
          Padding(
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
                Text(
                  [
                    stop.transitToNext?.label ?? '移動',
                    if (stop.transitMinutes != null) '${stop.transitMinutes}分',
                  ].join(' · '),
                  style: TextStyle(
                    color: mossDeep.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static IconData _transitIcon(TransitMode? mode) {
    return switch (mode) {
      TransitMode.walk => Icons.directions_walk_rounded,
      TransitMode.train => Icons.train_rounded,
      TransitMode.car => Icons.directions_car_rounded,
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
