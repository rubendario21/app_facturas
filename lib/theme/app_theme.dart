import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Colores con significado contable (iguales en la app, el portal y el PDF).
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.paid,
    required this.pending,
    required this.overdue,
    required this.partial,
    required this.muted,
    required this.line,
  });

  /// Cobrado / pagada.
  final Color paid;

  /// Saldo pendiente.
  final Color pending;

  /// Vencida.
  final Color overdue;

  /// Con abonos.
  final Color partial;

  /// Texto secundario.
  final Color muted;

  /// Separadores finos.
  final Color line;

  static const light = AppColors(
    paid: Color(0xFF1E8E5A),
    pending: Color(0xFFB7791F),
    overdue: Color(0xFFC2412D),
    partial: Color(0xFF2E3A8C),
    muted: Color(0xFF5E6478),
    line: Color(0xFFE2E4EC),
  );

  static const dark = AppColors(
    paid: Color(0xFF4CC38A),
    pending: Color(0xFFE0A84A),
    overdue: Color(0xFFF07A64),
    partial: Color(0xFF9AA6F2),
    muted: Color(0xFF9A9FB3),
    line: Color(0xFF2A2E3B),
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>()!;

  @override
  AppColors copyWith(
          {Color? paid,
          Color? pending,
          Color? overdue,
          Color? partial,
          Color? muted,
          Color? line}) =>
      AppColors(
        paid: paid ?? this.paid,
        pending: pending ?? this.pending,
        overdue: overdue ?? this.overdue,
        partial: partial ?? this.partial,
        muted: muted ?? this.muted,
        line: line ?? this.line,
      );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      paid: Color.lerp(paid, other.paid, t)!,
      pending: Color.lerp(pending, other.pending, t)!,
      overdue: Color.lerp(overdue, other.overdue, t)!,
      partial: Color.lerp(partial, other.partial, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      line: Color.lerp(line, other.line, t)!,
    );
  }
}

class AppTheme {
  static const ink = Color(0xFF2E3A8C);
  static const font = 'IBMPlexSans';

  /// Cifras con ancho fijo para que los importes queden alineados.
  static const tabular = [FontFeature.tabularFigures()];

  static ThemeData light() => _build(
        ColorScheme.fromSeed(seedColor: ink, brightness: Brightness.light)
            .copyWith(
          primary: ink,
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFFE3E6F8),
          onPrimaryContainer: const Color(0xFF1B2366),
          surface: const Color(0xFFFFFFFF),
          onSurface: const Color(0xFF1A1D29),
          surfaceContainerLowest: const Color(0xFFF5F6FA),
          surfaceContainerLow: const Color(0xFFF5F6FA),
          surfaceContainer: const Color(0xFFEEF0F6),
          surfaceContainerHighest: const Color(0xFFE6E8F0),
          outline: const Color(0xFFC9CCD8),
          outlineVariant: const Color(0xFFE2E4EC),
          error: const Color(0xFFC2412D),
        ),
        AppColors.light,
        background: const Color(0xFFF5F6FA),
      );

  static ThemeData dark() => _build(
        ColorScheme.fromSeed(seedColor: ink, brightness: Brightness.dark)
            .copyWith(
          primary: const Color(0xFFAEB8F5),
          onPrimary: const Color(0xFF151C55),
          primaryContainer: const Color(0xFF2B3474),
          onPrimaryContainer: const Color(0xFFE0E4FF),
          surface: const Color(0xFF1B1E29),
          onSurface: const Color(0xFFE6E8F0),
          surfaceContainerLowest: const Color(0xFF13151D),
          surfaceContainerLow: const Color(0xFF181B25),
          surfaceContainer: const Color(0xFF20232F),
          surfaceContainerHighest: const Color(0xFF2A2E3B),
          outline: const Color(0xFF454A5C),
          outlineVariant: const Color(0xFF2A2E3B),
          error: const Color(0xFFF07A64),
        ),
        AppColors.dark,
        background: const Color(0xFF13151D),
      );

  static ThemeData _build(ColorScheme scheme, AppColors colors,
      {required Color background}) {
    final base =
        ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: font);
    final text = base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.5),
      headlineSmall: base.textTheme.headlineSmall
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.3),
      titleLarge:
          base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      titleMedium:
          base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      labelLarge:
          base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );
    final radius = BorderRadius.circular(10);
    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: text,
      extensions: [colors],
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      // Superficies planas con borde fino: sin sombras repetidas.
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
            borderRadius: radius, side: BorderSide(color: colors.line)),
      ),
      dividerTheme:
          DividerThemeData(color: colors.line, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        border: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(color: scheme.outline)),
        enabledBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(color: scheme.outline)),
        focusedBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(color: scheme.primary, width: 2)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: radius),
          side: BorderSide(color: scheme.outline),
          textStyle: text.labelLarge,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          side: BorderSide(color: scheme.outline),
          selectedBackgroundColor: scheme.primaryContainer,
          selectedForegroundColor: scheme.onPrimaryContainer,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 16)),
    );
  }
}

/// Preferencia de tema (Sistema / Claro / Oscuro), guardada en el dispositivo.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController() : super(ThemeMode.system);

  static final instance = ThemeController();
  static const _key = 'theme_mode';

  Future<void> load() async {
    try {
      final name = (await SharedPreferences.getInstance()).getString(_key);
      value = ThemeMode.values
          .firstWhere((m) => m.name == name, orElse: () => ThemeMode.system);
    } catch (_) {
      value = ThemeMode.system;
    }
  }

  Future<void> set(ThemeMode mode) async {
    value = mode;
    try {
      await (await SharedPreferences.getInstance()).setString(_key, mode.name);
    } catch (_) {}
  }
}
