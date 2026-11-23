import 'package:flutter/material.dart';
import 'util.dart';

ThemeData buildTheme() {
  final border = OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border));
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.brand),
    scaffoldBackgroundColor: AppColors.bg,
    fontFamily: 'Segoe UI',
    fontFamilyFallback: const ['Tahoma', 'Arial', 'Noto Sans Arabic'],
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.brand, width: 1.6)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.danger)),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 18), shape: shape)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 16), shape: shape, side: const BorderSide(color: AppColors.border))),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: shape)),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: const BorderSide(color: AppColors.border),
      labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF1F2D3D)),
      secondaryLabelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF0F3D44)),
      backgroundColor: Colors.white,
      selectedColor: const Color(0xFFCFE6EA),
      checkmarkColor: const Color(0xFF0F3D44),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    dataTableTheme: const DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(Color(0xFFF1F4F8)),
      headingTextStyle: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF263445)),
      dataRowMinHeight: 44,
      dataRowMaxHeight: 52,
      dividerThickness: 0.6,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1, thickness: 1),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: shape),
  );
}
