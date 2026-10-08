import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_fonts.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData get lightTheme => _build(AppPalette.light);

  static ThemeData get darkTheme => _build(AppPalette.dark);

  static ThemeData _build(AppPalette c) {
    final baseScheme = c.isDark
        ? const ColorScheme.dark()
        : const ColorScheme.light();
    return ThemeData(
      brightness: c.brightness,
      // Android 端末でも iOS と同じ遷移（右からスライド・左端スワイプで戻る）、
      // バウンススクロール、戻るボタンの山括弧、中央寄せタイトルにそろえる
      platform: TargetPlatform.iOS,
      extensions: [c],
      scaffoldBackgroundColor: c.background,
      colorScheme: baseScheme.copyWith(
        primary: c.accent,
        onPrimary: c.onAccent,
        surface: c.background,
        onSurface: c.textPrimary,
        error: c.destructive,
      ),
      useMaterial3: true,
      fontFamily: AppFonts.body,
      // iOS はタップで波紋を出さず、押している間だけ淡くハイライトする
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: c.textPrimary.withValues(alpha: 0.06),
      dividerColor: c.separator,
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: c.brightness,
        primaryColor: c.accent,
        scaffoldBackgroundColor: c.background,
        barBackgroundColor: c.bar,
        textTheme: CupertinoTextThemeData(
          primaryColor: c.accent,
          textStyle: TextStyle(
            fontFamily: AppFonts.body,
            fontSize: 16,
            color: c.textPrimary,
            letterSpacing: -0.2,
          ),
          navTitleTextStyle: TextStyle(
            fontFamily: AppFonts.body,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: c.textPrimary,
          ),
          navLargeTitleTextStyle: TextStyle(
            fontFamily: AppFonts.body,
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: c.textPrimary,
            letterSpacing: -0.4,
          ),
          actionTextStyle: TextStyle(
            fontFamily: AppFonts.body,
            fontSize: 17,
            color: c.accent,
          ),
          dateTimePickerTextStyle: TextStyle(
            fontFamily: AppFonts.body,
            fontSize: 21,
            color: c.textPrimary,
          ),
          pickerTextStyle: TextStyle(
            fontFamily: AppFonts.body,
            fontSize: 21,
            color: c.textPrimary,
          ),
        ),
      ),

      appBarTheme: AppBarTheme(
        // スクロール前は透かして、画面の地（AppBackground）の光をナビバーの裏まで見せる
        backgroundColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.scrolledUnder)
              ? c.card
              : Colors.transparent,
        ),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: AppFonts.body,
          color: c.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: c.accent),
        actionsIconTheme: IconThemeData(color: c.accent),
      ),

      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.accent,
        selectionColor: c.accent.withValues(alpha: 0.33),
        selectionHandleColor: c.accent,
      ),
    );
  }
}
