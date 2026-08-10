import 'package:flutter/material.dart';

/// Theme-aware colors for chrome (backgrounds, dialogs, menus, grid, node
/// chrome) that aren't covered by [ColorScheme]. Directory/file colors are
/// intentionally excluded - those are user-configurable defaults independent
/// of light/dark mode.
class FileTileColors extends ThemeExtension<FileTileColors> {
  final Color background;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;
  final Color textDim;
  final Color borderSubtle;
  final Color overlayHover;
  final Color iconDisabled;
  final Color nodeBorderDefault;
  final Color nodeBackgroundDefault;
  final Color nodeLabelText;
  final Color symlinkBadgeBackground;
  final Color gridLine;
  final Color gridLineOrigin;
  final Color accent;

  const FileTileColors({
    required this.background,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDim,
    required this.borderSubtle,
    required this.overlayHover,
    required this.iconDisabled,
    required this.nodeBorderDefault,
    required this.nodeBackgroundDefault,
    required this.nodeLabelText,
    required this.symlinkBadgeBackground,
    required this.gridLine,
    required this.gridLineOrigin,
    required this.accent,
  });

  static const dark = FileTileColors(
    background: Color(0xFF121212),
    surface: Color(0xFF1E1E1E),
    textPrimary: Colors.white,
    textSecondary: Color(0xDEFFFFFF),
    textDim: Colors.white54,
    borderSubtle: Colors.white24,
    overlayHover: Color(0x14FFFFFF),
    iconDisabled: Colors.grey,
    nodeBorderDefault: Color(0x0DFFFFFF),
    nodeBackgroundDefault: Color(0x03FFFFFF),
    nodeLabelText: Color(0xCCFFFFFF),
    symlinkBadgeBackground: Color(0xB3757575),
    gridLine: Color(0xFF353535),
    gridLineOrigin: Color(0xFF4A4A4A),
    accent: Colors.blueAccent,
  );

  // Warm parchment palette for light mode.
  static const light = FileTileColors(
    background: Color(0xFCF3ECD9),
    surface: Color(0xFFE9DFC3),
    textPrimary: Color(0xFF2D1F10),
    textSecondary: Color(0xEB801F10),
    textDim: Color(0x972D1F10),
    borderSubtle: Color(0x402D1F10),
    overlayHover: Color(0x142D1F10),
    iconDisabled: Color(0xFF9C8A63),
    nodeBorderDefault: Color(0x142D1F10),
    nodeBackgroundDefault: Color(0x06E0D0B8),
    nodeLabelText: Color(0xFF0D0700),
    symlinkBadgeBackground: Color(0xB39C8A63),
    gridLine: Color(0xF2E6DFB8),
    gridLineOrigin: Color(0xFFD4C192),
    accent: Colors.blueAccent,
  );

  @override
  FileTileColors copyWith({
    Color? background,
    Color? surface,
    Color? textPrimary,
    Color? textSecondary,
    Color? textDim,
    Color? borderSubtle,
    Color? overlayHover,
    Color? iconDisabled,
    Color? nodeBorderDefault,
    Color? nodeBackgroundDefault,
    Color? nodeLabelText,
    Color? symlinkBadgeBackground,
    Color? gridLine,
    Color? gridLineOrigin,
    Color? accent,
  }) {
    return FileTileColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textDim: textDim ?? this.textDim,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      overlayHover: overlayHover ?? this.overlayHover,
      iconDisabled: iconDisabled ?? this.iconDisabled,
      nodeBorderDefault: nodeBorderDefault ?? this.nodeBorderDefault,
      nodeBackgroundDefault: nodeBackgroundDefault ?? this.nodeBackgroundDefault,
      nodeLabelText: nodeLabelText ?? this.nodeLabelText,
      symlinkBadgeBackground: symlinkBadgeBackground ?? this.symlinkBadgeBackground,
      gridLine: gridLine ?? this.gridLine,
      gridLineOrigin: gridLineOrigin ?? this.gridLineOrigin,
      accent: accent ?? this.accent,
    );
  }

  @override
  FileTileColors lerp(ThemeExtension<FileTileColors>? other, double t) {
    if (other is! FileTileColors) return this;
    return FileTileColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textDim: Color.lerp(textDim, other.textDim, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      overlayHover: Color.lerp(overlayHover, other.overlayHover, t)!,
      iconDisabled: Color.lerp(iconDisabled, other.iconDisabled, t)!,
      nodeBorderDefault: Color.lerp(nodeBorderDefault, other.nodeBorderDefault, t)!,
      nodeBackgroundDefault: Color.lerp(nodeBackgroundDefault, other.nodeBackgroundDefault, t)!,
      nodeLabelText: Color.lerp(nodeLabelText, other.nodeLabelText, t)!,
      symlinkBadgeBackground: Color.lerp(symlinkBadgeBackground, other.symlinkBadgeBackground, t)!,
      gridLine: Color.lerp(gridLine, other.gridLine, t)!,
      gridLineOrigin: Color.lerp(gridLineOrigin, other.gridLineOrigin, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
    );
  }
}
