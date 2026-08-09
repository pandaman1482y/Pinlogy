import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/services/cloud_sync_service.dart';

void main() {
  group('map share link', () {
    final cloud = CloudSyncService();

    test('共有コードからアプリリンクを作成できる', () {
      final uri = cloud.mapShareUri('abc123');
      expect(uri.toString(), 'pinlogy://map-share?code=abc123');
    });

    test('アプリリンクから共有コードを取り出せる', () {
      expect(
        cloud.shareCodeFromText('pinlogy://map-share?code=abc123'),
        'abc123',
      );
    });

    test('共有メッセージ内のリンクと従来コードの両方を受け付ける', () {
      expect(
        cloud.shareCodeFromText(
          'このマップを受け取る pinlogy://map-share?code=abc123 期限30日',
        ),
        'abc123',
      );
      expect(cloud.shareCodeFromText('legacy-code'), 'legacy-code');
    });
  });
}
