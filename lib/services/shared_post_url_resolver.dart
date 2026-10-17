import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'social_post_identity.dart';

/// Best effort identity lookup. A preview lookup must never reject a new share.
Future<String> resolveSharedPostUrl(
  String raw, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final original = raw.trim();
  if (SocialPostIdentity.tryParse(original) != null) return original;
  final initial = Uri.tryParse(original);
  if (initial == null || !_allowed(initial)) return original;
  final transport = client ?? http.Client();
  try {
    return await _resolve(initial, transport).timeout(timeout) ?? original;
  } catch (_) {
    return original;
  } finally {
    if (client == null) transport.close();
  }
}

bool _allowed(Uri uri) =>
    uri.scheme == 'https' &&
    (uri.host.toLowerCase() == 'tiktok.com' ||
        uri.host.toLowerCase().endsWith('.tiktok.com'));

Future<String?> _resolve(Uri initial, http.Client client) async {
  var current = initial;
  final visited = <String>{};
  for (var hop = 0; hop < 5; hop++) {
    if (!_allowed(current) || !visited.add(current.toString())) return null;
    final identity = SocialPostIdentity.tryParse(current.toString());
    if (identity != null) return identity.canonicalUrl;
    final response = await client.send(
      http.Request('GET', current)..followRedirects = false,
    );
    final location = response.headers['location'];
    if (response.statusCode >= 300 &&
        response.statusCode < 400 &&
        location != null) {
      // Cancel the redirect body instead of waiting for an unbounded stream.
      await response.stream.listen((_) {}).cancel();
      current = current.resolve(location);
      continue;
    }
    if (response.statusCode != 200) {
      await response.stream.listen((_) {}).cancel();
      return null;
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      final remaining = 96 * 1024 - bytes.length;
      bytes.addAll(chunk.take(remaining));
      if (bytes.length >= 96 * 1024) break;
    }
    final html = utf8
        .decode(bytes, allowMalformed: true)
        .replaceAll('&amp;', '&')
        .replaceAll(r'\/', '/');
    for (final match in RegExp(
      r'<(?:link|meta)\b[^>]*>',
      caseSensitive: false,
    ).allMatches(html)) {
      final tag = match[0]!;
      String? attribute(String name) => RegExp(
        '$name\\s*=\\s*["\']([^"\']+)["\']',
        caseSensitive: false,
      ).firstMatch(tag)?.group(1);
      final canonical = attribute('rel')?.toLowerCase() == 'canonical';
      final og = attribute('property')?.toLowerCase() == 'og:url';
      final raw = canonical
          ? attribute('href')
          : og
          ? attribute('content')
          : null;
      if (raw == null) continue;
      final candidate = SocialPostIdentity.tryParse(
        current.resolve(raw).toString(),
      );
      if (candidate?.service == 'tiktok') return candidate!.canonicalUrl;
    }
    return null;
  }
  return null;
}
