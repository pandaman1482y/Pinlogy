import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../models/models.dart';
import '../../widgets/common_widgets.dart';
import '../maps/maps_tab.dart';

class SavedTab extends StatefulWidget {
  const SavedTab({super.key});

  @override
  State<SavedTab> createState() => _SavedTabState();
}

class _SavedTabState extends State<SavedTab> {
  String query = '';
  PlaceFilterOption filter = PlaceFilterOption.all;
  PlaceSortOption sort = PlaceSortOption.registeredDesc;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);

    return Column(
      children: [
        const PageHeading('保存済み', 'あとで行く場所を、ひとつの流れで。'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: QuietSearchField(
            hintText: '店名・住所・メモ・タグ',
            onChanged: (value) => setState(() => query = value),
          ),
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Row(
            children: [
              for (final option in PlaceFilterOption.values) ...[
                FilterPill(
                  label: option.label,
                  selected: filter == option,
                  onTap: () => setState(() => filter = option),
                ),
                const SizedBox(width: 8),
              ],
              PopupMenuButton<PlaceSortOption>(
                initialValue: sort,
                onSelected: (value) => setState(() => sort = value),
                itemBuilder: (_) => PlaceSortOption.values
                    .map((s) => PopupMenuItem(value: s, child: Text(s.label)))
                    .toList(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    sort.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Builder(
            builder: (context) {
              final places = controller.queryPlaces(
                query: query,
                filter: filter,
                sort: sort,
              );
              if (places.isEmpty) {
                return const EmptyState(
                  icon: Icons.favorite_border_rounded,
                  title: 'まだ見つからない',
                  message: '条件を変えるか、マップに場所を追加してみて。',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
                itemCount: places.length,
                separatorBuilder: (_, index) => const SizedBox(height: 12),
                itemBuilder: (context, i) => PlaceListTile(place: places[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}
