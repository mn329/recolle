import 'package:flutter/material.dart';

class AppColors {
  // Private constructor to prevent instantiation
  const AppColors._();

  // Base Colors
  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF101010);
  static const Color surfaceLight = Color(0xFF1C1C1E);

  // iOS のダークモードのグループ化リストに合わせた面・区切り線
  static const Color card = Color(0xFF1C1C1E);
  static const Color cardPressed = Color(0xFF2C2C2E);
  static const Color separator = Color(0x99545458);

  /// ナビゲーションバー・タブバーのすりガラス。背後を透かすため半透明にする。
  static const Color bar = Color(0xCC0A0A0A);

  // Accent Colors
  static const Color gold = Color(0xFFD4AF37);
  static const Color goldLight = Color(0xFFFFD700);
  static const Color destructive = Color(0xFFFF453A);

  // Text Colors
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0x99EBEBF5);
  static const Color textDisabled = Color(0x4DEBEBF5);

  // Ticket Colors
  static const Color ticketRed = Color(0xFF8B0000);
  static const Color ticketBlue = Color(0xFF00008B);
  static const Color ticketWhite = Color(0xFFF5F5F5);
}
