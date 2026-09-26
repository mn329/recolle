import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_fonts.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      // Android 端末でも iOS と同じ遷移（右からスライド・左端スワイプで戻る）、
      // バウンススクロール、戻るボタンの山括弧、中央寄せタイトルにそろえる
      platform: TargetPlatform.iOS,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.gold,
        onPrimary: Colors.black,
        surface: AppColors.background,
        onSurface: AppColors.textPrimary,
        error: AppColors.destructive,
      ),
      useMaterial3: true,
      fontFamily: AppFonts.body,
      // iOS はタップで波紋を出さず、押している間だけ淡くハイライトする
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.white.withValues(alpha: 0.06),
      dividerColor: AppColors.separator,
      cupertinoOverrideTheme: const CupertinoThemeData(
        brightness: Brightness.dark,
        primaryColor: AppColors.gold,
        scaffoldBackgroundColor: AppColors.background,
        barBackgroundColor: AppColors.bar,
        textTheme: CupertinoTextThemeData(
          primaryColor: AppColors.gold,
          textStyle: TextStyle(
            fontFamily: AppFonts.body,
            fontSize: 16,
            color: AppColors.textPrimary,
            letterSpacing: -0.2,
          ),
          navTitleTextStyle: TextStyle(
            fontFamily: AppFonts.body,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
          navLargeTitleTextStyle: TextStyle(
            fontFamily: AppFonts.body,
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.4,
          ),
          actionTextStyle: TextStyle(
            fontFamily: AppFonts.body,
            fontSize: 17,
            color: AppColors.gold,
          ),
          dateTimePickerTextStyle: TextStyle(
            fontFamily: AppFonts.body,
            fontSize: 21,
            color: AppColors.textPrimary,
          ),
          pickerTextStyle: TextStyle(
            fontFamily: AppFonts.body,
            fontSize: 21,
            color: AppColors.textPrimary,
          ),
        ),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.scrolledUnder)
              ? AppColors.card
              : AppColors.background,
        ),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: const TextStyle(
          fontFamily: AppFonts.body,
          color: AppColors.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: const IconThemeData(color: AppColors.gold),
        actionsIconTheme: const IconThemeData(color: AppColors.gold),
      ),

      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.gold,
        selectionColor: Color(0x55D4AF37),
        selectionHandleColor: AppColors.gold,
      ),
    );
  }
}
