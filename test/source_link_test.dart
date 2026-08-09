import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/models/models.dart';
import 'package:pinlogy/services/source_link_service.dart';

void main() {
  final links = SourceLinkService();

  test('Instagram URLを開ける対象として判定する', () {
    final post = SourcePost(
      title: '京都カフェ',
      service: 'Instagram',
      url: 'https://www.instagram.com/p/example',
    );
    expect(links.canOpen(post), isTrue);
    expect(links.serviceLabel(post), 'Instagram');
  });

  test('URLなしは開けない', () {
    final post = SourcePost(title: '画像だけ', service: 'スクリーンショット');
    expect(links.canOpen(post), isFalse);
  });

  test('TikTok URLからサービス名を推定する', () {
    final post = SourcePost(url: 'https://www.tiktok.com/@x/video/1');
    expect(links.serviceLabel(post), 'TikTok');
    expect(links.canOpen(post), isTrue);
  });
}
