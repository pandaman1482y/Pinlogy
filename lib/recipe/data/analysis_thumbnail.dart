/// The selected cover is independent of the immutable evidence image order.
int analysisThumbnailIndex(Map media, int count) {
  final index = media['thumbnail_index'];
  return index is int && index >= 0 && index < count ? index : 0;
}

String? analysisThumbnailPath(Map<String, dynamic> result, List<String> paths) {
  if (paths.isEmpty) return null;
  final media = result['shared_media'];
  return paths[media is Map ? analysisThumbnailIndex(media, paths.length) : 0];
}
