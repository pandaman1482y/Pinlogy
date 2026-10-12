import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/services/social_post_identity.dart';

void main() {
  test('写真投稿のIDと追跡パラメータなしのURLを取得する', () {
    final value = SocialPostIdentity.tryParse(
      'https://www.tiktok.com/@cook/photo/1234567890123456789?utm_source=share',
    );
    expect(value?.postId, '1234567890123456789');
    expect(value?.service, 'tiktok');
    expect(
      value?.canonicalUrl,
      'https://tiktok.com/@cook/photo/1234567890123456789',
    );
  });
  test('動画URLの既存判定を維持する', () {
    expect(
      SocialPostIdentity.tryParse(
        'https://www.tiktok.com/@cook/video/1234567890123456789',
      )?.key,
      'tiktok:1234567890123456789',
    );
  });
  test('短縮URLと不正なIDを確定投稿として扱わない', () {
    expect(SocialPostIdentity.tryParse('https://vm.tiktok.com/abc/'), isNull);
    expect(
      SocialPostIdentity.tryParse('https://www.tiktok.com/@cook/photo/abc'),
      isNull,
    );
  });
}
