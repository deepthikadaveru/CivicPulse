import 'package:flutter/material.dart';

class AppConstants {
  // ── Change this to your machine's local IP when testing on a real device ──
  // For emulator use: http://10.0.2.2:8000
  // For real device use: http://YOUR_PC_IP:8000 (e.g. http://192.168.1.5:8000)
  static const String baseUrl = 'http://192.168.0.109:8000/api/v1';
  //static const String baseUrl = 'http://127.0.0.1:8000/api/v1';
  static const String appName = 'CivicPulse';
  static const String tokenKey = 'access_token';
  static const String userKey = 'user_data';
  static const String cityKey = 'city_id';
}

class AppColors {
  // Severity colors
  static const Color critical = Color(0xFFE24B4A);
  static const Color high = Color(0xFFD85A30);
  static const Color moderate = Color(0xFFEF9F27);
  static const Color low = Color(0xFF639922);
  static const Color resolved = Color(0xFF1D9E75);

  // Brand
  static const Color primary = Color(0xFF185FA5);
  static const Color primaryLight = Color(0xFFE6F1FB);
  static const Color background = Color(0xFFF5F5F5);
  static const Color surface = Colors.white;
  static const Color textPrimary = Color(0xFF2C2C2A);
  static const Color textSecondary = Color(0xFF5F5E5A);
  static const Color border = Color(0xFFD3D1C7);

  static Color severityColor(String severity) {
    switch (severity) {
      case 'critical':
        return critical;
      case 'high':
        return high;
      case 'moderate':
        return moderate;
      case 'low':
        return low;
      default:
        return low;
    }
  }

  static Color statusColor(String status) {
    switch (status) {
      case 'resolved':
        return resolved;
      case 'in_progress':
        return primary;
      case 'assigned':
        return moderate;
      case 'rejected':
        return critical;
      default:
        return textSecondary;
    }
  }
}

class AppTheme {
  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          background: AppColors.background,
        ),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.border, width: 0.5),
          ),
        ),
      );
}
