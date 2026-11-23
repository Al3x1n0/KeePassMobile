import 'package:material_ui/material_ui.dart';

/// Spaziature dell'app: unica fonte per padding e distanze nei widget.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 16;
  static const double l = 24;
}

/// Lunghezze massime dei campi di testo libero.
abstract final class AppLimits {
  static const int masterPassword = 1024;
  static const int fieldName = 256;
  static const int fieldValue = 8192;
  static const int notes = 65536;
  static const int searchQuery = 256;

  /// Indirizzo e nome utente di un server remoto.
  static const int remoteAddress = 2048;
  static const int remoteUserName = 256;
  static const int sshPrivateKey = 65536;

  /// Generatore: caratteri casuali, parole e separatore della passphrase.
  static const int generatedLength = 512;
  static const int generatedWords = 64;
  static const int wordSeparator = 8;

  /// Dimensione massima di un allegato (decisione D12): il
  /// database si copia in memoria a ogni salvataggio.
  static const int attachmentBytes = 10 * 1024 * 1024;
}

/// Larghezza massima dei form, per i tablet.
const double appFormMaxWidth = 480;

// Colori principali condivisi dai temi chiaro e scuro.
abstract final class AppColors {
  static const blue = Color(0xFF0066FF);
  static const white = Color(0xFFFFFFFF);
  static const ink = Color(0xFF161622);
}

ThemeData _buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.blue,
        brightness: brightness,
      ).copyWith(
        primary: AppColors.blue,
        onPrimary: AppColors.white,
        primaryContainer: AppColors.blue,
        onPrimaryContainer: AppColors.white,
        secondary: AppColors.blue,
        onSecondary: AppColors.white,
        secondaryContainer: AppColors.blue,
        onSecondaryContainer: AppColors.white,
        tertiaryContainer: AppColors.blue,
        onTertiaryContainer: AppColors.white,
        inversePrimary: AppColors.blue,
        surfaceTint: AppColors.blue,
        surface: dark ? AppColors.ink : AppColors.white,
        onSurface: dark ? AppColors.white : AppColors.ink,
      );
  final barColor = dark ? const Color(0xFF20202E) : const Color(0xFFF5F5F7);
  final navigationLabel = Typography.material2021().englishLike.labelMedium;
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  );
  const buttonMinimumSize = Size(0, 56);
  const buttonPadding = EdgeInsets.symmetric(horizontal: AppSpacing.l);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: barColor,
      foregroundColor: scheme.onSurface,
      centerTitle: true,
      scrolledUnderElevation: 0,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainer,
      elevation: 3,
      shape: buttonShape,
      menuPadding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: barColor,
      elevation: 0,
      indicatorColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? IconThemeData(color: scheme.primary)
            : null,
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => navigationLabel?.copyWith(
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: buttonMinimumSize,
        padding: buttonPadding,
        shape: buttonShape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: buttonMinimumSize,
        padding: buttonPadding,
        shape: buttonShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: buttonMinimumSize,
        padding: buttonPadding,
        shape: buttonShape,
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.blue,
      foregroundColor: AppColors.white,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      linearTrackColor: scheme.surfaceContainerHighest,
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled) ||
            states.contains(WidgetState.selected)) {
          return null;
        }
        return dark ? const Color(0xFF464655) : const Color(0xFFDBDDE4);
      }),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.disabled) ? null : AppColors.white,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled) ||
            states.contains(WidgetState.selected)) {
          return null;
        }
        return Colors.transparent;
      }),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: UnderlineInputBorder(
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
  );
}

ThemeData buildLightTheme() => _buildTheme(Brightness.light);

ThemeData buildDarkTheme() => _buildTheme(Brightness.dark);
