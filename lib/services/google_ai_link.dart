import 'package:url_launcher/url_launcher.dart';

/// iOS `GoogleAIModeLink` に対応
abstract final class GoogleAiLink {
  static Uri webSearchUrl({required String prompt}) {
    final query = _searchQuery(prompt);
    final uri = Uri.https('www.google.co.jp', '/search', {
      'q': query,
      'udm': '50',
      'hl': 'ja',
      'gl': 'jp',
      'ie': 'UTF-8',
    });
    if (uri.toString().length <= 7500) return uri;
    return Uri.https('www.google.co.jp', '/search', {
      'udm': '50',
      'hl': 'ja',
      'gl': 'jp',
    });
  }

  static Future<bool> openWithPrompt(String prompt) async {
    final web = webSearchUrl(prompt: prompt);
    final chrome = web.replace(scheme: 'googlechromes');
    if (await canLaunchUrl(chrome)) {
      return launchUrl(chrome, mode: LaunchMode.externalApplication);
    }
    return launchUrl(web, mode: LaunchMode.externalApplication);
  }

  static String _searchQuery(String prompt) {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) return '日本語で ';
    if (trimmed.startsWith('日本語で')) return trimmed;
    return '日本語で $trimmed';
  }
}
