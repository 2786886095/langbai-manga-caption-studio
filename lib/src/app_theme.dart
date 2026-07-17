import 'package:flutter/material.dart';

abstract final class AppColors {
  static const ink = Color(0xff1d1b1c);
  static const pink = Color(0xffe94d72);
  static const pinkPressed = Color(0xffca385c);
  static const blush = Color(0xfffff0f3);
  static const paper = Color(0xfffbf8f6);
  static const panel = Color(0xfffffdfc);
  static const canvas = Color(0xffeee9e6);
  static const line = Color(0xffd8d0cd);
  static const muted = Color(0xff776f6d);
  static const success = Color(0xff2f9d68);
  static const warning = Color(0xffd24868);
}

class _InstantPageTransitionsBuilder extends PageTransitionsBuilder {
  const _InstantPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.pink,
    brightness: Brightness.light,
    surface: AppColors.panel,
  ).copyWith(
    primary: AppColors.pink,
    onPrimary: Colors.white,
    secondary: AppColors.ink,
    outline: AppColors.line,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.paper,
    fontFamily: 'Noto Sans SC',
    fontFamilyFallback: const [
      'PingFang SC',
      'sans-serif',
    ],
    dividerColor: AppColors.line,
    splashFactory: InkRipple.splashFactory,
    splashColor: AppColors.pink.withOpacity(.12),
    highlightColor: AppColors.pink.withOpacity(.07),
    hoverColor: AppColors.pink.withOpacity(.05),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _InstantPageTransitionsBuilder(),
        TargetPlatform.iOS: _InstantPageTransitionsBuilder(),
        TargetPlatform.macOS: _InstantPageTransitionsBuilder(),
        TargetPlatform.windows: _InstantPageTransitionsBuilder(),
        TargetPlatform.linux: _InstantPageTransitionsBuilder(),
      },
    ),
    textTheme: const TextTheme(
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
      bodyMedium: TextStyle(fontSize: 14, height: 1.4, color: AppColors.ink),
      bodySmall: TextStyle(fontSize: 12, height: 1.35, color: AppColors.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? AppColors.line
              : states.contains(WidgetState.pressed)
                  ? AppColors.pinkPressed
                  : AppColors.pink,
        ),
        foregroundColor: const WidgetStatePropertyAll(Colors.white),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: const WidgetStatePropertyAll(AppColors.ink),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.line)),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.pink, width: 1.5),
      ),
    ),
  );
}
