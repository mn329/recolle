import 'package:flutter/material.dart';

/// アプリに同梱しているフォント（`assets/fonts`、ライセンスは同ディレクトリの OFL-*.txt）。
///
/// Bebas Neue / DM Mono は欧文のみのため、和文は本文フォントへフォールバックさせる。
abstract final class AppFonts {
  AppFonts._();

  /// 本文・和文全般。
  static const String body = 'ZenKakuGothicNew';

  /// チケットの印字風の英字見出し（大文字のみのデザイン）。
  static const String display = 'BebasNeue';

  /// 日付・番号などの等幅数字。
  static const String mono = 'DMMono';

  static const List<String> _fallback = [body];

  /// チケットタイトルなど、英字は Bebas Neue・和文は太字ゴシックで出す見出し。
  static TextStyle displayStyle({
    required double fontSize,
    Color? color,
    double letterSpacing = 0.6,
    List<Shadow>? shadows,
  }) {
    return TextStyle(
      fontFamily: display,
      fontFamilyFallback: _fallback,
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: letterSpacing,
      height: 1.15,
      color: color,
      shadows: shadows,
    );
  }

  /// 日付・数字用。和文（年・月・曜日）が混ざっても本文フォントで表示される。
  static TextStyle monoStyle({
    required double fontSize,
    Color? color,
    FontWeight fontWeight = FontWeight.w500,
  }) {
    return TextStyle(
      fontFamily: mono,
      fontFamilyFallback: _fallback,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }
}
