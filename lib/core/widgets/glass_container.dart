import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/syncro_theme.dart';

/// Renders an ambient background with subtle glowing radial gradient orbs
/// so frosted glass (`BackdropFilter`) surfaces refract rich color and depth.
class AmbientMeshBackground extends StatelessWidget {
  final Widget child;

  const AmbientMeshBackground({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: isDark ? SyncroColors.darkCanvas : SyncroColors.lightCanvas,
        ),
        // Top-left Indigo / Amethyst ambient orb
        Positioned(
          top: -90,
          left: -70,
          child: IgnorePointer(
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    SyncroColors.electricIndigo.withValues(
                      alpha: isDark ? 0.24 : 0.14,
                    ),
                    SyncroColors.electricIndigo.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Center-right Clinical Emerald ambient orb
        Positioned(
          top: 240,
          right: -90,
          child: IgnorePointer(
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    SyncroColors.clinicalEmerald.withValues(
                      alpha: isDark ? 0.18 : 0.11,
                    ),
                    SyncroColors.clinicalEmerald.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Bottom-left Amethyst ambient orb behind the floating nav bar
        Positioned(
          bottom: -60,
          left: 30,
          child: IgnorePointer(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    SyncroColors.amethystViolet.withValues(
                      alpha: isDark ? 0.20 : 0.12,
                    ),
                    SyncroColors.amethystViolet.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Frosted glassmorphic card/surface powered by `BackdropFilter` Gaussian blur,
/// translucent gradient surface, and specular border highlight.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blurSigma;
  final Color? tintColor;
  final Color? borderColor;
  final VoidCallback? onTap;

  const GlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 20,
    this.blurSigma = 16,
    this.tintColor,
    this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveTint = tintColor ??
        (isDark ? SyncroColors.darkSurface : SyncroColors.lightSurface);
    final effectiveBorder = borderColor ??
        (isDark
            ? Colors.white.withValues(alpha: 0.12)
            : SyncroColors.electricIndigo.withValues(alpha: 0.14));

    Widget surface = Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: effectiveBorder, width: 1.1),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  effectiveTint.withValues(alpha: isDark ? 0.78 : 0.88),
                  effectiveTint.withValues(alpha: isDark ? 0.62 : 0.74),
                ],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );

    if (onTap != null) {
      return AnimatedScaleTap(
        onTap: onTap,
        child: surface,
      );
    }
    return surface;
  }
}

/// Interactive wrapper that scales down slightly (`0.965x`) on press with
/// subtle haptic feedback.
class AnimatedScaleTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;

  const AnimatedScaleTap({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.97,
  });

  @override
  State<AnimatedScaleTap> createState() => _AnimatedScaleTapState();
}

class _AnimatedScaleTapState extends State<AnimatedScaleTap> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap?.call();
      },
      child: AnimatedScale(
        scale: _isPressed ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// Smooth staggered fade + upward slide entrance animation for cards and rows.
class StaggeredReveal extends StatelessWidget {
  final int index;
  final Widget child;

  const StaggeredReveal({
    super.key,
    required this.index,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final durationMs = (240 + (index.clamp(0, 8) * 35));
    return TweenAnimationBuilder<double>(
      key: ValueKey('reveal_$index'),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: durationMs),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1.0 - value) * 14),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Item model for [FloatingGlassNavBar].
class GlassNavDestination {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const GlassNavDestination({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

/// Detached floating glassmorphic pill navigation bar with:
/// 1. A morphing primary Floating Action Button that floats above the bar when
///    at the top of the screen and **docks/sticks onto the right edge of the bar**
///    when scrolling down.
/// 2. A secondary **"Scroll to Top" (`^`) frosted glass button** that springs
///    into view above the docked bar whenever the user scrolls down.
class FloatingGlassNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<GlassNavDestination> destinations;
  final bool isActionDocked;
  final String? actionLabel;
  final IconData actionIcon;
  final VoidCallback? onActionTap;
  final VoidCallback? onScrollToTopTap;

  const FloatingGlassNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.isActionDocked = false,
    this.actionLabel,
    this.actionIcon = Icons.add_rounded,
    this.onActionTap,
    this.onScrollToTopTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final hasAction = actionLabel != null && onActionTap != null;
    final docked = hasAction && isActionDocked;
    final showScrollToTop = isActionDocked && onScrollToTopTap != null;

    return SafeArea(
      top: false,
      child: SizedBox(
        height: (hasAction || showScrollToTop) ? 148 : 82,
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            // 1. Main 5-Tab Floating Glass Bar (narrows on right when primary FAB docks into it)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              left: 14,
              right: docked ? 78 : 14,
              bottom: 12,
              height: 68,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.horizontal(
                    left: const Radius.circular(34),
                    right: Radius.circular(docked ? 18 : 34),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:
                          Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: primary.withValues(alpha: isDark ? 0.16 : 0.08),
                      blurRadius: 24,
                      spreadRadius: -2,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.horizontal(
                    left: const Radius.circular(34),
                    right: Radius.circular(docked ? 18 : 34),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.horizontal(
                          left: const Radius.circular(34),
                          right: Radius.circular(docked ? 18 : 34),
                        ),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.16)
                              : SyncroColors.electricIndigo
                                  .withValues(alpha: 0.18),
                          width: 1.2,
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isDark
                              ? [
                                  const Color(0xFF162038)
                                      .withValues(alpha: 0.86),
                                  const Color(0xFF0E1526)
                                      .withValues(alpha: 0.78),
                                ]
                              : [
                                  Colors.white.withValues(alpha: 0.90),
                                  const Color(0xFFEEF2FF)
                                      .withValues(alpha: 0.84),
                                ],
                        ),
                      ),
                      child: Row(
                        children: [
                          for (int i = 0; i < destinations.length; i++)
                            Expanded(
                              child: _GlassNavButton(
                                destination: destinations[i],
                                isSelected: i == selectedIndex,
                                isCompact: docked,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  onDestinationSelected(i);
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 2. Secondary "Scroll to Top" Frosted Glass Button:
            // Appears above the right side of the bar (bottom: 90) when the primary
            // action button docks into the bar!
            Positioned(
              right: 14,
              bottom: 90,
              child: IgnorePointer(
                ignoring: !showScrollToTop,
                child: AnimatedScale(
                  scale: showScrollToTop ? 1.0 : 0.4,
                  duration: const Duration(milliseconds: 280),
                  curve: showScrollToTop
                      ? Curves.easeOutBack
                      : Curves.easeInCubic,
                  child: AnimatedOpacity(
                    opacity: showScrollToTop ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 220),
                    child: AnimatedScaleTap(
                      onTap: onScrollToTopTap,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDark ? 0.40 : 0.12,
                              ),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                            BoxShadow(
                              color: SyncroColors.clinicalEmerald
                                  .withValues(alpha: 0.30),
                              blurRadius: 14,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: SyncroColors.clinicalEmerald
                                      .withValues(alpha: 0.65),
                                  width: 1.3,
                                ),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: isDark
                                      ? [
                                          const Color(0xFF16243E)
                                              .withValues(alpha: 0.88),
                                          const Color(0xFF0F192C)
                                              .withValues(alpha: 0.82),
                                        ]
                                      : [
                                          Colors.white.withValues(alpha: 0.92),
                                          const Color(0xFFE6FFFA)
                                              .withValues(alpha: 0.86),
                                        ],
                                ),
                              ),
                              child: const Icon(
                                Icons.keyboard_double_arrow_up_rounded,
                                color: SyncroColors.clinicalEmerald,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 3. Primary Morphing Floating Action Button:
            // - Undocked (top of scroll): Expanded pill floating ABOVE the bar (bottom: 90)
            // - Docked (scrolled down): Slides down to bottom: 12 and sticks onto the right end of the bar!
            if (hasAction)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                right: 14,
                bottom: docked ? 12 : 90,
                height: docked ? 68 : 48,
                child: AnimatedScaleTap(
                  onTap: onActionTap,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(docked ? 18 : 26),
                        right: const Radius.circular(34),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: primary.withValues(alpha: 0.45),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(docked ? 18 : 26),
                        right: const Radius.circular(34),
                      ),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.horizontal(
                              left: Radius.circular(docked ? 18 : 26),
                              right: const Radius.circular(34),
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.35),
                              width: 1.2,
                            ),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                primary,
                                SyncroColors.amethystViolet,
                              ],
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                actionIcon,
                                color: Colors.white,
                                size: docked ? 24 : 20,
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 260),
                                curve: Curves.easeOutCubic,
                                child: docked
                                    ? const SizedBox.shrink()
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const SizedBox(width: 7),
                                          Text(
                                            actionLabel!,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13.5,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GlassNavButton extends StatelessWidget {
  final GlassNavDestination destination;
  final bool isSelected;
  final bool isCompact;
  final VoidCallback onTap;

  const _GlassNavButton({
    required this.destination,
    required this.isSelected,
    this.isCompact = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final unselectedColor = isDark
        ? Colors.white.withValues(alpha: 0.60)
        : const Color(0xFF475569);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: isSelected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    primary.withValues(alpha: isDark ? 0.30 : 0.18),
                    SyncroColors.amethystViolet.withValues(
                      alpha: isDark ? 0.22 : 0.12,
                    ),
                  ],
                )
              : null,
          border: isSelected
              ? Border.all(
                  color: primary.withValues(alpha: isDark ? 0.45 : 0.30),
                  width: 1,
                )
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: isSelected ? 1.12 : 1.0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              child: Icon(
                isSelected ? destination.activeIcon : destination.icon,
                size: isCompact ? 19.5 : 21,
                color: isSelected ? primary : unselectedColor,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isCompact ? 9.5 : 10.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? (isDark ? Colors.white : primary)
                    : unselectedColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
