import 'package:flutter/material.dart';

import 'tokens.dart';

/// Shared building blocks matching the prototype's components. Hand-drawn
/// only where the design's look demands it; native controls (switches,
/// dialogs, keyboards) stay native per the handoff's fidelity note.

class TkPrimaryButton extends StatelessWidget {
  const TkPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.background = TkColors.green,
    this.foreground = TkColors.paper,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color background;
  final Color foreground;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: TkMotion.feedback,
      opacity: enabled ? 1 : .45,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(TkRadius.button),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(TkRadius.button),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TkText.primaryButton.copyWith(color: foreground)),
          ),
        ),
      ),
    );
  }
}

class TkSecondaryButton extends StatelessWidget {
  const TkSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.borderColor = TkColors.ink16,
    this.foreground = TkColors.ink,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color borderColor;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(TkRadius.button),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(TkRadius.button),
        child: Container(
          constraints: const BoxConstraints(minHeight: 54),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: 1.5),
            borderRadius: BorderRadius.circular(TkRadius.button),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TkText.secondaryButton.copyWith(color: foreground)),
        ),
      ),
    );
  }
}

class TkTextButton extends StatelessWidget {
  const TkTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(TkRadius.row),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(8),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TkText.secondaryButton
                .copyWith(fontSize: 15, color: color ?? TkColors.ink50)),
      ),
    );
  }
}

/// The brand tile: rounded square with the digit 2 (all marks are drawn, no
/// image assets — per the handoff).
class TkBrandTile extends StatelessWidget {
  const TkBrandTile({
    super.key,
    this.size = 48,
    this.background = TkColors.green,
    this.foreground = TkColors.paper,
  });

  final double size;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(size * .31),
      ),
      alignment: Alignment.center,
      child: Text(
        '2',
        style: TextStyle(
          fontFamily: TkFonts.sans,
          fontSize: size * .44,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

/// Account avatar: colored tile with the site's initial.
class TkAvatarTile extends StatelessWidget {
  const TkAvatarTile({
    super.key,
    required this.letter,
    required this.color,
    this.size = 42,
  });

  final String letter;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * .31),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          fontFamily: TkFonts.sans,
          fontSize: size * .4,
          fontWeight: FontWeight.w700,
          color: TkColors.paper,
        ),
      ),
    );
  }
}

/// White card with the 1px hairline border — never a shadow.
class TkCard extends StatelessWidget {
  const TkCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    this.radius = TkRadius.card,
    this.color = TkColors.surface,
    this.borderColor = TkColors.ink06,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color color;
  final Color borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = AnimatedContainer(
      duration: TkMotion.feedback,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: card,
    );
  }
}

/// Quiet inset note panel (paper-sunk).
class TkNote extends StatelessWidget {
  const TkNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      decoration: BoxDecoration(
        color: TkColors.paperSunk,
        borderRadius: BorderRadius.circular(TkRadius.row),
      ),
      child: Text(text,
          style: TkText.bodySecondary.copyWith(
              fontSize: 13, color: const Color.fromRGBO(27, 26, 23, .65))),
    );
  }
}

/// UPPERCASE section label.
class TkSectionLabel extends StatelessWidget {
  const TkSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(), style: TkText.sectionLabel);
  }
}

/// Small uppercase badge chip (MATCHED / BEST / ACTIVE...).
class TkBadge extends StatelessWidget {
  const TkBadge(this.text,
      {super.key,
      this.color = TkColors.green,
      this.background = TkColors.greenPale});

  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(TkRadius.chip),
      ),
      child: Text(text.toUpperCase(),
          style: TkText.badge.copyWith(color: color)),
    );
  }
}

/// Onboarding progress: three pills, active ones stretch to 22px.
class TkStepPills extends StatelessWidget {
  const TkStepPills({super.key, required this.step, this.total = 3});

  final int step; // 1-based
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 1; i <= total; i++) ...[
          AnimatedContainer(
            duration: TkMotion.feedback,
            width: i <= step ? 22 : 7,
            height: 6,
            decoration: BoxDecoration(
              color: i <= step ? TkColors.green : TkColors.ink16,
              borderRadius: BorderRadius.circular(TkRadius.pill),
            ),
          ),
          const SizedBox(width: 7),
        ],
        const SizedBox(width: 6),
        Text('Step $step of $total', style: TkText.metadata),
      ],
    );
  }
}

/// The 30-second countdown bar: 3px, green fill emptying linearly.
class TkCountdownBar extends StatelessWidget {
  const TkCountdownBar({
    super.key,
    required this.fraction,
    this.background = TkColors.ink10,
    this.fill = TkColors.green,
  });

  /// Remaining fraction of the window, 0..1.
  final double fraction;
  final Color background;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 3,
        child: Stack(
          children: [
            Container(color: background),
            AnimatedFractionallySizedBox(
              duration: TkMotion.bar,
              curve: Curves.linear,
              alignment: Alignment.centerLeft,
              widthFactor: fraction.clamp(0, 1),
              child: Container(color: fill),
            ),
          ],
        ),
      ),
    );
  }
}

/// The copy glyph: two offset sheets, back at 55% opacity, front filled with
/// the button's own background so it occludes cleanly.
class TkCopyGlyph extends StatelessWidget {
  const TkCopyGlyph({super.key, required this.color, required this.fill});

  final Color color;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    Widget sheet({required bool front}) => Container(
          width: 12,
          height: 14,
          decoration: BoxDecoration(
            color: front ? fill : null,
            border: Border.all(
                color: front ? color : color.withValues(alpha: .55),
                width: 1.6),
            borderRadius: BorderRadius.circular(3),
          ),
        );
    return SizedBox(
      width: 22,
      height: 22,
      child: Stack(
        children: [
          Positioned(top: 0, left: 0, child: sheet(front: false)),
          Positioned(bottom: 0, right: 0, child: sheet(front: true)),
        ],
      ),
    );
  }
}

/// Pulsing ring waiting indicator. Faster for "act now", slower for
/// "waiting on something else".
class TkPulseRing extends StatefulWidget {
  const TkPulseRing({
    super.key,
    required this.child,
    this.size = 96,
    this.color = TkColors.mint,
    this.period = const Duration(milliseconds: 1400),
    this.borderRadius,
  });

  final Widget child;
  final double size;
  final Color color;
  final Duration period;
  final BorderRadius? borderRadius;

  @override
  State<TkPulseRing> createState() => _TkPulseRingState();
}

class _TkPulseRingState extends State<TkPulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.period)..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = Curves.easeOut.transform(_controller.value);
              return Transform.scale(
                scale: 1 + .35 * t,
                child: Opacity(
                  opacity: (.5 * (1 - t)).clamp(0, 1),
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: widget.borderRadius == null
                          ? BoxShape.circle
                          : BoxShape.rectangle,
                      borderRadius: widget.borderRadius,
                      border: Border.all(color: widget.color, width: 2),
                    ),
                  ),
                ),
              );
            },
          ),
          widget.child,
        ],
      ),
    );
  }
}

/// Full-screen state entry: translateY(18) → 0, fade, 320ms ease-out.
class TkRiseIn extends StatefulWidget {
  const TkRiseIn({super.key, required this.child, this.duration});

  final Widget child;
  final Duration? duration;

  @override
  State<TkRiseIn> createState() => _TkRiseInState();
}

class _TkRiseInState extends State<TkRiseIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration ?? TkMotion.riseIn,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - curve.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Deterministic brand color for an account tile, stable per site name.
Color brandColorFor(String siteName) {
  const palette = [
    TkColors.ink,
    TkColors.green,
    Color(0xFF7A5AA8),
    Color(0xFF2A5AA8),
    Color(0xFFB0682E),
    Color(0xFF8A3B4E),
    Color(0xFF3A6B8A),
    Color(0xFF6B7A2E),
  ];
  var hash = 0;
  for (final unit in siteName.toLowerCase().codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return palette[hash % palette.length];
}
