import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/recipe/data/analysis_thumbnail.dart';

void main() {
  test('selected frame is used without reordering evidence paths', () {
    final paths = ['/preview.jpg', '/frame1.jpg', '/frame2.jpg'];
    expect(
      analysisThumbnailPath({
        'shared_media': {'thumbnail_index': 2},
      }, paths),
      '/frame2.jpg',
    );
    expect(paths, ['/preview.jpg', '/frame1.jpg', '/frame2.jpg']);
  });
  test(
    'older results and invalid indices safely use first available image',
    () {
      for (final index in [null, -1, 99, 0.5]) {
        expect(
          analysisThumbnailPath(
            {
              'shared_media': {'thumbnail_index': index},
            },
            ['/first.jpg'],
          ),
          '/first.jpg',
        );
      }
      expect(analysisThumbnailPath({}, []), isNull);
    },
  );
}
