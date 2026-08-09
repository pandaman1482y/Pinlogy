import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const ink = Color(0xFF1A2620);
const moss = Color(0xFF3A6F56);
const mossDeep = Color(0xFF244C39);
const mint = Color(0xFFDCEFE4);
const mintSoft = Color(0xFFEEF6F1);
const canvas = Color(0xFFF4F7F5);
const leafWash = Color(0xFFC5DFD0);
const accentCoral = Color(0xFFFF6F91);
const accentIndigo = Color(0xFF6677E8);
const sunWash = Color(0xFFFFE7A8);
const borderSubtle = Color(0x00000000); // 枠線をほぼ使わない
const mist = Color(0x66FFFFFF);

TextStyle _display(
  double size, {
  FontWeight weight = FontWeight.w600,
  Color? color,
  double? height,
  double? tracking,
}) {
  return GoogleFonts.mPlusRounded1c(
    fontSize: size,
    fontWeight: weight,
    color: color ?? ink,
    height: height ?? 1.2,
    letterSpacing: tracking ?? -0.4,
  );
}

TextStyle _body(
  double size, {
  FontWeight weight = FontWeight.w500,
  Color? color,
  double? height,
}) {
  return GoogleFonts.zenKakuGothicNew(
    fontSize: size,
    fontWeight: weight,
    color: color ?? ink,
    height: height ?? 1.45,
  );
}

ThemeData buildPinlogyTheme() {
  final textTheme = TextTheme(
    headlineLarge: _display(34, weight: FontWeight.w800, tracking: -1.0),
    headlineMedium: _display(24, weight: FontWeight.w800, tracking: -0.5),
    titleLarge: _body(17, weight: FontWeight.w700),
    titleMedium: _body(15, weight: FontWeight.w700),
    bodyLarge: _body(15),
    bodyMedium: _body(14),
    bodySmall: _body(12, color: const Color(0xFF66756D)),
    labelLarge: _body(13, weight: FontWeight.w700),
  );

  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: canvas,
    colorScheme: ColorScheme.fromSeed(
      seedColor: moss,
      primary: moss,
      secondary: mossDeep,
      surface: Colors.white,
      onPrimary: Colors.white,
      onSurface: ink,
    ),
    textTheme: textTheme,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: _display(20, weight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      color: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white.withValues(alpha: 0.55),
      selectedColor: moss,
      side: BorderSide.none,
      labelStyle: _body(13, weight: FontWeight.w600, color: mossDeep),
      secondaryLabelStyle: _body(
        13,
        weight: FontWeight.w700,
        color: Colors.white,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: mossDeep,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        textStyle: _body(14, weight: FontWeight.w700, color: Colors.white),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: mossDeep,
        side: BorderSide(color: moss.withValues(alpha: 0.28)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        textStyle: _body(14, weight: FontWeight.w700),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: mossDeep,
      foregroundColor: Colors.white,
      elevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      extendedTextStyle: _body(
        14,
        weight: FontWeight.w700,
        color: Colors.white,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.62),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: moss.withValues(alpha: 0.45), width: 1.2),
      ),
      hintStyle: _body(14, color: const Color(0xFF8A968F)),
      prefixIconColor: mossDeep.withValues(alpha: 0.75),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: mossDeep,
      contentTextStyle: _body(14, weight: FontWeight.w600, color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0x14000000),
      thickness: 1,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFFFBFDFB),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFFFBFDFB),
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: Color(0xFFD0D9D4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      minTileHeight: 54,
      iconColor: mossDeep,
    ),
  );
}

/// 空気感のある背景。枠やカード感を弱める土台。
class PinlogyBackdrop extends StatelessWidget {
  const PinlogyBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF7FAF8), Color(0xFFEAF3EE), Color(0xFFF3F1EA)],
          stops: [0, 0.48, 1],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -95,
            left: -70,
            child: _blob(220, const Color(0xFFBFDCCB).withValues(alpha: 0.38)),
          ),
          Positioned(
            top: 220,
            right: -90,
            child: _blob(180, const Color(0xFFE8DFD0).withValues(alpha: 0.32)),
          ),
          Positioned(
            bottom: 80,
            left: 55,
            child: _blob(120, const Color(0xFFC9E0D2).withValues(alpha: 0.22)),
          ),
          child,
        ],
      ),
    );
  }

  Widget _blob(double size, Color color) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}

/// 浮遊するピル型タブ。
class PinlogyPillNav extends StatelessWidget {
  const PinlogyPillNav({
    super.key,
    required this.index,
    required this.onChanged,
    this.inboxBadge = 0,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final int inboxBadge;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: mossDeep.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              _item(0, Icons.terrain_rounded, 'マップ'),
              _item(1, Icons.inbox_rounded, '受信箱', badge: inboxBadge),
              _item(2, Icons.person_outline_rounded, 'マイページ'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(int i, IconData icon, String label, {int badge = 0}) {
    final selected = index == i;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: label,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: () => onChanged(i),
            borderRadius: BorderRadius.circular(999),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: selected ? mossDeep : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        icon,
                        size: 20,
                        color: selected
                            ? Colors.white
                            : const Color(0xFF6E7B74),
                      ),
                      if (badge > 0)
                        Positioned(
                          right: -10,
                          top: -6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: selected ? leafWash : moss,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '$badge',
                              style: _body(
                                9,
                                weight: FontWeight.w800,
                                color: selected ? mossDeep : Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: _body(
                      10,
                      weight: FontWeight.w700,
                      color: selected ? Colors.white : const Color(0xFF6E7B74),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
