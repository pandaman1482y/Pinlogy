import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme.dart';
import '../../widgets/common_widgets.dart';
import '../plans/plans_tab.dart';
import '../saved/saved_tab.dart';
import '../settings/cloud_sync_page.dart';

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final snapshot = AppScope.of(context).hub.snapshot;
    final unvisited = snapshot.places.where((place) => !place.isVisited).length;
    return Column(
      children: [
        const PageHeading('マイページ', '保存した場所と旅の準備を、ここで管理。'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .82),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    _Stat(value: snapshot.maps.length, label: 'マップ'),
                    const _StatDivider(),
                    _Stat(value: snapshot.places.length, label: 'スポット'),
                    const _StatDivider(),
                    _Stat(value: unvisited, label: '行きたい'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _MenuCard(
                icon: Icons.bookmark_outline_rounded,
                title: '保存した場所',
                subtitle: '検索・並び替え・削除',
                onTap: () => _open(context, const _SavedPlacesPage()),
              ),
              _MenuCard(
                icon: Icons.route_outlined,
                title: '旅行プラン',
                subtitle: '行きたい場所を日程にまとめる',
                onTap: () => _open(context, const _PlansPage()),
              ),
              _MenuCard(
                icon: Icons.cloud_outlined,
                title: '同期と共有',
                subtitle: 'バックアップ・共有マップ',
                onTap: () => _open(context, const CloudSyncPage()),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _open(BuildContext context, Widget page) {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final int value;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          '$value',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(color: mossDeep),
        ),
        const SizedBox(height: 2),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 34, color: mossDeep.withValues(alpha: .10));
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: Colors.white.withValues(alpha: .82),
      borderRadius: BorderRadius.circular(18),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        leading: CircleAvatar(
          backgroundColor: mint,
          foregroundColor: mossDeep,
          child: Icon(icon),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    ),
  );
}

class _SavedPlacesPage extends StatelessWidget {
  const _SavedPlacesPage();
  @override
  Widget build(BuildContext context) => PinlogyBackdrop(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(toolbarHeight: 48),
      body: const SafeArea(top: false, child: SavedTab()),
    ),
  );
}

class _PlansPage extends StatelessWidget {
  const _PlansPage();
  @override
  Widget build(BuildContext context) => PinlogyBackdrop(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(toolbarHeight: 48),
      body: const SafeArea(top: false, child: PlansTab()),
    ),
  );
}
