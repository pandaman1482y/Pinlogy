import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../services/source_link_service.dart';

class SourcePostTile extends StatelessWidget {
  const SourcePostTile({
    super.key,
    required this.post,
    this.compact = false,
    this.onOpened,
  });

  final SourcePost post;
  final bool compact;
  final VoidCallback? onOpened;

  @override
  Widget build(BuildContext context) {
    final links = SourceLinkService();
    final canOpen = links.canOpen(post);
    final label = links.serviceLabel(post);

    return Material(
      color: Colors.white.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: !canOpen
            ? null
            : () async {
                final ok = await links.openPost(post);
                if (!context.mounted) return;
                if (!ok) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('投稿を開けませんでした')));
                } else {
                  onOpened?.call();
                }
              },
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 14),
          child: Row(
            children: [
              Container(
                width: compact ? 40 : 44,
                height: compact ? 40 : 44,
                decoration: BoxDecoration(
                  color: mint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(links.iconFor(post), color: mossDeep, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.title ?? '元の投稿',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      canOpen ? '$label をひらく' : '$label  ·  URLなし',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: canOpen ? moss : const Color(0xFF8A968F),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                canOpen ? Icons.north_east_rounded : Icons.link_off_rounded,
                color: canOpen ? mossDeep : const Color(0xFFB0B8B3),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> openSourcePostOrWarn(
  BuildContext context,
  SourcePost? post,
) async {
  if (post == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('関連する投稿がありません')));
    return;
  }
  final links = SourceLinkService();
  if (!links.canOpen(post)) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('この投稿には開けるURLがありません')));
    return;
  }
  bool ok;
  try {
    ok = await links.openPost(post);
  } catch (_) {
    ok = false;
  }
  if (!context.mounted) return;
  if (!ok) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('投稿を開けませんでした')));
  }
}
