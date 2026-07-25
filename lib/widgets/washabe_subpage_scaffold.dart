import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// 設定・ヘルプなどのサブ画面用（メイン画面の暗色テーマを継承しない）
class WashabeSubpageScaffold extends StatelessWidget {
  const WashabeSubpageScaffold({
    super.key,
    this.title = '',
    this.titleWidget,
    required this.body,
    this.actions,
    this.leading,
    this.appBarColor,
    this.appBarForegroundColor,
  });

  final String title;
  final Widget? titleWidget;
  final Widget body;
  final List<Widget>? actions;
  final Widget? leading;
  final Color? appBarColor;
  final Color? appBarForegroundColor;

  static const _background = Color(0xFFF2F2F7);

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Theme(
        data: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          scaffoldBackgroundColor: _background,
          appBarTheme: AppBarTheme(
            backgroundColor: appBarColor ?? _background,
            foregroundColor: appBarForegroundColor ?? Colors.black,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: true,
            systemOverlayStyle: appBarColor != null
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
          ),
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.blue,
            brightness: Brightness.light,
          ),
        ),
        child: Scaffold(
          backgroundColor: _background,
          appBar: AppBar(
            title: titleWidget ?? Text(title),
            leading: leading,
            actions: actions,
          ),
          body: body,
        ),
      ),
    );
  }
}
