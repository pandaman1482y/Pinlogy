/// Prefer a current acquired image; placeholders must not hide an existing cover.
String? resolveImportThumbnail({
  String? postThumbnail,
  String? importThumbnail,
  String? savedThumbnail,
}) {
  for (final candidate in [postThumbnail, importThumbnail, savedThumbnail]) {
    final path = candidate?.trim();
    if (path == null || path.isEmpty || path.startsWith('local://')) continue;
    final uri = Uri.tryParse(path);
    if (uri == null ||
        (uri.scheme.isNotEmpty &&
            uri.scheme != 'https' &&
            uri.scheme != 'file'))
      continue;
    return path;
  }
  return null;
}
