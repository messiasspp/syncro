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

/// Detached floating glassmorphic pill navigation bar with real-time Gaussian blur
/// and glowing active tab capsule.
class FloatingGlassNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<GlassNavDestination> destinations;

  const FloatingGlassNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(34),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
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
            borderRadius: BorderRadius.circular(34),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(34),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.16)
                        : SyncroColors.electricIndigo.withValues(alpha: 0.18),
                    width: 1.2,
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [
                            const Color(0xFF162038).withValues(alpha: 0.86),
                            const Color(0xFF0E1526).withValues(alpha: 0.78),
                          ]
                        : [
                            Colors.white.withValues(alpha: 0.90),
                            const Color(0xFFEEF2FF).withValues(alpha: 0.84),
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
    );
  }
}

class _GlassNavButton extends StatelessWidget {
  final GlassNavDestination destination;
  final bool isSelected;
  final VoidCallback onTap;

  const _GlassNavButton({
    required this.destination,
    required this.isSelected,
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
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
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
                size: 21,
                color: isSelected ? primary : unselectedColor,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
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
