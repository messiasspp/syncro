import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../theme/syncro_theme.dart';
import 'glass_container.dart';

/// Sliding-window lazy loader shared by every list in Syncro.
///
/// Only the items in `[start, end)` are mounted. "Load more" grows [end] by
/// [pageSize]; once the window exceeds [maxWindow] items, the oldest items are
/// trimmed from the top (keeping memory and layout cost bounded), and a
/// "Show earlier" button appears to bring them back.
///
/// Scroll anchoring: every mounted item reports its laid-out height through
/// [measure]. When items are trimmed/restored above the viewport, the scroll
/// offset is corrected by the exact recorded height in the same frame, so the
/// content the user is looking at never jumps.
class WindowedPager {
  WindowedPager({this.pageSize = 12, this.maxWindow = 36})
      : assert(maxWindow > pageSize),
        end = pageSize;

  /// Number of items appended/prepended per tap.
  final int pageSize;

  /// Maximum number of simultaneously mounted items.
  final int maxWindow;

  /// Fixed extent of the "Show earlier" header (button + spacing). Fixed so
  /// that its appearance/disappearance can be compensated deterministically.
  static const double earlierButtonExtent = 62;

  static const double _fallbackItemExtent = 140;

  static final Set<WindowedPager> _live = <WindowedPager>{};

  int start = 0;
  int end;

  final Map<int, double> _heights = <int, double>{};
  VoidCallback? _onChanged;

  /// Registers this pager so the global Scroll-to-Top action can reset it.
  void attach(VoidCallback onChanged) {
    _onChanged = onChanged;
    _live.add(this);
  }

  void detach() {
    _onChanged = null;
    _live.remove(this);
  }

  /// Resets every mounted pager back to its very first page.
  ///
  /// Returns `true` if any pager had trimmed items at the top (meaning the
  /// true top items were not mounted and the caller should jump, not animate).
  static bool resetAllLive() {
    var anyShifted = false;
    for (final pager in _live.toList()) {
      if (pager.isShifted) anyShifted = true;
      final changed = pager.start != 0 || pager.end != pager.pageSize;
      pager.reset();
      if (changed) pager._onChanged?.call();
    }
    return anyShifted;
  }

  bool get isShifted => start > 0;
  bool get hasEarlier => start > 0;
  bool hasMore(int total) => end < total;
  int remaining(int total) => math.max(0, total - end);

  int visibleStart(int total) => math.min(start, total);
  int visibleEnd(int total) => math.min(end, total);
  int visibleCount(int total) => visibleEnd(total) - visibleStart(total);

  /// Back to the first page (e.g. on filter change or Scroll-to-Top).
  void reset() {
    start = 0;
    end = pageSize;
    _heights.clear();
  }

  /// Wraps a list item so its laid-out height is recorded for anchoring.
  ///
  /// The wrapper is keyed by [globalIndex] so that, together with
  /// [findChildIndex], mounted items keep their elements/state (and don't
  /// replay entrance animations) when the window slides.
  Widget measure(int globalIndex, Widget child) {
    return _MeasureHeight(
      key: ValueKey<int>(globalIndex),
      onHeight: (h) => _heights[globalIndex] = h,
      child: child,
    );
  }

  /// `findChildIndexCallback` for builder lists whose item slots are laid out
  /// as `[leading widgets][window items][footer]`.
  int? findChildIndex(Key key, {required int leading, required int total}) {
    if (key is! ValueKey<int>) return null;
    final globalIndex = key.value;
    if (globalIndex < visibleStart(total) || globalIndex >= visibleEnd(total)) {
      return null;
    }
    return leading + (globalIndex - visibleStart(total));
  }

  double _extentOf(int from, int to) {
    if (to <= from) return 0;
    final known = _heights.values;
    final avg = known.isEmpty
        ? _fallbackItemExtent
        : known.reduce((a, b) => a + b) / known.length;
    var sum = 0.0;
    for (var i = from; i < to; i++) {
      sum += _heights[i] ?? avg;
    }
    return sum;
  }

  double _headerExtent(int s) => s > 0 ? earlierButtonExtent : 0;

  /// Appends the next page; trims the oldest items above if over [maxWindow].
  void loadMore(
    BuildContext context,
    int total,
    void Function(VoidCallback fn) setState,
  ) {
    HapticFeedback.selectionClick();
    final newEnd = math.min(total, end + pageSize);
    var newStart = start;
    if (newEnd - newStart > maxWindow) newStart = newEnd - maxWindow;

    // Content removed above the viewport (minus the header that may appear).
    final shift = _extentOf(start, newStart) -
        (_headerExtent(newStart) - _headerExtent(start));
    final position = Scrollable.maybeOf(context)?.position;
    if (shift != 0 && position != null && position.hasPixels) {
      position.jumpTo(math.max(0, position.pixels - shift));
    }
    setState(() {
      start = newStart;
      end = newEnd;
    });
  }

  /// Restores the previous page above; trims the bottom if over [maxWindow].
  void loadEarlier(
    BuildContext context,
    void Function(VoidCallback fn) setState,
  ) {
    HapticFeedback.selectionClick();
    final newStart = math.max(0, start - pageSize);
    var newEnd = end;
    if (newEnd - newStart > maxWindow) newEnd = newStart + maxWindow;

    final shift = _extentOf(newStart, start) +
        (_headerExtent(newStart) - _headerExtent(start));
    final position = Scrollable.maybeOf(context)?.position;
    if (shift != 0 && position != null && position.hasPixels) {
      position.jumpTo(math.max(0, position.pixels + shift));
    }
    setState(() {
      start = newStart;
      end = newEnd;
    });
  }
}

class _MeasureHeight extends SingleChildRenderObjectWidget {
  const _MeasureHeight({super.key, required this.onHeight, super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureHeight(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasureHeight renderObject,
  ) {
    renderObject.onHeight = onHeight;
  }
}

class _RenderMeasureHeight extends RenderProxyBox {
  _RenderMeasureHeight(this.onHeight);

  ValueChanged<double> onHeight;

  @override
  void performLayout() {
    super.performLayout();
    onHeight(size.height);
  }
}

/// Fixed-height "Show earlier (N hidden)" header shown when items were
/// trimmed from the top of the window.
class PagerShowEarlierButton extends StatelessWidget {
  const PagerShowEarlierButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final void Function(BuildContext context) onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: WindowedPager.earlierButtonExtent,
      child: Align(
        alignment: Alignment.topCenter,
        child: _PagerPill(
          icon: Icons.keyboard_arrow_up_rounded,
          label: label,
          onTap: () => onTap(context),
          emphasized: false,
        ),
      ),
    );
  }
}

/// Footer shown below a windowed list: "Load more" when items remain,
/// otherwise a subtle end-of-list marker. Always shows the visible range.
class PagerFooter extends StatelessWidget {
  const PagerFooter({
    super.key,
    required this.hasMore,
    required this.loadMoreLabel,
    required this.rangeLabel,
    required this.endLabel,
    required this.onLoadMore,
  });

  final bool hasMore;
  final String loadMoreLabel;
  final String rangeLabel;
  final String endLabel;
  final void Function(BuildContext context) onLoadMore;

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.65);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Column(
        children: [
          if (hasMore)
            _PagerPill(
              icon: Icons.expand_more_rounded,
              label: loadMoreLabel,
              onTap: () => onLoadMore(context),
              emphasized: true,
            ),
          const SizedBox(height: 8),
          Text(
            hasMore ? rangeLabel : '$rangeLabel • $endLabel',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _PagerPill extends StatelessWidget {
  const _PagerPill({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.emphasized,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return AnimatedScaleTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: emphasized
              ? LinearGradient(
                  colors: [
                    primary.withValues(alpha: 0.22),
                    SyncroColors.amethystViolet.withValues(alpha: 0.18),
                  ],
                )
              : null,
          color: emphasized ? null : primary.withValues(alpha: 0.08),
          border: Border.all(color: primary.withValues(alpha: 0.38)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
