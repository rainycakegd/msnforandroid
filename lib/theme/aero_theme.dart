// lib/theme/aero_theme.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';

/// A complete color set for one Aero theme.
class AeroPalette {
  final AeroThemeId id;
  final String name;
  final Color primaryDark;
  final Color primaryLight;
  final Color accent;
  final Color glassTint;
  final Color textOnGlass;
  final Color textDark;
  final Color bubbleMine;
  final Color bubbleTheirs;

  const AeroPalette({
    required this.id,
    required this.name,
    required this.primaryDark,
    required this.primaryLight,
    required this.accent,
    required this.glassTint,
    required this.textOnGlass,
    required this.textDark,
    required this.bubbleMine,
    required this.bubbleTheirs,
  });

  /// Main window gradient (dark top to light bottom).
  LinearGradient get backgroundGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          primaryDark,
          Color.lerp(primaryDark, primaryLight, 0.55)!,
          primaryLight,
          Colors.white,
        ],
        stops: const <double>[0.0, 0.35, 0.75, 1.0],
      );

  /// Glossy button / title bar gradient with a hard highlight line in the middle.
  LinearGradient get glossGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Color.lerp(primaryLight, Colors.white, 0.55)!,
          primaryLight,
          primaryDark,
          Color.lerp(primaryDark, primaryLight, 0.35)!,
        ],
        stops: const <double>[0.0, 0.49, 0.5, 1.0],
      );

  /// Semi-transparent glass panel fill.
  LinearGradient get glassGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Colors.white.withOpacity(0.78),
          glassTint.withOpacity(0.55),
          Colors.white.withOpacity(0.45),
        ],
        stops: const <double>[0.0, 0.5, 1.0],
      );
}

class AeroPalettes {
  static const AeroPalette msnClassic = AeroPalette(
    id: AeroThemeId.msnClassic,
    name: 'MSN Classic',
    primaryDark: Color(0xFF0B5CAB),
    primaryLight: Color(0xFF9FD4FF),
    accent: Color(0xFF3FA9F5),
    glassTint: Color(0xFFD6EEFF),
    textOnGlass: Color(0xFFFFFFFF),
    textDark: Color(0xFF0A2E57),
    bubbleMine: Color(0xFFCDE9FF),
    bubbleTheirs: Color(0xFFFFFFFF),
  );

  static const AeroPalette aquaGreen = AeroPalette(
    id: AeroThemeId.aquaGreen,
    name: 'Aqua Green',
    primaryDark: Color(0xFF0B8A6F),
    primaryLight: Color(0xFFA5F0D2),
    accent: Color(0xFF2FD3A0),
    glassTint: Color(0xFFD8FFF0),
    textOnGlass: Color(0xFFFFFFFF),
    textDark: Color(0xFF0A4A3B),
    bubbleMine: Color(0xFFC9F7E3),
    bubbleTheirs: Color(0xFFFFFFFF),
  );

  static const AeroPalette sunsetOrange = AeroPalette(
    id: AeroThemeId.sunsetOrange,
    name: 'Sunset Orange',
    primaryDark: Color(0xFFD35400),
    primaryLight: Color(0xFFFFD29A),
    accent: Color(0xFFFF9A3C),
    glassTint: Color(0xFFFFEBD2),
    textOnGlass: Color(0xFFFFFFFF),
    textDark: Color(0xFF5A2A05),
    bubbleMine: Color(0xFFFFE2BC),
    bubbleTheirs: Color(0xFFFFFFFF),
  );

  static const List<AeroPalette> all = <AeroPalette>[
    msnClassic,
    aquaGreen,
    sunsetOrange,
  ];

  static AeroPalette byId(AeroThemeId id) {
    switch (id) {
      case AeroThemeId.msnClassic:
        return msnClassic;
      case AeroThemeId.aquaGreen:
        return aquaGreen;
      case AeroThemeId.sunsetOrange:
        return sunsetOrange;
    }
  }
}

/// Holds the selected theme id and persists it locally.
class AeroThemeNotifier extends Notifier<AeroThemeId> {
  @override
  AeroThemeId build() {
    _load();
    return AeroThemeId.msnClassic;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(AppConstants.prefThemeId);
      if (stored != null) {
        final match = AeroThemeId.values.where((t) => t.name == stored);
        if (match.isNotEmpty) {
          state = match.first;
        }
      }
    } catch (_) {
      // Keep the default theme if local storage is unavailable.
    }
  }

  Future<void> setTheme(AeroThemeId id) async {
    state = id;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.prefThemeId, id.name);
    } catch (_) {
      // Ignore persistence errors; the theme still applies for this session.
    }
  }
}

final aeroThemeIdProvider =
    NotifierProvider<AeroThemeNotifier, AeroThemeId>(AeroThemeNotifier.new);

final aeroPaletteProvider = Provider<AeroPalette>((ref) {
  return AeroPalettes.byId(ref.watch(aeroThemeIdProvider));
});

/// Reusable text styles.
class AeroTextStyles {
  static TextStyle get splashTitle => GoogleFonts.openSans(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        letterSpacing: 0.5,
        shadows: const <Shadow>[
          Shadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      );

  static TextStyle get title => GoogleFonts.openSans(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        shadows: const <Shadow>[
          Shadow(color: Color(0x55000000), blurRadius: 4, offset: Offset(0, 1)),
        ],
      );

  static TextStyle get heading => GoogleFonts.openSans(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AeroColors.textDark,
      );

  static TextStyle get body => GoogleFonts.openSans(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AeroColors.textDark,
      );

  static TextStyle get bodyBold => GoogleFonts.openSans(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AeroColors.textDark,
      );

  static TextStyle get buddyName => GoogleFonts.openSans(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AeroColors.textDark,
      );

  static TextStyle get statusMessage => GoogleFonts.openSans(
        fontSize: 12,
        fontStyle: FontStyle.italic,
        color: const Color(0xFF5B7A99),
      );

  static TextStyle get nowPlaying => GoogleFonts.openSans(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: const Color(0xFF2E8B3D),
      );

  static TextStyle get chatMessage => GoogleFonts.openSans(
        fontSize: 14,
        height: 1.3,
        color: AeroColors.textDark,
      );

  static TextStyle get timestamp => GoogleFonts.openSans(
        fontSize: 10,
        color: const Color(0xFF7A93AD),
      );

  static TextStyle get typing => GoogleFonts.openSans(
        fontSize: 12,
        fontStyle: FontStyle.italic,
        color: const Color(0xFF5B7A99),
      );

  static TextStyle get button => GoogleFonts.openSans(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        shadows: const <Shadow>[
          Shadow(color: Color(0x66000000), blurRadius: 3, offset: Offset(0, 1)),
        ],
      );

  static TextStyle get groupHeader => GoogleFonts.openSans(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AeroColors.msnBlueDark,
      );
}

/// Builds the Material [ThemeData] from an [AeroPalette].
class AeroTheme {
  static ThemeData build(AeroPalette palette) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: palette.primaryDark,
      brightness: Brightness.light,
    ).copyWith(
      primary: palette.primaryDark,
      secondary: palette.accent,
      surface: Colors.white,
      onPrimary: Colors.white,
    );

    final baseText = GoogleFonts.openSansTextTheme();

    return ThemeData(
      useMaterial3: false,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      primaryColor: palette.primaryDark,
      scaffoldBackgroundColor: palette.primaryLight,
      textTheme: baseText.apply(
        bodyColor: palette.textDark,
        displayColor: palette.textDark,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: AeroTextStyles.title,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withOpacity(0.85),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: GoogleFonts.openSans(
          color: const Color(0xFF7A93AD),
          fontSize: 14,
        ),
        labelStyle: GoogleFonts.openSans(color: palette.primaryDark),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.primaryDark.withOpacity(0.4)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.primaryDark.withOpacity(0.35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFD64545)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFD64545), width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.primaryDark,
        contentTextStyle: GoogleFonts.openSans(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: palette.primaryDark.withOpacity(0.15),
        thickness: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.primaryDark,
      ),
    );
  }
}

/// Reusable glossy decorations so every widget shares one Aero look.
class AeroDecorations {
  /// Semi-transparent glass panel with white top highlight and soft shadow.
  static BoxDecoration glassPanel(
    AeroPalette palette, {
    double radius = 18,
  }) {
    return BoxDecoration(
      gradient: palette.glassGradient,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white.withOpacity(0.85), width: 1.2),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: palette.primaryDark.withOpacity(0.28),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: Colors.white.withOpacity(0.6),
          blurRadius: 4,
          offset: const Offset(0, -1),
        ),
      ],
    );
  }

  /// Glossy pill button.
  static BoxDecoration glossButton(
    AeroPalette palette, {
    double radius = 22,
    bool pressed = false,
  }) {
    return BoxDecoration(
      gradient: palette.glossGradient,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: Colors.white.withOpacity(0.9),
        width: 1.4,
      ),
      boxShadow: pressed
          ? <BoxShadow>[
              BoxShadow(
                color: palette.primaryDark.withOpacity(0.3),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ]
          : <BoxShadow>[
              BoxShadow(
                color: palette.primaryDark.withOpacity(0.5),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
    );
  }

  /// Chat bubble decoration.
  static BoxDecoration bubble(AeroPalette palette, {required bool mine}) {
    final base = mine ? palette.bubbleMine : palette.bubbleTheirs;
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Colors.white.withOpacity(0.95),
          base,
          Color.lerp(base, palette.primaryLight, 0.35)!,
        ],
        stops: const <double>[0.0, 0.45, 1.0],
      ),
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(16),
        topRight: const Radius.circular(16),
        bottomLeft: Radius.circular(mine ? 16 : 4),
        bottomRight: Radius.circular(mine ? 4 : 16),
      ),
      border: Border.all(
        color: palette.primaryDark.withOpacity(0.25),
        width: 1,
      ),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: palette.primaryDark.withOpacity(0.18),
          blurRadius: 6,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }
}