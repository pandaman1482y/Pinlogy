import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/feedback.dart';
import '../../widgets/sheet_layout.dart';
import 'plan_detail_page.dart';

class PlansTab extends StatelessWidget {
  const PlansTab({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final plans = List<TripPlan>.of(controller.hub.snapshot.plans)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return Column(
      children: [
        PageHeading(
          'プラン',
          '日付つきで、移動と時間の流れをつくる。',
          action: SoftIconButton(
            onPressed: () => _showCreatePlan(context),
            icon: Icons.add_rounded,
            tooltip: 'プランを追加',
          ),
        ),
        Expanded(
          child: plans.isEmpty
              ? EmptyState(
                  icon: Icons.route_rounded,
                  title: 'まだプランがない',
                  message: '行きたい場所を、日付と順番で並べてみよう。',
                  action: FilledButton(
                    onPressed: () => _showCreatePlan(context),
                    child: const Text('プランをつくる'),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 110),
                  itemCount: plans.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, i) => _PlanCard(plan: plans[i]),
                ),
        ),
      ],
    );
  }

  static Future<void> _showCreatePlan(BuildContext context) async {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    final titleController = TextEditingController();
    final notesController = TextEditingController();
    DateTime? startDate;
    try {
      final created = await showModalBottomSheet<bool>(
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
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '新しいプラン',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: titleController,
                        autofocus: true,
                        decoration: const InputDecoration(hintText: 'プラン名'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: notesController,
                        decoration: const InputDecoration(hintText: 'メモ（任意）'),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: startDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setModalState(() => startDate = picked);
                          }
                        },
                        icon: const Icon(
                          Icons.calendar_today_rounded,
                          size: 18,
                        ),
                        label: Text(
                          startDate == null
                              ? '開始日を選ぶ（任意）'
                              : '${startDate!.year}/${startDate!.month}/${startDate!.day}',
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('つくる'),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
      final title = titleController.text.trim();
      final notes = notesController.text.trim();
      if (created != true || !context.mounted) return;
      final plan = await runGuarded(
        context,
        () => AppScope.read(context).plans.create(
          TripPlan(
            title: title.isEmpty ? null : title,
            notes: notes.isEmpty ? null : notes,
            startDate: startDate,
          ),
        ),
      );
      if (plan == null || !context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PlanDetailPage(planId: plan.id)),
      );
    } finally {
      disposeAfterFrame([titleController, notesController]);
    }
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan});

  final TripPlan plan;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final stops = controller.hub.snapshot.planStops
        .where((s) => s.planId == plan.id)
        .toList();
    final days = stops.map((s) => s.dayDate).toSet().length;
    final dayLabel = plan.startDate == null
        ? (days == 0 ? '日付未設定' : '$days日分')
        : '${plan.startDate!.month}/${plan.startDate!.day}〜 · ${stops.length}地点';

    return Material(
      color: Colors.white.withValues(alpha: 0.62),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PlanDetailPage(planId: plan.id)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: mintSoft.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.route_rounded, color: mossDeep),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dayLabel,
                      style: TextStyle(
                        color: ink.withValues(alpha: 0.55),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (plan.notes.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        plan.notes,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: ink.withValues(alpha: 0.45),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: ink.withValues(alpha: 0.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
