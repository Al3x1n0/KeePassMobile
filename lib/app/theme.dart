import 'package:material_ui/material_ui.dart';

/// Spaziature dell'app: unica fonte per padding e distanze nei widget.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 16;
  static const double l = 24;
}

/// Dimensioni degli indicatori cromatici delle voci.
abstract final class AppEntryColorLayout {
  static const double stripeWidth = 4;
}

/// Dimensioni della pila di azioni per l'apertura dei database.
abstract final class AppFileSelectLayout {
  static const double fabMinHeight = 56;
  static const double fabIconSize = 24;
  static const double contentMinHeight = 96;
  static const fabPadding = EdgeInsetsDirectional.only(
    start: AppSpacing.m,
    end: AppSpacing.m + AppSpacing.xs,
  );
}

/// Aspetto e transizioni dei riquadri espandibili condivisi.
abstract final class AppSectionLayout {
  static const double backgroundOpacity = 0.16;
  static const double headerMinHeight = 48;
  static const transitionDuration = Duration(milliseconds: 200);
  static const transitionCurve = Curves.easeInOutCubic;
  static const margin = EdgeInsets.symmetric(
    horizontal: AppSpacing.m,
    vertical: AppSpacing.s,
  );
  static const headerPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.m,
    vertical: AppSpacing.s,
  );
  static const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(16)),
  );
}

/// Dimensioni della navigazione flottante e dello spazio per il pulsante aggiungi.
abstract final class AppNavigationLayout {
  static const double destinationMinHeight = 48;
  static const double enabledMinWidth = 64;
  static const double labelSidePadding = AppSpacing.s + AppSpacing.xs;
  static const double iconSize = 22;
  static const double iconLabelGap = 2;
  static const double blurSigma = 12;
  static const double borderOpacity = 0.22;
  static const double shadowBlurRadius = 16;
  static const double fabClearance = 56 + AppSpacing.m * 2;
  static const transitionDuration = Duration(milliseconds: 240);
  static const selectionCurve = Curves.easeOutCubic;

  static const margin = EdgeInsets.fromLTRB(
    AppSpacing.m,
    0,
    AppSpacing.m,
    AppSpacing.s + AppSpacing.xs,
  );
  static const surfacePadding = EdgeInsets.all(AppSpacing.xs);
  static const destinationPadding = EdgeInsets.symmetric(
    horizontal: labelSidePadding,
    vertical: AppSpacing.xs,
  );
  static const disabledDestinationPadding = EdgeInsets.symmetric(
    vertical: AppSpacing.xs,
  );
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
      centerTitle: false,
      scrolledUnderElevation: 0,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainer,
      elevation: 3,
      shape: buttonShape,
      menuPadding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: barColor.withValues(alpha: dark ? 0.32 : 0.28),
      elevation: 0,
      shadowColor: scheme.shadow.withValues(alpha: dark ? 0.16 : 0.06),
      indicatorColor: AppColors.blue.withValues(alpha: dark ? 0.18 : 0.10),
      indicatorShape: const StadiumBorder(),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.disabled)
              ? scheme.onSurface.withValues(alpha: 0.38)
              : states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => navigationLabel?.copyWith(
          letterSpacing: 0,
          height: 1.2,
          color: states.contains(WidgetState.disabled)
              ? scheme.onSurface.withValues(alpha: 0.38)
              : states.contains(WidgetState.selected)
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
