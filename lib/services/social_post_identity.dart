class SocialPostIdentity {
  const SocialPostIdentity({
    required this.service,
    required this.postId,
    required this.canonicalUrl,
  });

  final String service;
  final String postId;
  final String canonicalUrl;

  String get key => '$service:$postId';
  String get storageId => 'social-$service-$postId';

  static SocialPostIdentity? tryParse(String? rawUrl) {
    final uri = Uri.tryParse(rawUrl?.trim() ?? '');
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    final segments = uri.pathSegments
        .where((value) => value.isNotEmpty)
        .toList();

    if (host == 'instagram.com' || host.endsWith('.instagram.com')) {
      final offset = segments.isNotEmpty && segments.first == 'share' ? 1 : 0;
      if (segments.length >= offset + 2 &&
          const {'p', 'reel', 'reels', 'tv'}.contains(segments[offset])) {
        final id = _safeId(segments[offset + 1]);
        if (id != null) {
          return SocialPostIdentity(
            service: 'instagram',
            postId: id,
            canonicalUrl: 'https://www.instagram.com/p/$id/',
          );
        }
      }
    }

    if (host == 'tiktok.com' || host.endsWith('.tiktok.com')) {
      for (var index = 0; index + 1 < segments.length; index++) {
        if (segments[index] == 'video') {
          final id = RegExp(
            r'^\d{8,30}$',
          ).firstMatch(segments[index + 1])?.group(0);
          if (id != null) {
            return SocialPostIdentity(
              service: 'tiktok',
              postId: id,
              canonicalUrl: Uri(
                scheme: 'https',
                host: host,
                path: uri.path,
              ).toString(),
            );
          }
        }
      }
    }
    return null;
  }

  static String? normalizedSupportedUrl(String? rawUrl) {
    final identity = tryParse(rawUrl);
    if (identity != null) return identity.canonicalUrl;
    final uri = Uri.tryParse(rawUrl?.trim() ?? '');
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    final supported =
        host == 'instagram.com' ||
        host.endsWith('.instagram.com') ||
        host == 'tiktok.com' ||
        host.endsWith('.tiktok.com');
    if (!supported) return null;
    final query = Map<String, String>.from(uri.queryParameters)
      ..removeWhere((key, _) => _trackingKeys.contains(key.toLowerCase()));
    return Uri(
      scheme: 'https',
      host: host,
      path: uri.path,
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }

  static String? _safeId(String value) =>
      RegExp(r'^[A-Za-z0-9_-]{5,80}$').hasMatch(value) ? value : null;

  static const _trackingKeys = {
    'utm_source',
    'utm_medium',
    'utm_campaign',
    'utm_content',
    'utm_term',
    'igsh',
    'igshid',
    'ig_mid',
    'share_app_id',
    'share_item_id',
    '_r',
  };
}
