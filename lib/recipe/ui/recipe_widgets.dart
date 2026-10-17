import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../models/recipe_models.dart';

class RecipeImage extends StatelessWidget {
  const RecipeImage({
    super.key,
    this.path,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.cacheWidth,
  });

  final String? path;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    final raw = path?.trim();
    Widget child;
    if (raw == null || raw.isEmpty || raw.startsWith('local://')) {
      child = const _ImageFallback();
    } else {
      final uri = Uri.tryParse(raw);
      if (uri?.scheme == 'https') {
        child = Image.network(
          raw,
          fit: fit,
          cacheWidth: cacheWidth,
          errorBuilder: (_, __, ___) => const _ImageFallback(),
        );
      } else {
        final filePath = uri?.scheme == 'file' ? uri!.toFilePath() : raw;
        child = Image.file(
          File(filePath),
          fit: fit,
          cacheWidth: cacheWidth,
          errorBuilder: (_, __, ___) => const _ImageFallback(),
        );
      }
    }
    if (borderRadius == null) return child;
    return ClipRRect(borderRadius: borderRadius!, child: child);
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) => Container(
    color: mintSoft,
    alignment: Alignment.center,
    child: const Icon(Icons.restaurant_menu_rounded, color: moss, size: 40),
  );
}

class RecipeGridCard extends StatelessWidget {
  const RecipeGridCard({
    super.key,
    required this.recipe,
    required this.onTap,
    required this.onFavorite,
  });

  final Recipe recipe;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: recipe.title,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 4 / 5,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                RecipeImage(path: recipe.coverImagePath, cacheWidth: 480),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xB8000000)],
                      stops: [0.42, 1],
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.32),
                    shape: const CircleBorder(),
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: recipe.isFavorite ? 'お気に入りから外す' : 'お気に入り',
                      onPressed: onFavorite,
                      icon: Icon(
                        recipe.isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: Colors.white,
                        size: 21,
                      ),
                    ),
                  ),
                ),
                if (recipe.status == RecipeStatus.needsReview)
                  const Positioned(
                    top: 10,
                    left: 10,
                    child: _CardBadge(
                      icon: Icons.priority_high_rounded,
                      label: '要確認',
                      color: warningColor,
                    ),
                  ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        recipe.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: Colors.white, height: 1.25),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        [
                          if (recipe.totalMinutes != null)
                            '${recipe.totalMinutes}分',
                          recipe.category,
                        ].whereType<String>().join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.88),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CardBadge extends StatelessWidget {
  const _CardBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.white),
        const SizedBox(width: 3),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
      if (trailing != null) trailing!,
    ],
  );
}

class SoftPanel extends StatelessWidget {
  const SoftPanel({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: mintSoft,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: borderSubtle),
    ),
    child: child,
  );
}

String compactDuration(int? minutes) => minutes == null ? '時間未確認' : '$minutes分';

String timestampLabel(int seconds) {
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return '$minutes:${rest.toString().padLeft(2, '0')}';
}

/// Align the icon with the first text line and let both labels and values wrap.
class RecipeIconText extends StatelessWidget {
  const RecipeIconText({
    super.key,
    required this.icon,
    required this.label,
    required this.text,
    this.fontSize = 14,
  });
  final IconData icon;
  final String label, text;
  final double fontSize;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 24,
        height: fontSize * 1.45,
        child: Center(child: Icon(icon, size: 18, color: mossDeep)),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$label：',
                style: const TextStyle(color: mossDeep),
              ),
              TextSpan(text: text),
            ],
          ),
          style: TextStyle(
            fontSize: fontSize,
            height: 1.45,
            fontWeight: FontWeight.normal,
            color: ink,
          ),
        ),
      ),
    ],
  );
}

class RecipeServingStepper extends StatelessWidget {
  const RecipeServingStepper({
    required this.servings,
    required this.unit,
    required this.onChanged,
  });
  final double servings;
  final String unit;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final step = unit == '人分' ? 0.5 : 1.0;
    final value = servings.toStringAsFixed(servings % 1 == 0 ? 0 : 1);
    return Container(
      decoration: BoxDecoration(
        color: mintSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '数量を減らす',
            visualDensity: VisualDensity.compact,
            onPressed: servings <= step
                ? null
                : () => onChanged(servings - step),
            icon: const Icon(Icons.remove_rounded, size: 18),
          ),
          Text('$value$unit'),
          IconButton(
            tooltip: '数量を増やす',
            visualDensity: VisualDensity.compact,
            onPressed: () => onChanged(servings + step),
            icon: const Icon(Icons.add_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}
