import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../notifiers/app_settings.dart';
import '../../services/android_ringtone_service.dart';
import '../../services/timer_alert.dart';
import '../../services/timer_completion_sound_catalog.dart';
import '../../widgets/swipe_down_to_dismiss.dart';
import '../../widgets/washabe_subpage_scaffold.dart';

class TimerSoundPickerView extends StatefulWidget {
  const TimerSoundPickerView({
    super.key,
    required this.settings,
    required this.timerAlert,
    required this.languageCode,
  });

  final AppSettingsNotifier settings;
  final TimerAlert timerAlert;
  final String languageCode;

  @override
  State<TimerSoundPickerView> createState() => _TimerSoundPickerViewState();
}

class _TimerSoundPickerViewState extends State<TimerSoundPickerView> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SwipeDownToDismiss(
      scrollController: _scrollController,
      child: WashabeSubpageScaffold(
        title: 'タイマー音'.tr(widget.languageCode),
        leading: const SizedBox.shrink(),
        body: Platform.isAndroid
            ? _AndroidSoundPicker(
                settings: widget.settings,
                lang: widget.languageCode,
                scrollController: _scrollController,
              )
            : _IosSoundPicker(
                settings: widget.settings,
                timerAlert: widget.timerAlert,
                lang: widget.languageCode,
                scrollController: _scrollController,
              ),
      ),
    );
  }
}

class _IosSoundPicker extends StatefulWidget {
  const _IosSoundPicker({
    required this.settings,
    required this.timerAlert,
    required this.lang,
    required this.scrollController,
  });

  final AppSettingsNotifier settings;
  final TimerAlert timerAlert;
  final String lang;
  final ScrollController scrollController;

  @override
  State<_IosSoundPicker> createState() => _IosSoundPickerState();
}

class _IosSoundPickerState extends State<_IosSoundPicker> {
  bool _isSelected(TimerSoundItem item) =>
      widget.settings.completionSound ==
      TimerCompletionSoundCatalog.normalizedStoredValue(item.storedValue);

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: widget.scrollController,
      children: [
        for (final item in TimerCompletionSoundCatalog.allItems)
          ListTile(
            title: Text(item.nameKey.tr(widget.lang)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.playable)
                  IconButton(
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () =>
                        widget.timerAlert.previewSound(item.storedValue),
                  ),
                if (_isSelected(item))
                  const Icon(Icons.check, color: Colors.blue),
              ],
            ),
            onTap: () => setState(() {
              widget.settings.completionSound = item.storedValue;
            }),
          ),
      ],
    );
  }
}

class _AndroidSoundPicker extends StatefulWidget {
  const _AndroidSoundPicker({
    required this.settings,
    required this.lang,
    required this.scrollController,
  });

  final AppSettingsNotifier settings;
  final String lang;
  final ScrollController scrollController;

  @override
  State<_AndroidSoundPicker> createState() => _AndroidSoundPickerState();
}

class _AndroidSoundPickerState extends State<_AndroidSoundPicker> {
  List<AndroidRingtoneItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await AndroidRingtoneService.getRingtones();
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    AndroidRingtoneService.stopRingtone();
    super.dispose();
  }

  bool _isSelected(AndroidRingtoneItem item) =>
      widget.settings.completionSound == item.storedValue;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return Center(child: Text('利用できる音がありません'.tr(widget.lang)));
    }
    return ListView.builder(
      controller: widget.scrollController,
      itemCount: _items.length,
      itemBuilder: (ctx, i) {
        final item = _items[i];
        return ListTile(
          title: Text(item.title),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.play_arrow),
                onPressed: () => AndroidRingtoneService.playRingtone(item.uri),
              ),
              if (_isSelected(item))
                const Icon(Icons.check, color: Colors.blue),
            ],
          ),
          onTap: () {
            widget.settings.completionSound = item.storedValue;
            setState(() {});
          },
        );
      },
    );
  }
}
