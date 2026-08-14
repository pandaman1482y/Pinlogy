import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/models/models.dart';
import 'package:pinlogy/repositories/local_data_store.dart';
import 'package:pinlogy/repositories/local_repositories.dart';
import 'package:pinlogy/services/location_services.dart';
import 'package:pinlogy/services/share_receiver_service.dart';

void main() {
  group('SharedContent.tryParse', () {
    test('URL文字列をurlへ変換する', () {
      final content = SharedContent.tryParse('https://www.instagram.com/p/abc');
      expect(content?.url, 'https://www.instagram.com/p/abc');
    });

    test('Mapペイロードを受け取る', () {
      final content = SharedContent.tryParse({
        'url': 'https://www.tiktok.com/@x/video/1',
        'text': '北海道グルメ',
        'imagePaths': ['content://media/1'],
        'service': 'TikTok',
        'title': '共有',
      });
      expect(content?.service, 'TikTok');
      expect(content?.imagePaths, ['content://media/1']);
      expect(content?.text, '北海道グルメ');
    });

    test('空ペイロードはnull', () {
      expect(SharedContent.tryParse({}), isNull);
      expect(SharedContent.tryParse(null), isNull);
    });
  });

  group('ShareIntakeCoordinator', () {
    test('投稿タイトル・本文・サムネイルを揃えてから解析する', () async {
      final hub = LocalRepositoryHub(InMemoryDataStore());
      await hub.load(seedIfEmpty: false);
      final capture = _CapturingAnalysis();
      final receiver = LocalShareReceiverService(
        sourcePosts: hub.sourcePosts,
        analysis: hub.analysis,
        analysisService: capture,
        officialPreviewLoader: (_) async =>
            'https://p16-sign.tiktokcdn.com/preview.jpeg',
      );

      final post = await receiver.receive(
        const SharedContent(
          url: 'https://www.tiktok.com/@shop/video/1',
          title: 'カフェ・ピンロジー',
          text: '大阪府八尾市本町1丁目1番1号',
        ),
        waitForAnalysis: true,
      );

      expect(post.imagePaths, ['https://p16-sign.tiktokcdn.com/preview.jpeg']);
      expect(capture.request?.text, contains('カフェ・ピンロジー'));
      expect(capture.request?.text, contains('大阪府八尾市本町1丁目1番1号'));
      expect(capture.request?.imageUrls, post.imagePaths);
    });

    test('共有を受信箱へ即保存し解析失敗でも残す', () async {
      final hub = LocalRepositoryHub(InMemoryDataStore());
      await hub.load(seedIfEmpty: false);
      final receiver = LocalShareReceiverService(
        sourcePosts: hub.sourcePosts,
        analysis: hub.analysis,
        analysisService: _FailingAnalysis(),
      );
      final intake = ShareIntakeCoordinator(shareReceiver: receiver);

      final post = await receiver.receive(
        const SharedContent(
          url: 'https://www.instagram.com/p/keep',
          title: '保持テスト',
        ),
        waitForAnalysis: true,
      );

      expect(post.title, '保持テスト');
      expect(hub.snapshot.sourcePosts.any((p) => p.id == post.id), isTrue);
      final job = await hub.analysis.getBySourcePostId(post.id);
      expect(job?.status, AnalysisJobStatus.failed);
      expect(job?.errorMessage, contains('ネットワーク'));

      await intake.dispose();
    });
  });
}

class _CapturingAnalysis implements PostAnalysisService {
  PostAnalysisRequest? request;

  @override
  Future<PostAnalysisResponse> analyze(PostAnalysisRequest request) async {
    this.request = request;
    return PostAnalysisResponse(
      sourcePostId: request.sourcePostId,
      candidates: const [],
    );
  }
}

class _FailingAnalysis implements PostAnalysisService {
  @override
  Future<PostAnalysisResponse> analyze(PostAnalysisRequest request) async {
    throw StateError('SocketException: Failed host lookup');
  }
}
