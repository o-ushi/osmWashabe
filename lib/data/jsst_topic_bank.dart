import '../models/topic.dart';

/// iOS `JSSTTopicBank` と同じ内蔵お題
abstract final class JsstTopicBank {
  static const List<String> dailyTopics = [
    'あなたの趣味について、その魅力を説明してください。',
    '最近読んだ本や見た映画の中で、印象に残っているものと、その理由を教えてください。',
    '子供の頃の一番楽しかった思い出について話してください。',
    'あなたの好きな食べ物と、それが好きな理由を教えてください。',
    '休日はどのように過ごしていますか。その理由も含めて説明してください。',
    'あなたの故郷、または今住んでいる場所の良いところを1つ紹介してください。',
    '健康のために普段からしていることと、その効果について話してください。',
    '最近始めたこと、または始めてみたいことについて話してください。',
    'あなたにとって大切な人について、その人のどんなところが好きか説明してください。',
    'あなたの一年で一番好きな季節と、その理由を教えてください。',
  ];

  static const List<String> businessTopics = [
    '初めて会う取引先と名刺交換をする場面を想定し、自己紹介に含めるべき内容を説明してください。',
    '会議で自分の意見と反対の意見が出た時、どのように対応すべきだと思いますか。',
    '上司に報告・連絡・相談をする際、最も大切だと思うことは何ですか。',
    '電話で取引先に用件を伝える際、気をつけるべき点を説明してください。',
    'チームで仕事を進める上で、大切にすべきことは何だと思いますか。',
    '業務でミスをした時、まず取るべき行動とその理由を説明してください。',
    '新しい社員が職場に馴染むために、先輩としてできることは何だと思いますか。',
    '納期に間に合いそうにない時、どのように対応しますか。',
    'ビジネスメールを書く際に、特に気をつけていることはありますか。',
    '理想的な職場の人間関係について、あなたの考えを話してください。',
  ];

  static const List<String> supplementTopics = [
    '在宅勤務（リモートワーク）のメリットとデメリットについて話してください。',
    'SNSを利用することについて、あなたはどう思いますか。その理由も教えてください。',
    '日本の電車が時間どおりに運行されることについて、海外の人に説明してください。',
    '環境問題について、個人ができる取り組みを1つ挙げて説明してください。',
    '日本へ来る外国人観光客が増えていることについて、あなたの考えを話してください。',
    'コンビニエンスストアの便利さについて、具体例を挙げて説明してください。',
    'これからの日本で、若者が大切にすべきことは何だと思いますか。',
    '挨拶の大切さについて、あなたの経験を交えて話してください。',
    '日本の食文化の特徴を、外国人に説明してください。',
    '学び続けること（生涯学習）について、あなたの考えを話してください。',
  ];

  static const List<SituationPrompt> situationPrompts = [
    SituationPrompt(
      situation: '重要な会議に5分遅れそうです。上司に電話してください。',
      condition: '丁寧な敬語でお詫びし、遅れる理由と到着予定時刻を伝えてください。',
    ),
    SituationPrompt(
      situation: '取引先から依頼された資料の納期を1日延ばしてほしいと言われました。担当者に相談してください。',
      condition: '現在の進捗を説明し、誠意を持って交渉してください。',
    ),
    SituationPrompt(
      situation: '後輩が作成した資料にミスを見つけました。本人に伝えてください。',
      condition: '後輩のやる気を損なわないよう、配慮しながら具体的に指摘してください。',
    ),
    SituationPrompt(
      situation: '体調不良のため、本日の出勤を休みたいです。上司に連絡してください。',
      condition: '現在の状況を伝え、業務の引き継ぎについてお願いしてください。',
    ),
    SituationPrompt(
      situation: '他部署の同僚に、新しいプロジェクトへの協力を依頼したいです。',
      condition: 'プロジェクトの目的と、協力をお願いする理由を丁寧に説明してください。',
    ),
    SituationPrompt(
      situation: 'お客様から「商品の使い方が分からない」と電話がありました。',
      condition: 'お客様の気持ちに寄り添い、確認のうえ折り返す旨を丁寧にお伝えください。',
    ),
    SituationPrompt(
      situation: '社内の歓迎会の幹事を任されました。先輩に参加をお誘いしてください。',
      condition: '日時・場所・目的を伝え、参加していただけるよう丁寧にお願いしてください。',
    ),
    SituationPrompt(
      situation: '上司から指示された業務の進め方に疑問があります。確認したいです。',
      condition: '上司への敬意を示しつつ、クッション言葉を使って質問してください。',
    ),
    SituationPrompt(
      situation: '急な用事のため、明日の有給休暇を取得したいです。上司に相談してください。',
      condition: '急な申請であることをお詫びし、業務への影響が出ないよう配慮を伝えてください。',
    ),
    SituationPrompt(
      situation: '取引先の担当者が、提示した見積もりに納得していない様子です。',
      condition: '自社の強みを説明し、双方が納得できる提案をしてください。',
    ),
  ];

  static List<String> builtInTopics(TopicCategory category) {
    switch (category) {
      case TopicCategory.daily:
        return dailyTopics;
      case TopicCategory.business:
        return businessTopics;
      case TopicCategory.situation:
        return situationPrompts.map((s) => s.readableText).toList();
      case TopicCategory.random:
        return [...dailyTopics, ...businessTopics, ...supplementTopics];
    }
  }
}
