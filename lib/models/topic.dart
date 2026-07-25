/// お題カテゴリ（iOS `TopicCategory` に対応）
enum TopicCategory {
  daily('日常の身近な話題'),
  business('ビジネスシーン'),
  /// 15+60秒モードでのみ表示されるシチュエーション問題カテゴリ
  situation('シチュエーション'),
  random('ランダム');

  const TopicCategory(this.label);
  final String label;
}

/// 通常モード用お題
class Topic {
  const Topic({
    required this.id,
    required this.text,
    required this.category,
  });

  final String id;
  final String text;
  final TopicCategory category;
}

/// シチュエーションプロンプト（iOS `SituationPrompt` に対応）
class SituationPrompt {
  const SituationPrompt({
    required this.situation,
    required this.condition,
  });

  final String situation;
  final String condition;

  String get id => '$situation|$condition';

  String get readableText => '$situation。守るべき条件は、$condition';

  factory SituationPrompt.fromJson(Map<String, dynamic> json) {
    return SituationPrompt(
      situation: json['situation'] as String? ?? '',
      condition: json['condition'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'situation': situation,
        'condition': condition,
      };
}
