import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/services/social_post_identity.dart';

void main() {
  group('SocialPostIdentity', () {
    test('Instagram post and reel URLs share the shortcode identity', () {
      final post = SocialPostIdentity.tryParse(
        'https://www.instagram.com/p/AbC_123/?igsh=tracking',
      );
      final reel = SocialPostIdentity.tryParse(
        'https://instagram.com/reel/AbC_123/?utm_source=share',
      );
      expect(post?.key, 'instagram:AbC_123');
      expect(reel?.key, post?.key);
    });

    test('TikTok tracking query does not change video identity', () {
      final first = SocialPostIdentity.tryParse(
        'https://www.tiktok.com/@cook/video/1234567890123456789?share_item_id=1',
      );
      final second = SocialPostIdentity.tryParse(
        'https://m.tiktok.com/@cook/video/1234567890123456789?utm_source=x',
      );
      expect(first?.key, 'tiktok:1234567890123456789');
      expect(second?.key, first?.key);
    });

    test('different posts are not equal', () {
      final first = SocialPostIdentity.tryParse(
        'https://www.instagram.com/p/First01/',
      );
      final second = SocialPostIdentity.tryParse(
        'https://www.instagram.com/p/Second02/',
      );
      expect(first?.key, isNot(second?.key));
    });

    test('fallback removes only known tracking parameters', () {
      final normalized = SocialPostIdentity.normalizedSupportedUrl(
        'https://www.tiktok.com/t/ZShort/?utm_source=x&lang=ja',
      );
      expect(normalized, contains('lang=ja'));
      expect(normalized, isNot(contains('utm_source')));
    });
  });
}
