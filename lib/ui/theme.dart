import 'package:flutter/material.dart';

/// Cores semânticas adicionais (receita, despesa, superfícies de tabela).
@immutable
class FinColors extends ThemeExtension<FinColors> {
  final Color income;
  final Color expense;
  final Color positive;
  final Color negative;
  final Color warning;
  final Color subtle;
  final Color gridLine;
  final Color stickyColumn;

  const FinColors({
    required this.income,
    required this.expense,
    required this.positive,
    required this.negative,
    required this.warning,
    required this.subtle,
    required this.gridLine,
    required this.stickyColumn,
  });

  // Paleta das séries validada para daltonismo (ΔE ≥ 28) e contraste.
  static const light = FinColors(
    income: Color(0xFF2457D6),
    expense: Color(0xFFE8710A),
    positive: Color(0xFF15803D),
    negative: Color(0xFFC62828),
    warning: Color(0xFFB45309),
    subtle: Color(0xFF6B7280),
    gridLine: Color(0xFFE5E7EB),
    stickyColumn: Color(0xFFFFFFFF),
  );

  static const dark = FinColors(
    income: Color(0xFF5B85F0),
    expense: Color(0xFFD9771F),
    positive: Color(0xFF4ADE80),
    negative: Color(0xFFF87171),
    warning: Color(0xFFFBBF24),
    subtle: Color(0xFF9CA3AF),
    gridLine: Color(0xFF2A2F3A),
    stickyColumn: Color(0xFF171A21),
  );

  @override
  FinColors copyWith() => this;

  @override
  FinColors lerp(ThemeExtension<FinColors>? other, double t) =>
      t < 0.5 ? this : (other as FinColors? ?? this);
}

extension FinThemeX on BuildContext {
  FinColors get fin => Theme.of(this).extension<FinColors>()!;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}

class AppTheme {
  static const accent = Color(0xFF2457D6);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final isDark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: b,
      primary: isDark ? const Color(0xFF7DA2FF) : accent,
      surface: isDark ? const Color(0xFF111318) : const Color(0xFFF6F7F9),
      onSurface: isDark ? const Color(0xFFE7E9EE) : const Color(0xFF111827),
      surfaceContainerLowest: isDark
          ? const Color(0xFF171A21)
          : const Color(0xFFFFFFFF),
      surfaceContainerLow: isDark
          ? const Color(0xFF1B1F27)
          : const Color(0xFFFFFFFF),
      surfaceContainer: isDark
          ? const Color(0xFF1F232C)
          : const Color(0xFFF0F2F5),
      outlineVariant: isDark
          ? const Color(0xFF2A2F3A)
          : const Color(0xFFE5E7EB),
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: b,
      scaffoldBackgroundColor: scheme.surface,
      extensions: [isDark ? FinColors.dark : FinColors.light],
    );
    const tabular = [FontFeature.tabularFigures()];
    final text = base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        fontFeatures: tabular,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(fontFeatures: tabular),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(fontFeatures: tabular),
    );
    return base.copyWith(
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.primary.withValues(alpha: 0.12),
        surfaceTintColor: Colors.transparent,
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(
          text.labelSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
