import 'dart:io';

import 'package:flutter/services.dart';

class AndroidRingtoneItem {
  const AndroidRingtoneItem({required this.uri, required this.title});

  final String uri;
  final String title;

  String get storedValue => 'android_ringtone:$uri|$title';
}

abstract final class AndroidRingtoneService {
  static const _channel = MethodChannel('com.osamushikubo.osm_washabe/ringtones');

  static bool get isSupported => Platform.isAndroid;

  static AndroidRingtoneItem? fromStoredValue(String value) {
    if (!value.startsWith('android_ringtone:')) return null;
    final rest = value.substring('android_ringtone:'.length);
    final sep = rest.indexOf('|');
    if (sep < 0) return AndroidRingtoneItem(uri: rest, title: rest);
    return AndroidRingtoneItem(
      uri: rest.substring(0, sep),
      title: rest.substring(sep + 1),
    );
  }

  static Future<List<AndroidRingtoneItem>> getRingtones() async {
    if (!isSupported) return [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('getRingtones');
      if (raw == null) return [];
      return raw.whereType<Map<Object?, Object?>>().map((m) {
        return AndroidRingtoneItem(
          uri: m['uri']?.toString() ?? '',
          title: m['title']?.toString() ?? '',
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> playRingtone(String uri) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('play', uri);
    } catch (_) {}
  }

  static Future<void> stopRingtone() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }
}
