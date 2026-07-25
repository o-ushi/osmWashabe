import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_strings.dart';

enum CrashLogShareResult {
  /// GAS Webhook へ自動送信成功
  sent,

  /// Gmail 等のメール作成画面を開いた
  emailComposerOpened,

  /// 送信・共有のいずれも失敗
  failed,
}

abstract final class CrashLogService {
  static const _fileName = 'osm_crash_log.txt';
  static const _maxLines = 500;
  static const _shareChannel =
      MethodChannel('com.osamushikubo.osm_washabe/log_share');

  /// クラッシュログの受信先（GAS の LOG_RECIPIENT と揃える）
  static const _developerEmail = 'osam.in.az@gmail.com';

  // GAS「デプロイ」→「ウェブアプリ URL」のコピー（デプロイ ID 欄とは別）
  static const _webhookUrl =
      'https://script.google.com/macros/s/AKfycbwpMxu5XDk8gxCLgmI9TCt6AGRmt7hp15aGeJVVS-_5cOB0GYRXTFOyKDoLDjjLFs0dbg/exec';

  static Future<File> _logFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<void> init() async {
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      prevOnError?.call(details);
      unawaited(logCrash(details.exception, details.stack));
    };
    await log('--- セッション開始 (${Platform.operatingSystem}) ---');
  }

  static Future<void> log(String message) async {
    try {
      final stamp = DateTime.now().toIso8601String().substring(0, 19);
      final line = '$stamp $message\n';
      final file = await _logFile();
      await file.writeAsString(line, mode: FileMode.append, flush: true);
      await _trimIfNeeded(file);
    } catch (_) {}
  }

  static Future<void> logCrash(Object error, StackTrace? stack) async {
    final buf = StringBuffer('=== CRASH ===\n');
    buf.writeln(error);
    if (stack != null) {
      final lines = stack.toString().split('\n');
      buf.writeAll(lines.take(25), '\n');
      buf.writeln();
    }
    buf.writeln('=== END CRASH ===');
    await log(buf.toString());
  }

  static Future<void> _trimIfNeeded(File file) async {
    try {
      final content = await file.readAsString();
      final lines = content.split('\n');
      if (lines.length > _maxLines + 50) {
        final kept = lines.skip(lines.length - _maxLines).join('\n');
        await file.writeAsString(kept, flush: true);
      }
    } catch (_) {}
  }

  static Future<String> readLog() async {
    try {
      final file = await _logFile();
      if (!await file.exists()) return '';
      return await file.readAsString();
    } catch (_) {
      return '';
    }
  }

  static Future<void> clearLog() async {
    try {
      final file = await _logFile();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Android: ネイティブクラッシュログ（Kotlin UncaughtExceptionHandler が書いたもの）を取得。
  static Future<String> readNativeCrashLog() async {
    if (!Platform.isAndroid) return '';
    try {
      final result =
          await _shareChannel.invokeMethod<String>('getNativeCrashLog');
      return result ?? '';
    } catch (_) {
      return '';
    }
  }

  /// ログ全体（Dartログ + ネイティブクラッシュログ）を結合して返す。
  static Future<String> readAllLogs() async {
    final dartLog = await readLog();
    final nativeLog = await readNativeCrashLog();
    if (nativeLog.isEmpty) return dartLog;
    return '$dartLog\n--- ネイティブクラッシュログ ---\n$nativeLog';
  }

  static Future<String> _buildShareBody(String languageCode) async {
    final content = await readAllLogs();
    if (content.isEmpty) return 'ログ_空'.tr(languageCode);
    if (content.length <= 60000) return content;
    return 'ログ_先頭省略'.tr(languageCode) +
        content.substring(content.length - 60000);
  }

  /// Opens an email composer only. It never falls back to a network POST.
  static Future<CrashLogShareResult> shareViaEmail({
    required String languageCode,
  }) async {
    final body = await _buildShareBody(languageCode);
    if (await _shareViaNativeIntent(body, languageCode)) {
      return CrashLogShareResult.emailComposerOpened;
    }
    return CrashLogShareResult.failed;
  }

  /// Sends directly to the configured Google Apps Script webhook only.
  static Future<CrashLogShareResult> shareViaWebhook({
    required String languageCode,
  }) async {
    final body = await _buildShareBody(languageCode);
    if (await _postToWebhook(body, languageCode)) {
      return CrashLogShareResult.sent;
    }
    return CrashLogShareResult.failed;
  }

  static Future<bool> _shareViaNativeIntent(
    String body,
    String languageCode,
  ) async {
    if (!Platform.isAndroid) {
      return _launchMailtoComposer(body, languageCode);
    }
    try {
      final ok = await _shareChannel.invokeMethod<bool>('shareLog', {
        'email': _developerEmail,
        'content': body,
        'subject': 'クラッシュログ_メール件名'.tr(languageCode),
        'chooserTitle': 'クラッシュログ_メール送信'.tr(languageCode),
        'truncationPrefix': 'ログ_先頭省略'.tr(languageCode),
      });
      if (ok == true) return true;
    } catch (e, st) {
      debugPrint('osmWashabe: ネイティブメール起動失敗: $e\n$st');
    }
    return _launchMailtoComposer(body, languageCode);
  }

  /// Kotlin 経由が失敗したときの予備: mailto でメールアプリを開く。
  static Future<bool> _launchMailtoComposer(
    String body,
    String languageCode,
  ) async {
    try {
      final prefix = 'ログ_先頭省略'.tr(languageCode);
      final clipped = body.length > 3500
          ? prefix + body.substring(body.length - 3500)
          : body;
      final uri = Uri(
        scheme: 'mailto',
        path: _developerEmail,
        queryParameters: {
          'subject': 'クラッシュログ_メール件名'.tr(languageCode),
          'body': clipped,
        },
      );
      if (!await canLaunchUrl(uri)) return false;
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e, st) {
      debugPrint('osmWashabe: mailto 起動失敗: $e\n$st');
      return false;
    }
  }

  static Future<bool> _postToWebhook(String body, String languageCode) async {
    if (_webhookUrl.startsWith('PASTE_')) return false;

    final payload = jsonEncode({
      'subject': 'クラッシュログ_メール件名'.tr(languageCode),
      'body': body,
    });

    try {
      final response = await _postToGasWebApp(payload);
      final ok = _isWebhookSuccess(response);
      if (!ok) {
        debugPrint(
          'osmWashabe: Webhook 失敗 status=${response.statusCode} '
          'body=${response.body.length > 300 ? response.body.substring(0, 300) : response.body}',
        );
      }
      return ok;
    } catch (e, st) {
      debugPrint('osmWashabe: Webhook 例外: $e\n$st');
      return false;
    }
  }

  /// GAS ウェブアプリは 302 で googleusercontent へ飛ぶ。POST 本文を保ったまま追従する。
  static Future<http.Response> _postToGasWebApp(String payload) async {
    final client = http.Client();
    try {
      var uri = Uri.parse(_webhookUrl);
      for (var hop = 0; hop < 5; hop++) {
        final request = http.Request('POST', uri)
          ..headers['Content-Type'] = 'application/json; charset=utf-8'
          ..body = payload
          ..followRedirects = false;
        final streamed =
            await client.send(request).timeout(const Duration(seconds: 30));
        final response = await http.Response.fromStream(streamed);

        final code = response.statusCode;
        if (code == 302 || code == 303 || code == 307 || code == 308) {
          final location = response.headers['location'];
          if (location == null || location.isEmpty) return response;
          uri = Uri.parse(location);
          continue;
        }
        return response;
      }
      throw StateError('GAS webhook: too many redirects');
    } finally {
      client.close();
    }
  }

  static bool _isWebhookSuccess(http.Response response) {
    final body = response.body.trim();
    if (body.contains('<!DOCTYPE') ||
        body.contains('Không tìm thấy') ||
        body.contains('doPost') ||
        body.contains('Lỗi')) {
      return false;
    }
    if (body.contains('"result":"ok"') || body.contains('"result": "ok"')) {
      return true;
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['result'] == 'ok') return true;
    } catch (_) {}
    return false;
  }
}
