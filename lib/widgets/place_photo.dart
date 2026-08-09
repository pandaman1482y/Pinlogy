import 'dart:io';

import 'package:flutter/material.dart';

/// 共有投稿から保存した写真を、ローカル・ネットワークのどちらでも表示する。
class PlacePhoto extends StatefulWidget {
  const PlacePhoto({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.fallback,
    this.onRefreshSource,
  });

  final String? path;
  final BoxFit fit;
  final Widget? fallback;
  final Future<String?> Function()? onRefreshSource;

  @override
  State<PlacePhoto> createState() => _PlacePhotoState();
}

class _PlacePhotoState extends State<PlacePhoto> {
  int _retry = 0;
  String? _replacementPath;
  bool _recovering = false;
  bool _autoRecoveryTried = false;

  @override
  Widget build(BuildContext context) {
    final value = (_replacementPath ?? widget.path)?.trim() ?? '';
    if (value.isEmpty) return widget.fallback ?? const SizedBox.shrink();

    final error = widget.fallback ?? const SizedBox.shrink();
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return Image.network(
        value,
        key: ValueKey('$value#$_retry'),
        fit: widget.fit,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) return child;
          return Stack(
            fit: StackFit.expand,
            children: [
              error,
              const Center(
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              ),
            ],
          );
        },
        errorBuilder: (_, _, _) {
          if (!_autoRecoveryTried && widget.onRefreshSource != null) {
            _autoRecoveryTried = true;
            WidgetsBinding.instance.addPostFrameCallback((_) => _recover());
          }
          return Stack(
            fit: StackFit.expand,
            children: [
              error,
              Center(
                child: IconButton.filledTonal(
                  tooltip: '画像を再読み込み',
                  onPressed: _recovering ? null : _recover,
                  icon: _recovering
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
              ),
            ],
          );
        },
      );
    }
    if (value.startsWith('file://')) {
      return Image.file(
        File(Uri.parse(value).toFilePath()),
        fit: widget.fit,
        errorBuilder: (_, _, _) => error,
      );
    }
    return Image.file(
      File(value),
      fit: widget.fit,
      errorBuilder: (_, _, _) => error,
    );
  }

  Future<void> _recover() async {
    if (_recovering || !mounted) return;
    setState(() => _recovering = true);
    try {
      final refreshed = await widget.onRefreshSource?.call();
      if (!mounted) return;
      setState(() {
        if (refreshed != null && refreshed.isNotEmpty) {
          _replacementPath = refreshed;
        }
        _retry++;
      });
    } finally {
      if (mounted) setState(() => _recovering = false);
    }
  }
}
