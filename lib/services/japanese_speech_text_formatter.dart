/// iOS `JapaneseSpeechTextFormatter` に対応
abstract final class JapaneseSpeechTextFormatter {
  /// 短い文は1塊で読み上げ、長文のみ句点で分割する。
  static List<String> utteranceChunks(String text) {
    final normalized = normalize(text);
    if (normalized.isEmpty) return [];
    if (normalized.length <= 400) return [normalized];

    final chunks = <String>[];
    var current = '';

    for (final character in normalized.split('')) {
      current += character;
      if ('。！？!?'.contains(character)) {
        _appendChunk(current, chunks);
        current = '';
        continue;
      }

      if (character == '、' && current.length >= 120) {
        _appendChunk(current, chunks);
        current = '';
      }
    }

    _appendChunk(current, chunks);
    return chunks.isEmpty ? [normalized] : chunks;
  }

  static String normalize(String text) {
    var result = text;
    result = result.replaceAll('\r\n', '。').replaceAll('\n', '。').replaceAll('\r', '。');
    result = result.replaceAll('?', '？').replaceAll('!', '！');
    result = result.replaceAll('…', '、').replaceAll('・', '、');
    result = result.replaceAll(RegExp(r'。{2,}'), '。');
    result = result.replaceAll(RegExp(r'[ \t　]+'), '');
    return result.trim();
  }

  static void _appendChunk(String raw, List<String> chunks) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;
    chunks.add(trimmed);
  }
}
