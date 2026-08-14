const standardPostCategories = <String>[
  'カフェ',
  'ラーメン',
  '焼肉',
  '寿司',
  'スイーツ',
  '居酒屋',
  'グルメ',
  '観光',
  '宿泊',
  'ショッピング',
];

Set<String> suggestPostCategories(String text) {
  const keywords = <String, List<String>>{
    'カフェ': ['カフェ', '喫茶', 'coffee', '珈琲'],
    'ラーメン': ['ラーメン', 'つけ麺', 'まぜそば'],
    '焼肉': ['焼肉', 'ホルモン'],
    '寿司': ['寿司', '鮨', '海鮮'],
    'スイーツ': ['スイーツ', 'ケーキ', 'パフェ', 'ベーカリー', 'パン'],
    '居酒屋': ['居酒屋', 'バル', '酒場'],
    'グルメ': ['レストラン', 'ランチ', 'ディナー', 'ごはん', '食堂'],
    '観光': ['観光', '神社', '寺', '美術館', '博物館', '公園'],
    '宿泊': ['ホテル', '旅館', '宿泊'],
    'ショッピング': ['ショップ', '雑貨', '買い物'],
  };
  final lower = text.toLowerCase();
  return {
    for (final entry in keywords.entries)
      if (entry.value.any(lower.contains)) entry.key,
  };
}
