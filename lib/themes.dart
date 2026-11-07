import 'package:flutter/material.dart';

class TradeStyle {
  final String id, name;
  final Color primary, background, paper, ink, muted, border, soft;
  final double radius;
  final String? font;
  const TradeStyle(
    this.id,
    this.name,
    this.primary,
    this.background,
    this.paper,
    this.ink,
    this.muted,
    this.border,
    this.soft,
    this.radius, [
    this.font,
  ]);
  bool get dark => id == 'midnight';
  Color get good => dark ? const Color(0xff6bc5ab) : const Color(0xff008569);
  Color get bad => dark ? const Color(0xffed8ca1) : const Color(0xffcd4b64);
  ThemeData theme() {
    final cs = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: dark ? Brightness.dark : Brightness.light,
    ).copyWith(primary: primary, surface: paper, onSurface: ink, error: bad);
    return ThemeData(
      useMaterial3: true,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: paper,
        modalBackgroundColor: paper,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      colorScheme: cs,
      scaffoldBackgroundColor: background,
      fontFamily: font ?? 'Figtree',
      textTheme:
          ThemeData(brightness: dark ? Brightness.dark : Brightness.light)
              .textTheme
              .apply(
                bodyColor: ink,
                displayColor: ink,
                fontFamily: font ?? 'Figtree',
              ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: ink,
          letterSpacing: -.5,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: paper,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        labelStyle: TextStyle(fontSize: 12, color: muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius.clamp(3, 12)),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius.clamp(3, 12)),
          borderSide: BorderSide(color: border),
        ),
      ),
      cardTheme: CardThemeData(
        color: paper,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: border),
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: dark ? background : Colors.white,
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius.clamp(4, 22)),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(0, 42),
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius.clamp(4, 22)),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: paper,
        indicatorColor: soft,
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: ink),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1),
    );
  }
}

const styles = [
  TradeStyle(
    'blue',
    'Market Blue',
    Color(0xff365bd4),
    Color(0xfff7f8fb),
    Colors.white,
    Color(0xff17253c),
    Color(0xff7e8ba0),
    Color(0xffe5eaf2),
    Color(0xffedf1fc),
    12,
  ),
  TradeStyle(
    'forest',
    'Forest Executive',
    Color(0xff285840),
    Color(0xfff5f4ef),
    Color(0xfffffefa),
    Color(0xff263f32),
    Color(0xff728273),
    Color(0xffdce4d7),
    Color(0xffe8efe4),
    16,
    'serif',
  ),
  TradeStyle(
    'navy',
    'Navy Reserve',
    Color(0xff31547a),
    Color(0xfff3f5f8),
    Colors.white,
    Color(0xff24364b),
    Color(0xff788698),
    Color(0xffdce3ec),
    Color(0xffe8eef5),
    6,
  ),
  TradeStyle(
    'teal',
    'Teal Studio',
    Color(0xff22736e),
    Color(0xfff2f7f6),
    Colors.white,
    Color(0xff23423f),
    Color(0xff718984),
    Color(0xffd9e7e3),
    Color(0xffe3f0eb),
    22,
  ),
  TradeStyle(
    'wine',
    'Burgundy Select',
    Color(0xff884459),
    Color(0xfffaf5f6),
    Colors.white,
    Color(0xff432832),
    Color(0xff967a85),
    Color(0xffeadde2),
    Color(0xfff3e6eb),
    7,
    'serif',
  ),
  TradeStyle(
    'graphite',
    'Graphite Pro',
    Color(0xff4e5968),
    Color(0xfff4f5f6),
    Colors.white,
    Color(0xff2b3441),
    Color(0xff818993),
    Color(0xffdee2e7),
    Color(0xffe9ecf0),
    2,
  ),
  TradeStyle(
    'sapphire',
    'Sapphire Precision',
    Color(0xff385bb0),
    Color(0xfff4f6fc),
    Colors.white,
    Color(0xff25365c),
    Color(0xff7986a2),
    Color(0xffdfe5f3),
    Color(0xffe8edfa),
    5,
  ),
  TradeStyle(
    'copper',
    'Copper Atelier',
    Color(0xff95613f),
    Color(0xfffaf7f3),
    Colors.white,
    Color(0xff443429),
    Color(0xff958474),
    Color(0xffeaddd1),
    Color(0xfff2e9de),
    11,
    'serif',
  ),
  TradeStyle(
    'midnight',
    'Midnight Terminal',
    Color(0xffad91e6),
    Color(0xff171820),
    Color(0xff20222d),
    Color(0xffeeedf4),
    Color(0xffaca6bd),
    Color(0xff353744),
    Color(0xff302a40),
    5,
    'monospace',
  ),
  TradeStyle(
    'gold',
    'Ivory & Gold',
    Color(0xff8a713b),
    Color(0xfff8f6ef),
    Color(0xfffffefa),
    Color(0xff423b2c),
    Color(0xff928772),
    Color(0xffe7e1d2),
    Color(0xfff0ebdd),
    9,
    'serif',
  ),
];
