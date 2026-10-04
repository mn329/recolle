import 'package:flutter/material.dart';

/// アプリの配色。ライト・ダークそれぞれの値を持ち、端末の外観設定に合わせて切り替わる。
///
/// 画面からは `context.colors.accent` のように取り出す。
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brightness,
    required this.background,
    required this.card,
    required this.cardPressed,
    required this.separator,
    required this.bar,
    required this.accent,
    required this.accentLight,
    required this.onAccent,
    required this.destructive,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.fill,
    required this.segmentThumb,
    required this.toastBackground,
    required this.toastBorder,
    required this.shadow,
    required this.glassTint,
    required this.glassGlow,
    required this.tabInactive,
    required this.tabIndicator,
    required this.tabIndicatorActive,
    required this.ticketBase,
    required this.ticketText,
    required this.ticketDivider,
  });

  final Brightness brightness;

  /// 画面の地の色（iOS のグループ化リストの背景に相当）。
  final Color background;

  /// 角丸カード・グループ化リストの面。
  final Color card;
  final Color cardPressed;
  final Color separator;

  /// ナビゲーションバーのすりガラス。背後を透かすため半透明にする。
  final Color bar;

  /// シャンパンゴールドのアクセント。ライトでは白地で読めるよう濃くしている。
  final Color accent;
  final Color accentLight;

  /// [accent] を塗った上に載せる文字・アイコンの色。
  final Color onAccent;
  final Color destructive;

  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;

  /// 検索欄・セグメントコントロール・未選択チップの塗り。
  final Color fill;
  final Color segmentThumb;

  final Color toastBackground;
  final Color toastBorder;
  final Color shadow;

  // リキッドグラスのタブバー
  final Color glassTint;
  final Color glassGlow;
  final Color tabInactive;
  final Color tabIndicator;
  final Color tabIndicatorActive;

  // チケットの券面
  final Color ticketBase;
  final Color ticketText;
  final Color ticketDivider;

  bool get isDark => brightness == Brightness.dark;

  static const dark = AppPalette(
    brightness: Brightness.dark,
    background: Color(0xFF0B0A09),
    card: Color(0xFF1D1B18),
    cardPressed: Color(0xFF2B2824),
    separator: Color(0x99545458),
    // 画面の地と同じ不透明な色。半透明だと、その下の色と混ざって地より暗く見える（スクロールで縮んだ見出しの背景）
    bar: Color(0xFF0B0A09),
    accent: Color(0xFFE6C88F),
    accentLight: Color(0xFFF5E2BC),
    onAccent: Color(0xFF1A1409),
    destructive: Color(0xFFFF453A),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0x99EBEBF5),
    textDisabled: Color(0x4DEBEBF5),
    fill: Color(0x3D767680),
    segmentThumb: Color(0xFF636366),
    toastBackground: Color(0xD92C2A27),
    toastBorder: Color(0x14FFFFFF),
    shadow: Color(0x80000000),
    glassTint: Color(0x33303036),
    glassGlow: Color(0x33FFFFFF),
    tabInactive: Color(0xFFD1D1D6),
    tabIndicator: Color(0x24FFFFFF),
    tabIndicatorActive: Color(0x3DFFFFFF),
    ticketBase: Color(0xFF141210),
    ticketText: Color(0xFFFFFFFF),
    ticketDivider: Color(0x4DFFFFFF),
  );

  static const light = AppPalette(
    brightness: Brightness.light,
    background: Color(0xFFF4F2EE),
    card: Color(0xFFFFFFFF),
    cardPressed: Color(0xFFE9E6E0),
    separator: Color(0x4A3C3C43),
    // 画面の地と同じ不透明な色。半透明だと、その下の色と混ざって地より暗く見える（スクロールで縮んだ見出しの背景）
    bar: Color(0xFFF4F2EE),
    accent: Color(0xFF9A7433),
    accentLight: Color(0xFFC9A86A),
    onAccent: Color(0xFFFFFFFF),
    destructive: Color(0xFFFF3B30),
    textPrimary: Color(0xFF000000),
    textSecondary: Color(0x993C3C43),
    textDisabled: Color(0x4D3C3C43),
    fill: Color(0x1F767680),
    segmentThumb: Color(0xFFFFFFFF),
    toastBackground: Color(0xE6FFFFFF),
    toastBorder: Color(0x14000000),
    shadow: Color(0x24000000),
    glassTint: Color(0x99FFFFFF),
    glassGlow: Color(0x40FFFFFF),
    tabInactive: Color(0xFF3C3C43),
    tabIndicator: Color(0x12000000),
    tabIndicatorActive: Color(0x1F000000),
    ticketBase: Color(0xFFFFFFFF),
    ticketText: Color(0xFF1C1C1E),
    ticketDivider: Color(0x33000000),
  );

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: c(background, other.background),
      card: c(card, other.card),
      cardPressed: c(cardPressed, other.cardPressed),
      separator: c(separator, other.separator),
      bar: c(bar, other.bar),
      accent: c(accent, other.accent),
      accentLight: c(accentLight, other.accentLight),
      onAccent: c(onAccent, other.onAccent),
      destructive: c(destructive, other.destructive),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textDisabled: c(textDisabled, other.textDisabled),
      fill: c(fill, other.fill),
      segmentThumb: c(segmentThumb, other.segmentThumb),
      toastBackground: c(toastBackground, other.toastBackground),
      toastBorder: c(toastBorder, other.toastBorder),
      shadow: c(shadow, other.shadow),
      glassTint: c(glassTint, other.glassTint),
      glassGlow: c(glassGlow, other.glassGlow),
      tabInactive: c(tabInactive, other.tabInactive),
      tabIndicator: c(tabIndicator, other.tabIndicator),
      tabIndicatorActive: c(tabIndicatorActive, other.tabIndicatorActive),
      ticketBase: c(ticketBase, other.ticketBase),
      ticketText: c(ticketText, other.ticketText),
      ticketDivider: c(ticketDivider, other.ticketDivider),
    );
  }
}

extension AppPaletteContext on BuildContext {
  /// 現在の外観（ライト・ダーク）に合ったアプリの配色。
  AppPalette get colors =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;
}
