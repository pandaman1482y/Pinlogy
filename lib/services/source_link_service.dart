import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';

/// Instagram / TikTok など元投稿を外部アプリまたはブラウザで開く。
class SourceLinkService {
  Future<bool> openPost(SourcePost post) async {
    final url = post.url?.trim();
    if (url == null || url.isEmpty) return false;
    return openUrl(url, service: post.service);
  }

  Future<bool> openUrl(String url, {String? service}) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return false;

    final httpsUri = Uri.tryParse(trimmed);
    if (httpsUri == null ||
        !(httpsUri.isScheme('http') || httpsUri.isScheme('https'))) {
      return false;
    }

    // インストール済みなら各アプリが https リンクを受け取って開く
    if (await canLaunchUrl(httpsUri)) {
      return launchUrl(httpsUri, mode: LaunchMode.externalApplication);
    }
    return launchUrl(httpsUri, mode: LaunchMode.platformDefault);
  }

  String serviceLabel(SourcePost? post) {
    if (post == null) return '投稿';
    final service = post.service?.trim();
    if (service != null && service.isNotEmpty) return service;
    final url = (post.url ?? '').toLowerCase();
    if (url.contains('instagram.com')) return 'Instagram';
    if (url.contains('tiktok.com')) return 'TikTok';
    if (url.contains('youtube.com') || url.contains('youtu.be')) {
      return 'YouTube';
    }
    return '投稿';
  }

  IconData iconFor(SourcePost? post) {
    final label = serviceLabel(post).toLowerCase();
    if (label.contains('instagram')) return Icons.photo_camera_outlined;
    if (label.contains('tiktok')) return Icons.music_note_rounded;
    if (label.contains('youtube')) return Icons.play_circle_outline;
    if (label.contains('画像') || label.contains('スクリーン')) {
      return Icons.image_outlined;
    }
    return Icons.open_in_new_rounded;
  }

  bool canOpen(SourcePost? post) {
    final url = post?.url?.trim();
    return url != null &&
        url.isNotEmpty &&
        (url.startsWith('http://') || url.startsWith('https://'));
  }
}
