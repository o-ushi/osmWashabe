import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Vosk 日本語 small モデルの初回展開と配置。APK にバンドルされた ZIP を使う。
abstract final class VoskModelManager {
  static const modelDirName = 'vosk-model-small-ja-0.22';

  /// アセットバンドル内の ZIP パス。
  static const _assetZipPath = 'assets/vosk/$modelDirName.zip';

  static Completer<void>? _prepareCompleter;

  /// 並行する ensureReady() 呼び出しすべてに進捗を届けるリスナーリスト。
  static final List<void Function(double)> _progressListeners = [];

  static void _emitProgress(double value) {
    for (final cb in List.of(_progressListeners)) {
      cb(value);
    }
  }

  static Future<bool> isReady() async {
    final dir = await _modelDirectory();
    return File('${dir.path}/am/final.mdl').existsSync();
  }

  static Future<String> modelPath() async {
    final dir = await _modelDirectory();
    return dir.path;
  }

  static Future<void> clearCache() async {
    try {
      final dir = await _modelDirectory();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
    try {
      final tempDir = await getTemporaryDirectory();
      final zipFile = File('${tempDir.path}/$modelDirName.zip');
      if (await zipFile.exists()) await zipFile.delete();
    } catch (_) {}
  }

  /// モデルが未配置なら APK バンドル済み ZIP を展開する。
  static Future<void> ensureReady({
    void Function(double progress)? onProgress,
  }) async {
    if (await isReady()) {
      onProgress?.call(1);
      return;
    }

    if (onProgress != null) _progressListeners.add(onProgress);
    try {
      if (_prepareCompleter != null) {
        await _prepareCompleter!.future;
        return;
      }

      final completer = Completer<void>();
      _prepareCompleter = completer;
      try {
        await _extractBundledModel();
        completer.complete();
      } catch (e, st) {
        completer.completeError(e, st);
        rethrow;
      } finally {
        _prepareCompleter = null;
      }
    } finally {
      if (onProgress != null) _progressListeners.remove(onProgress);
    }
  }

  static Future<Directory> _modelDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/$modelDirName');
  }

  static Future<void> _extractBundledModel() async {
    final modelDir = await _modelDirectory();
    if (await isReady()) {
      _emitProgress(1);
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final zipFile = File('${tempDir.path}/$modelDirName.zip');
    if (zipFile.existsSync()) await zipFile.delete();

    _emitProgress(0.05);
    final data = await rootBundle.load(_assetZipPath);
    _emitProgress(0.5);
    await zipFile.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    _emitProgress(0.7);

    if (modelDir.existsSync()) {
      await modelDir.delete(recursive: true);
    }
    await modelDir.create(recursive: true);

    await extractFileToDisk(zipFile.path, modelDir.parent.path);
    _emitProgress(1);
    await zipFile.delete();

    if (!await isReady()) {
      throw StateError('Vosk model extraction failed');
    }
  }
}
