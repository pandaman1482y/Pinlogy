import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pinlogy/models/models.dart';
import 'package:pinlogy/repositories/local_data_store.dart';
import 'package:pinlogy/repositories/local_repositories.dart';
import 'package:pinlogy/services/location_services.dart';
import 'package:pinlogy/services/share_receiver_service.dart';
import 'package:pinlogy/services/shared_post_url_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const short = 'https://lite.tiktok.com/t/abc/';
  const full = 'https://www.tiktok.com/@author/video/7646728112784362772';
  test('canonical URL needs no network request', () async {
    expect(
      await resolveSharedPostUrl(
        full,
        client: MockClient((_) => throw StateError('network')),
      ),
      full,
    );
  });
  test(
    'redirect location resolves independently of response.request.url',
    () async {
      expect(
        await resolveSharedPostUrl(
          short,
          client: MockClient(
            (_) async => http.Response('', 302, headers: {'location': full}),
          ),
        ),
        'https://tiktok.com/@author/video/7646728112784362772',
      );
    },
  );
  test('HTML canonical resolves with a bounded response', () async {
    expect(
      await resolveSharedPostUrl(
        short,
        client: MockClient(
          (_) async =>
              http.Response('<link rel="canonical" href="$full">', 200),
        ),
      ),
      'https://tiktok.com/@author/video/7646728112784362772',
    );
  });
  test('unrelated video links are not treated as the shared post', () async {
    expect(
      await resolveSharedPostUrl(
        short,
        client: MockClient(
          (_) async => http.Response('<a href="$full">recommendation</a>', 200),
        ),
      ),
      short,
    );
  });
  test('HTTP failure preserves original share URL', () async {
    expect(
      await resolveSharedPostUrl(
        short,
        client: MockClient((_) async => http.Response('blocked', 403)),
      ),
      short,
    );
  });
  test('network failure preserves original share URL', () async {
    expect(
      await resolveSharedPostUrl(
        short,
        client: MockClient((_) => throw http.ClientException('offline')),
      ),
      short,
    );
  });
  test('timeout preserves original share URL', () async {
    expect(
      await resolveSharedPostUrl(
        short,
        timeout: const Duration(milliseconds: 10),
        client: MockClient((_) => Completer<http.Response>().future),
      ),
      short,
    );
  });
  test('redirects do not follow another host', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response(
        '',
        302,
        headers: {'location': 'https://example.com/video/7646728112784362772'},
      );
    });
    expect(await resolveSharedPostUrl(short, client: client), short);
    expect(calls, 1);
  });
  test('unresolved new share is persisted with a pending job and still deduplicated', () async {
    SharedPreferences.setMockInitialValues({});
    final hub = LocalRepositoryHub(InMemoryDataStore());
    await hub.load(seedIfEmpty: false);
    final receiver = LocalShareReceiverService(
      sourcePosts: hub.sourcePosts,
      analysis: hub.analysis,
      analysisService: _UnusedAnalysis(),
      autoAnalyze: false,
      officialPreviewLoader: (_) async => null,
      identityClient: MockClient((_) async => http.Response('blocked', 403)),
    );
    final post = await receiver.receive(const SharedContent(url: short));
    expect(post.url, short);
    expect(hub.snapshot.sourcePosts.length, 1);
    expect(
      (await hub.analysis.getBySourcePostId(post.id))?.status,
      AnalysisJobStatus.pending,
    );
    await expectLater(
      receiver.receive(const SharedContent(url: short)),
      throwsA(isA<DuplicateShareException>()),
    );
    expect(hub.snapshot.sourcePosts.length, 1);
    expect((await hub.analysis.getAll()).length, 1);
  });
}

class _UnusedAnalysis implements PostAnalysisService {
  @override
  Future<PostAnalysisResponse> analyze(PostAnalysisRequest request) async =>
      throw StateError('analysis disabled for intake test');
}
