import 'package:flutter/widgets.dart';

/// Design tokens from design_handoff_two_keys/README.md. Two backgrounds only:
/// paper and ink. Green is reserved for approve/secure/success — never
/// decoration. Red appears only for blocked/destructive.
abstract final class TkColors {
  static const paper = Color(0xFFF7F5F1);
  static const paperSunk = Color(0xFFF2EFE9);
  static const paperField = Color(0xFFEDEAE3);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1B1A17);
  static const inkDarkGradEnd = Color(0xFF221F1B);
  static const inkDarkest = Color(0xFF12110F);
  static const green = Color(0xFF2F6F5B);
  static const greenHover = Color(0xFF38826B);
  static const greenBright = Color(0xFF3E9A76);
  static const greenBrightHover = Color(0xFF4CB187);
  static const greenPale = Color(0xFFE4EFE9);
  static const greenTint = Color(0xFFF1F7F4);
  static const mint = Color(0xFF7FD1AC);
  static const mintPale = Color(0xFFB8E0CE);
  static const greenDeep = Color(0xFF1B4636);
  static const danger = Color(0xFF8A3123);
  static const dangerBg = Color(0xFF7A2E22);
  static const onGreenBrightText = Color(0xFF0E1A15);

  static const ink70 = Color.fromRGBO(27, 26, 23, .7);
  static const ink60 = Color.fromRGBO(27, 26, 23, .6);
  static const ink55 = Color.fromRGBO(27, 26, 23, .55);
  static const ink50 = Color.fromRGBO(27, 26, 23, .5);
  static const ink45 = Color.fromRGBO(27, 26, 23, .45);
  static const ink35 = Color.fromRGBO(27, 26, 23, .35);
  static const ink16 = Color.fromRGBO(27, 26, 23, .16);
  static const ink10 = Color.fromRGBO(27, 26, 23, .10);
  static const ink06 = Color.fromRGBO(27, 26, 23, .06);
  static const paper85 = Color.fromRGBO(247, 245, 241, .85);
  static const paper72 = Color.fromRGBO(247, 245, 241, .72);
  static const paper55 = Color.fromRGBO(247, 245, 241, .55);
  static const paper20 = Color.fromRGBO(247, 245, 241, .2);

  static const inkGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [ink, inkDarkGradEnd],
  );
}

abstract final class TkFonts {
  static const sans = 'InstrumentSans';
  static const mono = 'JetBrainsMono';
}

/// Type roles from the handoff table. Sizes are logical pixels.
abstract final class TkText {
  static const heroTitle = TextStyle(
    fontFamily: TkFonts.sans,
    fontSize: 34,
    fontWeight: FontWeight.w600,
    letterSpacing: 34 * -.028,
    height: 1.16,
    color: TkColors.ink,
  );
  static const screenTitle = TextStyle(
    fontFamily: TkFonts.sans,
    fontSize: 28,
    fontWeight: FontWeight.w600,
    letterSpacing: 28 * -.024,
    height: 1.2,
    color: TkColors.ink,
  );
  static const pageHeading = TextStyle(
    fontFamily: TkFonts.sans,
    fontSize: 32,
    fontWeight: FontWeight.w600,
    letterSpacing: 32 * -.02,
    height: 1.15,
    color: TkColors.ink,
  );
  static const cardTitle = TextStyle(
    fontFamily: TkFonts.sans,
    fontSize: 16.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 16.5 * -.01,
    color: TkColors.ink,
  );
  static const body = TextStyle(
    fontFamily: TkFonts.sans,
    fontSize: 15.5,
    fontWeight: FontWeight.w400,
    height: 1.6,
    color: TkColors.ink60,
  );
  static const bodySecondary = TextStyle(
    fontFamily: TkFonts.sans,
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    height: 1.55,
    color: TkColors.ink55,
  );
  static const metadata = TextStyle(
    fontFamily: TkFonts.sans,
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    color: TkColors.ink50,
  );
  static const sectionLabel = TextStyle(
    fontFamily: TkFonts.sans,
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
    letterSpacing: 11.5 * .08,
    color: TkColors.ink45,
  );
  static const badge = TextStyle(
    fontFamily: TkFonts.sans,
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 10.5 * .06,
  );
  static const codeRow = TextStyle(
    fontFamily: TkFonts.mono,
    fontSize: 19,
    fontWeight: FontWeight.w500,
    letterSpacing: 19 * .04,
    color: TkColors.ink,
  );
  static const codeCard = TextStyle(
    fontFamily: TkFonts.mono,
    fontSize: 22,
    fontWeight: FontWeight.w500,
    letterSpacing: 22 * .02,
    color: TkColors.ink,
  );
  static const codeDetail = TextStyle(
    fontFamily: TkFonts.mono,
    fontSize: 38,
    fontWeight: FontWeight.w500,
    letterSpacing: 38 * .03,
    color: TkColors.ink,
  );
  static const codeHero = TextStyle(
    fontFamily: TkFonts.mono,
    fontSize: 52,
    fontWeight: FontWeight.w500,
    letterSpacing: 52 * .04,
  );
  static const primaryButton = TextStyle(
    fontFamily: TkFonts.sans,
    fontSize: 16.5,
    fontWeight: FontWeight.w700,
  );
  static const secondaryButton = TextStyle(
    fontFamily: TkFonts.sans,
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );
}

abstract final class TkRadius {
  static const pill = 99.0;
  static const button = 18.0;
  static const card = 18.0;
  static const largeCard = 20.0;
  static const panel = 16.0;
  static const row = 14.0;
  static const field = 14.0;
  static const tile = 13.0;
  static const chip = 7.0;
}

abstract final class TkSpace {
  /// Screen side padding.
  static const side = 24.0;
  static const sideWide = 14.0; // card lists run wider than the text gutter
  static const bottom = 44.0;
}

abstract final class TkMotion {
  static const riseIn = Duration(milliseconds: 320);
  static const riseInFast = Duration(milliseconds: 290);
  static const feedback = Duration(milliseconds: 180);
  static const bar = Duration(milliseconds: 900);
  static const copiedHold = Duration(seconds: 2);
}
