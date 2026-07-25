import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Android 採点専用: 無音録音と Vosk 文字起こしのプラットフォーム API。
abstract final class AndroidOfflineSpeechPlatform {
  static const _channel =
      MethodChannel('com.osamushikubo.osm_washabe/offline_speech');
  static const _progressChannel =
      EventChannel('com.osamushikubo.osm_washabe/offline_speech_progress');

  static Stream<double>? _transcribeProgressStream;

  static bool get isSupported => Platform.isAndroid;

  static Future<bool> hasRecordPermission() async {
    if (!isSupported) return false;
    final granted = await _channel.invokeMethod<bool>('hasRecordPermission');
    return granted ?? false;
  }

  static Future<bool> requestRecordPermission() async {
    if (!isSupported) return false;
    final granted =
        await _channel.invokeMethod<bool>('requestRecordPermission');
    return granted ?? false;
  }

  static Future<bool> startRecording() async {
    if (!isSupported) return false;
    final ok = await _channel.invokeMethod<bool>('startRecording');
    return ok ?? false;
  }

  static Future<String?> stopRecording() async {
    if (!isSupported) return null;
    final path = await _channel.invokeMethod<String>('stopRecording');
    if (path == null || path.isEmpty) return null;
    return path;
  }

  static Future<void> cancelRecording() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('cancelRecording');
  }

  /// Vosk 文字起こし中の進捗（0.0〜1.0）。[transcribe] 呼び出し前から購読する。
  static Stream<double> transcribeProgressStream() {
    if (!isSupported) return const Stream.empty();
    return _transcribeProgressStream ??= _progressChannel
        .receiveBroadcastStream()
        .map((event) => (event as num).toDouble());
  }

  /// 録音済み[wavPath]をオンラインのSpeechRecognizerに渡して文字起こしを試みる。
  /// 端末がオンライン認識に対応していない/失敗した場合はnullを返す
  /// （呼び出し側でVoskオフライン文字起こしにフォールバックする）。
  /// [onFailureReason]には失敗理由（recognizer_unavailable/recognizer_error:ERROR_NO_MATCH等）が渡る。
  static Future<String?> recognizeOnline(
    String wavPath, {
    void Function(String reason)? onFailureReason,
  }) async {
    if (!isSupported) return null;
    try {
      final raw = await _channel
          .invokeMethod<Map>('recognizeOnline', {'wavPath': wavPath})
          .timeout(const Duration(seconds: 20));
      final text = raw?['text'] as String?;
      final trimmed = text?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
      final reason = raw?['reason'] as String?;
      if (reason != null) onFailureReason?.call(reason);
      return null;
    } catch (e) {
      onFailureReason?.call('channel_exception:$e');
      return null;
    }
  }

  static Future<List<OfflineSpeechSegment>> transcribe({
    required String modelPath,
    required String wavPath,
  }) async {
    if (!isSupported) return const [];
    final raw = await _channel.invokeMethod<List<dynamic>>(
      'transcribe',
      {
        'modelPath': modelPath,
        'wavPath': wavPath,
      },
    );
    if (raw == null) return const [];
    return raw
        .map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          return OfflineSpeechSegment(
            text: map['text'] as String? ?? '',
            startSec: (map['startSec'] as num?)?.toDouble() ?? 0,
          );
        })
        .where((segment) => segment.text.trim().isNotEmpty)
        .toList(growable: false);
  }
}

class OfflineSpeechSegment {
  const OfflineSpeechSegment({
    required this.text,
    required this.startSec,
  });

  final String text;
  final double startSec;
}
