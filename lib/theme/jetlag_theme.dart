import 'package:flutter/material.dart';

import '../models/guide_event.dart';

/// Dark surface for the guide. Kept apart from the roster light theme so the
/// fullscreen module reads as its own app.
class JetlagTheme {
  const JetlagTheme._();

  static const bg = Color(0xFF121316);
  static const card = Color(0xFF1C1E24);
  static const elevated = Color(0xFF262933);
  static const border = Color(0xFF2C303B);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9AA0A6);
  static const textTertiary = Color(0xFF5F6368);
  static const duty = Color(0xFF4A90E2);
  static const sleep = Color(0xFF8A7CFF);
  /// Softer than [sleep] so inflight rest does not read as a planned sleep.
  static const inflight = Color(0xFF5C5478);
  static const loggedSleep = Color(0xFF2EC4B6);
  static const caffeine = Color(0xFFF5A623);
  static const meal = Color(0xFF50E3C2);
  static const light = Color(0xFFFFD043);
  static const now = Color(0xFFFF5A7A);
  static const debt = Color(0xFFFF5C5C);
  static const surplus = Color(0xFF3DDC97);

  static const pastOpacity = 0.4;
  static const pagePadding = 16.0;

  static const tabular = [FontFeature.tabularFigures()];

  static const title = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    height: 1.25,
  );
  static const clock = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    fontFeatures: tabular,
    height: 1.15,
  );
  static const localClock = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w800,
    color: textPrimary,
    fontFeatures: tabular,
    height: 1.15,
  );
  static const body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: textPrimary,
    fontFeatures: tabular,
    height: 1.3,
  );
  static const caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: textSecondary,
    fontFeatures: tabular,
    height: 1.3,
  );
  static const micro = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: textTertiary,
    height: 1.4,
  );

  static const disclaimer =
      '본 가이드는 일반적인 생체주기 모델을 기반으로 한 생활 가이드이며 의학적 조언이 아닙니다. 당일 컨디션에 맞춰 조절해 주세요.';

  static final ThemeData material = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    canvasColor: bg,
    dividerColor: border,
    splashColor: duty.withValues(alpha: 0.16),
    highlightColor: duty.withValues(alpha: 0.08),
    colorScheme: ColorScheme.fromSeed(
      seedColor: duty,
      brightness: Brightness.dark,
      primary: duty,
      onPrimary: bg,
      secondary: sleep,
      onSecondary: textPrimary,
      tertiary: meal,
      error: now,
      surface: card,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      outline: border,
      outlineVariant: border,
      surfaceContainerLowest: bg,
      surfaceContainerLow: bg,
      surfaceContainer: card,
      surfaceContainerHigh: elevated,
      surfaceContainerHighest: elevated,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: bg,
      foregroundColor: textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: title,
    ),
    cardTheme: const CardThemeData(
      color: card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: border),
      ),
    ),
    dividerTheme: const DividerThemeData(color: border, thickness: 1),
    iconTheme: const IconThemeData(color: textSecondary),
    textTheme: const TextTheme(
      titleLarge: title,
      titleMedium: title,
      bodyLarge: body,
      bodyMedium: body,
      bodySmall: caption,
      labelLarge: body,
      labelMedium: caption,
      labelSmall: micro,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: elevated,
      contentTextStyle: body,
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: title,
      contentTextStyle: body,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: card,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: textSecondary,
      textColor: textPrimary,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: duty),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: duty,
      selectionColor: duty.withValues(alpha: 0.35),
      selectionHandleColor: duty,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return duty;
        return textSecondary;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return duty.withValues(alpha: 0.45);
        }
        return border;
      }),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return bg;
          return textPrimary;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return duty;
          return card;
        }),
        side: const WidgetStatePropertyAll(BorderSide(color: border)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: duty,
        side: const BorderSide(color: border),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: card,
      selectedItemColor: duty,
      unselectedItemColor: textSecondary,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      selectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      unselectedLabelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  static Color accentFor(GuideEventKind kind) {
    switch (kind) {
      case GuideEventKind.meal:
        return meal;
      case GuideEventKind.caffeine:
        return caffeine;
      case GuideEventKind.sleep:
        return sleep;
      case GuideEventKind.loggedSleep:
        return loggedSleep;
      case GuideEventKind.light:
        return light;
      case GuideEventKind.arrival:
      case GuideEventKind.pickup:
      case GuideEventKind.showup:
      case GuideEventKind.departure:
        return duty;
      case GuideEventKind.inflight:
        return inflight;
    }
  }

  static IconData iconFor(GuideEventKind kind) {
    switch (kind) {
      case GuideEventKind.meal:
        return Icons.restaurant;
      case GuideEventKind.caffeine:
        return Icons.local_cafe;
      case GuideEventKind.sleep:
        return Icons.bed;
      case GuideEventKind.loggedSleep:
        return Icons.nights_stay;
      case GuideEventKind.light:
        return Icons.wb_sunny_outlined;
      case GuideEventKind.arrival:
        return Icons.flight_land;
      case GuideEventKind.pickup:
        return Icons.local_taxi;
      case GuideEventKind.showup:
        return Icons.badge_outlined;
      case GuideEventKind.departure:
        return Icons.flight_takeoff;
      case GuideEventKind.inflight:
        return Icons.airline_seat_flat;
    }
  }
}
