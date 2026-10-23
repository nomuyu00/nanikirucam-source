import 'package:flutter/material.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';

/// アプリのテーマ（ライト固定）。`app.dart` の MaterialApp に渡す。
///
/// ColorScheme は fromSeed の自動生成に任せず、ブランド色（[AppColors]）から
/// primary（ジェイド）・secondary（落ち着いた緑灰）・tertiary（朱）・surface（アイボリー）・
/// error を指定する。文字はフォントを同梱せずシステムフォントで、字重・行間・大きさの
/// 階層だけを決める。
abstract final class AppTheme {
  static const ColorScheme colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.jade,
    onPrimary: Colors.white,
    primaryContainer: AppColors.jadeTint,
    onPrimaryContainer: Color(0xFF00281B),
    primaryFixed: AppColors.jadeTint,
    primaryFixedDim: Color(0xFFA9D6C1),
    onPrimaryFixed: Color(0xFF00281B),
    onPrimaryFixedVariant: AppColors.jadeDeep,
    secondary: Color(0xFF4D6359),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFDDE9E1),
    onSecondaryContainer: Color(0xFF0A1F16),
    tertiary: AppColors.vermilion,
    onTertiary: Colors.white,
    tertiaryContainer: AppColors.vermilionTint,
    onTertiaryContainer: Color(0xFF3D0700),
    error: AppColors.danger,
    onError: Colors.white,
    errorContainer: Color(0xFFF9DEDC),
    onErrorContainer: Color(0xFF410E0B),
    surface: AppColors.ivory,
    onSurface: AppColors.ink,
    surfaceDim: Color(0xFFE6E0D2),
    surfaceBright: AppColors.tileFace,
    surfaceContainerLowest: AppColors.tileFace,
    surfaceContainerLow: Color(0xFFF5F1E7),
    surfaceContainer: Color(0xFFF0EBDF),
    surfaceContainerHigh: Color(0xFFEBE5D7),
    surfaceContainerHighest: Color(0xFFE5DECF),
    onSurfaceVariant: AppColors.inkMuted,
    outline: AppColors.outline,
    outlineVariant: AppColors.outlineSoft,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: Color(0xFF26302B),
    onInverseSurface: Color(0xFFF1EFE8),
    inversePrimary: Color(0xFF8FD5B5),
    surfaceTint: Colors.transparent,
  );

  /// 文字の階層（システムフォント。日本語が詰まって見えないよう行間を広めにとる）。
  static TextTheme textTheme(String? fontFamily) {
    TextStyle s(
      double size,
      FontWeight weight,
      double height, {
      double ls = 0,
    }) => TextStyle(
      fontFamily: fontFamily,
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: ls,
      color: AppColors.ink,
    );
    return TextTheme(
      displayLarge: s(44, FontWeight.w800, 1.15),
      displayMedium: s(36, FontWeight.w800, 1.15),
      displaySmall: s(30, FontWeight.w800, 1.2),
      headlineLarge: s(28, FontWeight.w800, 1.25),
      headlineMedium: s(25, FontWeight.w800, 1.25),
      headlineSmall: s(22, FontWeight.w700, 1.3),
      titleLarge: s(19, FontWeight.w700, 1.35),
      titleMedium: s(16, FontWeight.w700, 1.4),
      titleSmall: s(14, FontWeight.w700, 1.4),
      bodyLarge: s(16, FontWeight.w400, 1.55),
      bodyMedium: s(14, FontWeight.w400, 1.55),
      bodySmall: s(
        12.5,
        FontWeight.w400,
        1.5,
      ).copyWith(color: AppColors.inkMuted),
      labelLarge: s(15, FontWeight.w700, 1.25, ls: 0.1),
      labelMedium: s(12.5, FontWeight.w600, 1.3, ls: 0.1),
      labelSmall: s(11, FontWeight.w700, 1.3, ls: 0.3),
    );
  }

  static ThemeData light({String? fontFamily}) {
    const scheme = colorScheme;
    final text = textTheme(fontFamily);
    const buttonShape = RoundedRectangleBorder(borderRadius: AppRadius.mdAll);
    const buttonPadding = EdgeInsets.symmetric(
      horizontal: AppSpacing.lg + AppSpacing.xs,
      vertical: AppSpacing.md,
    );
    const buttonMinSize = Size(64, 48);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      fontFamily: fontFamily,
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        shadowColor: scheme.outlineVariant,
        centerTitle: false,
        titleSpacing: AppSpacing.lg,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonMinSize,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonMinSize,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: text.labelLarge,
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.55)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
          textStyle: text.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: buttonMinSize,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: text.labelLarge,
          elevation: 0,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        minVerticalPadding: AppSpacing.md,
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        subtitleTextStyle: text.bodySmall,
        leadingAndTrailingTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
          visualDensity: VisualDensity.standard,
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: scheme.outline.withValues(alpha: 0.45)),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.surfaceContainerLowest,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? scheme.onSurface.withValues(alpha: 0.38)
                : states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : scheme.onSurface,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
        labelStyle: text.labelMedium?.copyWith(color: scheme.onSurface),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        actionTextColor: scheme.inversePrimary,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        insetPadding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          0,
          AppSpacing.gutter,
          AppSpacing.md,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: scheme.outlineVariant,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : scheme.outline.withValues(alpha: 0.6),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: Colors.transparent,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: AppRadius.smAll,
        ),
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
      ),
    );
  }
}
