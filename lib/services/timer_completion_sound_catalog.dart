import '../l10n/app_strings.dart';

class TimerSoundItem {
  const TimerSoundItem({
    required this.storedValue,
    required this.nameKey,
    this.soundId,
    this.playable = true,
  });

  final String storedValue;
  final String nameKey;
  final int? soundId;
  final bool playable;
}

/// iOS `TimerCompletionSoundCatalog` に対応
abstract final class TimerCompletionSoundCatalog {
  static const noneStoredValue = 'none';
  static const defaultStoredValue = '1307';

  static const noneItem = TimerSoundItem(
    storedValue: noneStoredValue,
    nameKey: '通知音_なし',
    playable: false,
  );

  static const defaultNotificationItems = [
    TimerSoundItem(storedValue: '1307', soundId: 1307, nameKey: '通知音_三連音'),
    TimerSoundItem(storedValue: '1320', soundId: 1320, nameKey: '通知音_アンティシペート'),
    TimerSoundItem(storedValue: '1321', soundId: 1321, nameKey: '通知音_ブルーム'),
    TimerSoundItem(storedValue: '1322', soundId: 1322, nameKey: '通知音_カリプソ'),
    TimerSoundItem(storedValue: '1323', soundId: 1323, nameKey: '通知音_チューチュー'),
    TimerSoundItem(storedValue: '1324', soundId: 1324, nameKey: '通知音_ディセント'),
    TimerSoundItem(storedValue: '1325', soundId: 1325, nameKey: '通知音_ファンファーレ'),
    TimerSoundItem(storedValue: '1326', soundId: 1326, nameKey: '通知音_ラダー'),
    TimerSoundItem(storedValue: '1327', soundId: 1327, nameKey: '通知音_メヌエット'),
    TimerSoundItem(storedValue: '1328', soundId: 1328, nameKey: '通知音_ニュース'),
    TimerSoundItem(storedValue: '1329', soundId: 1329, nameKey: '通知音_ノワール'),
    TimerSoundItem(storedValue: '1330', soundId: 1330, nameKey: '通知音_シャーウッド'),
    TimerSoundItem(storedValue: '1331', soundId: 1331, nameKey: '通知音_スペル'),
    TimerSoundItem(storedValue: '1332', soundId: 1332, nameKey: '通知音_サスペンス'),
    TimerSoundItem(storedValue: '1333', soundId: 1333, nameKey: '通知音_テレグラフ'),
    TimerSoundItem(storedValue: '1334', soundId: 1334, nameKey: '通知音_ティプトゥ'),
    TimerSoundItem(storedValue: '1335', soundId: 1335, nameKey: '通知音_タイプライター'),
    TimerSoundItem(storedValue: '1336', soundId: 1336, nameKey: '通知音_アップデート'),
  ];

  static List<TimerSoundItem> get allItems => [noneItem, ...defaultNotificationItems];

  static String normalizedStoredValue(String raw) {
    if (raw.startsWith('android_ringtone:')) return raw;
    if (raw.startsWith('ios_sound:') || raw.startsWith('file:')) {
      return defaultStoredValue;
    }
    if (allItems.any((i) => i.storedValue == raw)) return raw;
    const legacy = {
      'none': noneStoredValue,
      '1007': defaultStoredValue,
      '1315': defaultStoredValue,
      'pinPoon': defaultStoredValue,
      'pinPoonFast': defaultStoredValue,
      'tink': defaultStoredValue,
      'glass': defaultStoredValue,
      'newMail': defaultStoredValue,
      'alarm': defaultStoredValue,
      '1057': defaultStoredValue,
      '1016': defaultStoredValue,
      '1005': defaultStoredValue,
      '1304': defaultStoredValue,
    };
    if (legacy.containsKey(raw)) return legacy[raw]!;
    return defaultStoredValue;
  }

  static TimerSoundItem? itemFor(String storedValue) {
    final normalized = normalizedStoredValue(storedValue);
    for (final item in allItems) {
      if (item.storedValue == normalized) return item;
    }
    return null;
  }

  static String displayName(String storedValue, String languageCode) {
    // Android ringtone: "android_ringtone:uri|title"
    if (storedValue.startsWith('android_ringtone:')) {
      final rest = storedValue.substring('android_ringtone:'.length);
      final sep = rest.indexOf('|');
      if (sep >= 0) return rest.substring(sep + 1);
      return rest;
    }
    final item = itemFor(storedValue);
    if (item == null) return '通知音_不明'.tr(languageCode);
    return item.nameKey.tr(languageCode);
  }
}
