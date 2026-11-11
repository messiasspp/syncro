import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/syncro_theme.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/windowed_pager.dart';
import '../../domain/models/appointment.dart';
import '../../domain/models/entity.dart';
import '../../domain/models/event_type.dart';
import '../providers/scheduling_providers.dart';
import '../widgets/appointment_detail_sheet.dart';
import '../widgets/confirmation_sheet.dart';

enum AgendaViewMode {
  timeline,
  month,
  week,
}

/// Tab 1: Redesigned Glassmorphic Agenda & Interactive Timeline View.
class AgendaScreen extends ConsumerStatefulWidget {
  const AgendaScreen({super.key});

  @override
  ConsumerState<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends ConsumerState<AgendaScreen> {
  AgendaViewMode _viewMode = AgendaViewMode.timeline;
  DateTime _focusedDate = DateTime(2026, 10, 19);
  String? _selectedEventTypeId;
  DateTime? _selectedDateFilter;

  /// Windowed lazy loading over day groups: 7 days per page, at most 21
  /// days mounted at once (older days are trimmed from the top).
  final WindowedPager _pager = WindowedPager(pageSize: 7, maxWindow: 21);

  @override
  void initState() {
    super.initState();
    _pager.attach(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pager.detach();
    super.dispose();
  }

  DateTime _startOfWeek(DateTime date) {
    return DateTime(date.year, date.month, date.day)
        .subtract(Duration(days: date.weekday - 1));
  }

  DateTime _endOfWeek(DateTime date) {
    return _startOfWeek(date).add(
      const Duration(days: 6, hours: 23, minutes: 59, seconds: 59),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Applies a filter change and restarts the window from the first page.
  void _applyFilter(VoidCallback change) {
    setState(() {
      change();
      _pager.reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final eventTypesAsync = ref.watch(eventTypesStreamProvider);
    final entitiesAsync = ref.watch(entitiesStreamProvider);
    final appointmentsAsync = ref.watch(appointmentsStreamProvider);

    final eventTypes = eventTypesAsync.valueOrNull ?? const <EventType>[];
    final entities = entitiesAsync.valueOrNull ?? const <Entity>[];
    final allAppointments =
        appointmentsAsync.valueOrNull ?? const <Appointment>[];

    final eventTypeById = {for (final et in eventTypes) et.id: et};
    final entityById = {for (final e in entities) e.id: e};

    final filteredByType = _selectedEventTypeId == null
        ? allAppointments
        : allAppointments
            .where((a) => a.eventTypeId == _selectedEventTypeId)
            .toList();

    // Distinct calendar dates for the interactive horizontal date ribbon,
    // with up to 3 category dot colors per date precomputed in one pass.
    final distinctDates = <DateTime>[];
    final dotSetsByDate = <DateTime, Set<Color>>{};
    for (final apt in filteredByType) {
      final d = DateTime(
        apt.timeRange.start.year,
        apt.timeRange.start.month,
        apt.timeRange.start.day,
      );
      final dots = dotSetsByDate.putIfAbsent(d, () {
        distinctDates.add(d);
        return <Color>{};
      });
      if (dots.length < 3) {
        dots.add(
          parseHexColor(eventTypeById[apt.eventTypeId]?.colorHex ?? '#6366F1'),
        );
      }
    }
    final dotsByDate = {
      for (final e in dotSetsByDate.entries) e.key: e.value.toList(),
    };

    final filtered = switch (_viewMode) {
      AgendaViewMode.timeline => _selectedDateFilter == null
          ? filteredByType
          : filteredByType
              .where((apt) =>
                  _isSameDay(apt.timeRange.start, _selectedDateFilter!))
              .toList(),
      AgendaViewMode.month => _selectedDateFilter != null
          ? filteredByType
              .where((apt) =>
                  _isSameDay(apt.timeRange.start, _selectedDateFilter!))
              .toList()
          : filteredByType.where((apt) {
              final s = apt.timeRange.start;
              return s.year == _focusedDate.year &&
                  s.month == _focusedDate.month;
            }).toList(),
      AgendaViewMode.week => _selectedDateFilter != null
          ? filteredByType
              .where((apt) =>
                  _isSameDay(apt.timeRange.start, _selectedDateFilter!))
              .toList()
          : filteredByType.where((apt) {
              final s = apt.timeRange.start;
              final start = _startOfWeek(_focusedDate);
              final end = _endOfWeek(_focusedDate);
              return !s.isBefore(start) && !s.isAfter(end);
            }).toList(),
    };

    final confirmedCount = allAppointments
        .where((a) => a.status == AppointmentStatus.confirmed)
        .length;
    final suggestedCount = allAppointments
        .where((a) => a.status == AppointmentStatus.suggested)
        .length;

    // Group filtered appointments by date header
    final grouped = <DateTime, List<Appointment>>{};
    for (final apt in filtered) {
      final dayKey = DateTime(
        apt.timeRange.start.year,
        apt.timeRange.start.month,
        apt.timeRange.start.day,
      );
      grouped.putIfAbsent(dayKey, () => []).add(apt);
    }
    final sortedDays = grouped.keys.toList()..sort();

    // Windowed slice of day groups currently mounted.
    final totalDays = sortedDays.length;
    final windowStart = _pager.visibleStart(totalDays);
    final windowEnd = _pager.visibleEnd(totalDays);
    final windowCount = windowEnd - windowStart;
    final hasEarlier = _pager.hasEarlier && windowStart > 0;
    final leading = hasEarlier ? 1 : 0;

    final topPadding = MediaQuery.of(context).padding.top + kToolbarHeight + 12;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, topPadding, 16, 8),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Bento Summary Metric Row
                Row(
                  children: [
                    Expanded(
                      child: _BentoStatCard(
                        label: strings.totalAppointmentsLabel,
                        count: allAppointments.length,
                        total: allAppointments.isEmpty
                            ? 1
                            : allAppointments.length,
                        icon: Icons.calendar_month_rounded,
                        accentColor: SyncroColors.electricIndigo,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _BentoStatCard(
                        label: strings.confirmedLabel,
                        count: confirmedCount,
                        total: allAppointments.isEmpty
                            ? 1
                            : allAppointments.length,
                        icon: Icons.verified_rounded,
                        accentColor: SyncroColors.clinicalEmerald,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _BentoStatCard(
                        label: strings.suggestedLabel,
                        count: suggestedCount,
                        total: allAppointments.isEmpty
                            ? 1
                            : allAppointments.length,
                        icon: Icons.auto_awesome_rounded,
                        accentColor: SyncroColors.amberSuggested,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 2. View Mode Selector (Timeline, Month Grid, Week Matrix)
                _ViewModeSegmentedSelector(
                  currentMode: _viewMode,
                  onModeChanged: (mode) => _applyFilter(() {
                    _viewMode = mode;
                    _selectedDateFilter = null;
                  }),
                  strings: strings,
                ),
                const SizedBox(height: 12),

                // 3. Category Filter Strip
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      _CategoryGlassPill(
                        label: strings.allFilter,
                        isSelected: _selectedEventTypeId == null,
                        dotColor: SyncroColors.electricIndigo,
                        onTap: () => _applyFilter(() {
                          _selectedEventTypeId = null;
                          _selectedDateFilter = null;
                        }),
                      ),
                      for (final et in eventTypes) ...[
                        const SizedBox(width: 8),
                        _CategoryGlassPill(
                          label: et.name,
                          isSelected: _selectedEventTypeId == et.id,
                          dotColor: parseHexColor(et.colorHex),
                          onTap: () => _applyFilter(() {
                            _selectedEventTypeId =
                                _selectedEventTypeId == et.id ? null : et.id;
                            _selectedDateFilter = null;
                          }),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 4. Interactive Presentation: Timeline Ribbon, Month Matrix, or Week Matrix
                switch (_viewMode) {
                  AgendaViewMode.timeline => distinctDates.isNotEmpty
                      ? SizedBox(
                          height: 66,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            itemCount: distinctDates.length + 1,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, idx) {
                              if (idx == 0) {
                                final isAllSelected =
                                    _selectedDateFilter == null;
                                return _DateRibbonChip(
                                  topText: strings.isPt ? 'VER' : 'VIEW',
                                  middleText: strings.isPt ? 'Tudo' : 'All',
                                  bottomText: '${filteredByType.length}',
                                  isSelected: isAllSelected,
                                  dotColors: const [
                                    SyncroColors.electricIndigo,
                                    SyncroColors.clinicalEmerald,
                                  ],
                                  onTap: () => _applyFilter(
                                      () => _selectedDateFilter = null),
                                );
                              }
                              final date = distinctDates[idx - 1];
                              final isSelected = _selectedDateFilter != null &&
                                  _selectedDateFilter!.year == date.year &&
                                  _selectedDateFilter!.month == date.month &&
                                  _selectedDateFilter!.day == date.day;
                              final dots = dotsByDate[date] ?? const <Color>[];

                              return _DateRibbonChip(
                                topText: strings
                                    .weekdayName(date.weekday, short: true)
                                    .toUpperCase(),
                                middleText: '${date.day}',
                                bottomText: DateFormat('MMM').format(date),
                                isSelected: isSelected,
                                dotColors: dots,
                                onTap: () => _applyFilter(() {
                                  _selectedDateFilter =
                                      isSelected ? null : date;
                                }),
                              );
                            },
                          ),
                        )
                      : const SizedBox.shrink(),
                  AgendaViewMode.month => _GlassMonthCalendarMatrix(
                      focusedMonth: _focusedDate,
                      selectedDate: _selectedDateFilter,
                      dotsByDate: dotsByDate,
                      strings: strings,
                      onDateSelected: (date) {
                        _applyFilter(() {
                          if (_selectedDateFilter != null &&
                              _isSameDay(_selectedDateFilter!, date)) {
                            _selectedDateFilter = null;
                          } else {
                            _selectedDateFilter = date;
                          }
                        });
                      },
                      onMonthChanged: (newMonth) {
                        _applyFilter(() {
                          _focusedDate = newMonth;
                          _selectedDateFilter = null;
                        });
                      },
                      onTodayTap: () {
                        _applyFilter(() {
                          _focusedDate = DateTime(2026, 10, 19);
                          _selectedDateFilter = DateTime(2026, 10, 19);
                        });
                      },
                    ),
                  AgendaViewMode.week => _GlassWeekMatrix(
                      focusedDate: _focusedDate,
                      selectedDate: _selectedDateFilter,
                      dotsByDate: dotsByDate,
                      appointments: filteredByType,
                      strings: strings,
                      onDateSelected: (date) {
                        _applyFilter(() {
                          if (_selectedDateFilter != null &&
                              _isSameDay(_selectedDateFilter!, date)) {
                            _selectedDateFilter = null;
                          } else {
                            _selectedDateFilter = date;
                          }
                        });
                      },
                      onWeekChanged: (newDate) {
                        _applyFilter(() {
                          _focusedDate = newDate;
                          _selectedDateFilter = null;
                        });
                      },
                      onCurrentWeekTap: () {
                        _applyFilter(() {
                          _focusedDate = DateTime(2026, 10, 19);
                          _selectedDateFilter = DateTime(2026, 10, 19);
                        });
                      },
                    ),
                },

                // Active Day Filter Chip (when a specific day is clicked)
                if (_selectedDateFilter != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5.5,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.event_available_rounded,
                                size: 14,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                strings
                                    .formatDateHeader(_selectedDateFilter!),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color:
                                      Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => _applyFilter(
                                    () => _selectedDateFilter = null),
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.2),
                                  ),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 13,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),

        // 4. Connected Timeline Spine & Appointment Cards
        if (sortedDays.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _selectedDateFilter != null
                          ? Icons.event_available_rounded
                          : Icons.event_busy_rounded,
                      size: 46,
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _selectedDateFilter != null
                          ? strings.noAppointmentsForSelectedDay
                          : strings.noAppointmentsFound,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (_selectedDateFilter != null) ...[
                      const SizedBox(height: 14),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: Text(strings.clearFilter),
                        onPressed: () =>
                            _applyFilter(() => _selectedDateFilter = null),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  // [Show earlier] • windowed day groups • [Load more footer]
                  if (hasEarlier && index == 0) {
                    return PagerShowEarlierButton(
                      label: strings.showEarlierLabel(windowStart),
                      onTap: (ctx) => _pager.loadEarlier(ctx, setState),
                    );
                  }
                  final local = index - leading;
                  if (local == windowCount) {
                    return PagerFooter(
                      hasMore: _pager.hasMore(totalDays),
                      loadMoreLabel:
                          strings.loadMoreLabel(_pager.remaining(totalDays)),
                      rangeLabel: strings.windowRangeLabel(
                        windowStart + 1,
                        windowEnd,
                        totalDays,
                      ),
                      endLabel: strings.endOfListLabel,
                      onLoadMore: (ctx) =>
                          _pager.loadMore(ctx, totalDays, setState),
                    );
                  }
                  final globalIndex = windowStart + local;
                  final day = sortedDays[globalIndex];
                  final dayAppointments = grouped[day]!;
                  return _pager.measure(
                    globalIndex,
                    StaggeredReveal(
                      index: globalIndex % _pager.pageSize,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.5),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  strings.formatDateHeader(day),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.2,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            for (int i = 0; i < dayAppointments.length; i++)
                              _TimelineAppointmentRow(
                                appointment: dayAppointments[i],
                                entity: entityById[dayAppointments[i].entityId],
                                eventType: eventTypeById[
                                    dayAppointments[i].eventTypeId],
                                strings: strings,
                                isLastInDay: i == dayAppointments.length - 1,
                                onConfirm: () async {
                                  HapticFeedback.mediumImpact();
                                  final confirmed = dayAppointments[i].copyWith(
                                    status: AppointmentStatus.confirmed,
                                  );
                                  await ref
                                      .read(schedulingRepositoryProvider)
                                      .upsertAppointment(confirmed);
                                  await ref
                                      .read(calendarSyncServiceProvider)
                                      .pushAppointmentToCalendar(confirmed);
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                childCount: leading + windowCount + 1,
                findChildIndexCallback: (key) => _pager.findChildIndex(
                  key,
                  leading: leading,
                  total: totalDays,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BentoStatCard extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  final IconData icon;
  final Color accentColor;

  const _BentoStatCard({
    required this.label,
    required this.count,
    required this.total,
    required this.icon,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = (count / total).clamp(0.0, 1.0);
    return GlassContainer(
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      borderColor: accentColor.withValues(alpha: 0.28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 15, color: accentColor),
              ),
              const Spacer(),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: count.toDouble()),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                builder: (context, val, _) {
                  return Text(
                    '${val.round()}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: accentColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 3.5,
              color: accentColor,
              backgroundColor: accentColor.withValues(alpha: 0.14),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryGlassPill extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color dotColor;
  final VoidCallback onTap;

  const _CategoryGlassPill({
    required this.label,
    required this.isSelected,
    required this.dotColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedScaleTap(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: isSelected
              ? dotColor.withValues(alpha: isDark ? 0.26 : 0.16)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.white.withValues(alpha: 0.75)),
          border: Border.all(
            color: isSelected
                ? dotColor.withValues(alpha: 0.75)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.08)),
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateRibbonChip extends StatelessWidget {
  final String topText;
  final String middleText;
  final String bottomText;
  final bool isSelected;
  final List<Color> dotColors;
  final VoidCallback onTap;

  const _DateRibbonChip({
    required this.topText,
    required this.middleText,
    required this.bottomText,
    required this.isSelected,
    required this.dotColors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return AnimatedScaleTap(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 58,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: isSelected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    primary,
                    SyncroColors.amethystViolet,
                  ],
                )
              : null,
          color: isSelected
              ? null
              : (isDark
                  ? SyncroColors.darkSurface.withValues(alpha: 0.72)
                  : Colors.white.withValues(alpha: 0.80)),
          border: Border.all(
            color: isSelected
                ? Colors.white.withValues(alpha: 0.35)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.black.withValues(alpha: 0.06)),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              topText,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.85)
                    : Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              middleText,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: isSelected ? Colors.white : null,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final c in dotColors)
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? Colors.white : c,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineAppointmentRow extends StatelessWidget {
  final Appointment appointment;
  final Entity? entity;
  final EventType? eventType;
  final AppStrings strings;
  final bool isLastInDay;
  final VoidCallback onConfirm;

  const _TimelineAppointmentRow({
    required this.appointment,
    required this.entity,
    required this.eventType,
    required this.strings,
    required this.isLastInDay,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final categoryColor = parseHexColor(eventType?.colorHex ?? '#6366F1');
    final isSuggested = appointment.status == AppointmentStatus.suggested;
    final participantName = entity?.name ?? appointment.entityId;
    final categoryName = eventType?.name ?? appointment.eventTypeId;
    final visitNum =
        appointment.visitIndex != null ? appointment.visitIndex! + 1 : null;

    Widget cardContent = GlassContainer(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      borderRadius: 18,
      borderColor: categoryColor.withValues(alpha: isSuggested ? 0.50 : 0.30),
      onTap: () => AppointmentDetailSheet.show(
        context,
        appointment: appointment,
        entity: entity,
        eventType: eventType,
        strings: strings,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4.5,
            height: 54,
            decoration: BoxDecoration(
              color: categoryColor,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: categoryColor.withValues(alpha: 0.55),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        participantName,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                    ),
                    if (visitNum != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: categoryColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: categoryColor.withValues(alpha: 0.40),
                          ),
                        ),
                        child: Text(
                          strings.isPt
                              ? 'Visita #$visitNum'
                              : 'Visit #$visitNum',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: categoryColor,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$categoryName • ${strings.formatTimeRange(appointment.timeRange)} '
                  '(${appointment.timeRange.duration.inMinutes}m)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _StatusBadge(
                      status: appointment.status,
                      strings: strings,
                    ),
                    if (appointment.externalCalendarEventId != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.cloud_done_rounded,
                            size: 13,
                            color: SyncroColors.clinicalEmerald,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            strings.syncedBadge,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: SyncroColors.clinicalEmerald,
                            ),
                          ),
                        ],
                      ),
                    if (isSuggested)
                      Text(
                        strings.swipeToConfirmHint,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontStyle: FontStyle.italic,
                          color: SyncroColors.amberSuggested,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Column(
            children: [
              if (isSuggested)
                IconButton.filledTonal(
                  tooltip: strings.confirmAction,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  onPressed: onConfirm,
                ),
              IconButton(
                tooltip: strings.editAppointmentAction,
                icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                onPressed: () => AppointmentDetailSheet.show(
                  context,
                  appointment: appointment,
                  entity: entity,
                  eventType: eventType,
                  strings: strings,
                ),
              ),
              IconButton(
                tooltip: strings.shareAction,
                icon: const Icon(Icons.share_outlined, size: 18),
                onPressed: () => ConfirmationSheet.show(
                  context,
                  appointment: appointment,
                  entity: entity,
                  eventType: eventType,
                  strings: strings,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    // Interactive Dual-Direction Swipe:
    // Swipe Right -> Confirm / Mark Done
    // Swipe Left -> Edit & Reschedule
    cardContent = Dismissible(
      key: ValueKey('swipe_${appointment.id}'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          HapticFeedback.mediumImpact();
          onConfirm();
        } else if (direction == DismissDirection.endToStart) {
          HapticFeedback.mediumImpact();
          AppointmentDetailSheet.show(
            context,
            appointment: appointment,
            entity: entity,
            eventType: eventType,
            strings: strings,
          );
        }
        return false;
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: [
              SyncroColors.clinicalEmerald.withValues(alpha: 0.85),
              SyncroColors.electricIndigo.withValues(alpha: 0.65),
            ],
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified_rounded, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              strings.confirmAction,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: [
              SyncroColors.amethystViolet.withValues(alpha: 0.70),
              SyncroColors.electricIndigo.withValues(alpha: 0.85),
            ],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              strings.editAppointmentAction,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.edit_calendar_rounded, color: Colors.white),
          ],
        ),
      ),
      child: cardContent,
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left timeline spine column
          SizedBox(
            width: 50,
            child: Column(
              children: [
                const SizedBox(height: 14),
                Text(
                  strings.formatTime(appointment.timeRange.start),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: isLastInDay
                      ? const SizedBox.shrink()
                      : Container(
                          width: 1.5,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                categoryColor.withValues(alpha: 0.55),
                                categoryColor.withValues(alpha: 0.10),
                              ],
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(child: cardContent),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final AppointmentStatus status;
  final AppStrings strings;

  const _StatusBadge({
    required this.status,
    required this.strings,
  });

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      AppointmentStatus.confirmed => (
          strings.confirmedLabel,
          SyncroColors.clinicalEmerald
        ),
      AppointmentStatus.suggested => (
          strings.suggestedLabel,
          SyncroColors.amberSuggested
        ),
      AppointmentStatus.completed => (strings.completedLabel, Colors.blue),
      AppointmentStatus.cancelled => (
          strings.cancelledLabel,
          SyncroColors.coralAlert
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

/// Glassmorphic 3-way view switcher (Timeline, Month Grid, Week Matrix)
class _ViewModeSegmentedSelector extends StatelessWidget {
  final AgendaViewMode currentMode;
  final ValueChanged<AgendaViewMode> onModeChanged;
  final AppStrings strings;

  const _ViewModeSegmentedSelector({
    required this.currentMode,
    required this.onModeChanged,
    required this.strings,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      borderRadius: 22,
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _ViewSegmentItem(
              icon: Icons.view_timeline_rounded,
              label: strings.viewTimeline,
              isSelected: currentMode == AgendaViewMode.timeline,
              onTap: () => onModeChanged(AgendaViewMode.timeline),
            ),
          ),
          Expanded(
            child: _ViewSegmentItem(
              icon: Icons.calendar_view_month_rounded,
              label: strings.viewMonth,
              isSelected: currentMode == AgendaViewMode.month,
              onTap: () => onModeChanged(AgendaViewMode.month),
            ),
          ),
          Expanded(
            child: _ViewSegmentItem(
              icon: Icons.view_week_rounded,
              label: strings.viewWeek,
              isSelected: currentMode == AgendaViewMode.week,
              onTap: () => onModeChanged(AgendaViewMode.week),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewSegmentItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ViewSegmentItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: isSelected
              ? LinearGradient(
                  colors: [
                    primary,
                    SyncroColors.amethystViolet,
                  ],
                )
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? Colors.white : null,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? Colors.white : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Interactive Glassmorphic Month Grid with Category Indicator Micro-Dots
class _GlassMonthCalendarMatrix extends StatelessWidget {
  final DateTime focusedMonth;
  final DateTime? selectedDate;
  final Map<DateTime, List<Color>> dotsByDate;
  final AppStrings strings;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<DateTime> onMonthChanged;
  final VoidCallback onTodayTap;

  const _GlassMonthCalendarMatrix({
    required this.focusedMonth,
    required this.selectedDate,
    required this.dotsByDate,
    required this.strings,
    required this.onDateSelected,
    required this.onMonthChanged,
    required this.onTodayTap,
  });

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final now = DateTime.now();

    final firstOfMonth = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final offsetDays = (firstOfMonth.weekday - 1) % 7;
    final calendarStart = firstOfMonth.subtract(Duration(days: offsetDays));
    final allDays =
        List.generate(42, (i) => calendarStart.add(Duration(days: i)));

    final weekdayLabels = [
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
      DateTime.saturday,
      DateTime.sunday,
    ].map((w) => strings.weekdayName(w, short: true).toUpperCase()).toList();

    return GlassContainer(
      borderRadius: 24,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        children: [
          // Month Header Bar
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_left_rounded, size: 22),
                onPressed: () => onMonthChanged(
                  DateTime(focusedMonth.year, focusedMonth.month - 1, 1),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '${strings.monthName(focusedMonth.month)} ${focusedMonth.year}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_right_rounded, size: 22),
                onPressed: () => onMonthChanged(
                  DateTime(focusedMonth.year, focusedMonth.month + 1, 1),
                ),
              ),
              const Spacer(),
              AnimatedScaleTap(
                onTap: onTodayTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4.5,
                  ),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: primary.withValues(alpha: 0.32),
                    ),
                  ),
                  child: Text(
                    strings.todayButton,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Weekday Labels Row
          Row(
            children: [
              for (final label in weekdayLabels)
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.color
                            ?.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // 6 x 7 Calendar Grid
          Column(
            children: [
              for (int row = 0; row < 6; row++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      for (int col = 0; col < 7; col++) ...[
                        Builder(
                          builder: (context) {
                            final cellDate = allDays[row * 7 + col];
                            final isCurrentMonth =
                                cellDate.month == focusedMonth.month;
                            final isSelected = selectedDate != null &&
                                _isSameDay(selectedDate!, cellDate);
                            final isToday = _isSameDay(now, cellDate);

                            final normKey = DateTime(
                              cellDate.year,
                              cellDate.month,
                              cellDate.day,
                            );
                            final dots = dotsByDate[normKey] ?? const <Color>[];

                            return Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  onDateSelected(cellDate);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 1.5,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4.5,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(11),
                                    gradient: isSelected
                                        ? LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              primary,
                                              SyncroColors.amethystViolet,
                                            ],
                                          )
                                        : null,
                                    border: isToday && !isSelected
                                        ? Border.all(
                                            color:
                                                SyncroColors.clinicalEmerald,
                                            width: 1.4,
                                          )
                                        : null,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${cellDate.day}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isSelected || isToday
                                              ? FontWeight.w900
                                              : FontWeight.w600,
                                          color: isSelected
                                              ? Colors.white
                                              : (isCurrentMonth
                                                  ? null
                                                  : Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.color
                                                      ?.withValues(
                                                        alpha: 0.28,
                                                      )),
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      SizedBox(
                                        height: 4,
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            for (final dot in dots.take(3))
                                              Container(
                                                width: 3.5,
                                                height: 3.5,
                                                margin:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 0.8,
                                                ),
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: isSelected
                                                      ? Colors.white
                                                      : dot,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Interactive Glassmorphic Week Matrix View (7 Responsive Columns with Event Breakdown)
class _GlassWeekMatrix extends StatelessWidget {
  final DateTime focusedDate;
  final DateTime? selectedDate;
  final Map<DateTime, List<Color>> dotsByDate;
  final List<Appointment> appointments;
  final AppStrings strings;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<DateTime> onWeekChanged;
  final VoidCallback onCurrentWeekTap;

  const _GlassWeekMatrix({
    required this.focusedDate,
    required this.selectedDate,
    required this.dotsByDate,
    required this.appointments,
    required this.strings,
    required this.onDateSelected,
    required this.onWeekChanged,
    required this.onCurrentWeekTap,
  });

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _startOfWeek(DateTime date) {
    return DateTime(date.year, date.month, date.day)
        .subtract(Duration(days: date.weekday - 1));
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final now = DateTime.now();

    final weekStart = _startOfWeek(focusedDate);
    final weekEnd = weekStart.add(const Duration(days: 6));
    final weekDays = List.generate(7, (i) => weekStart.add(Duration(days: i)));

    final rangeText =
        '${DateFormat("d MMM").format(weekStart)} – ${DateFormat("d MMM yyyy").format(weekEnd)}';

    return GlassContainer(
      borderRadius: 24,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        children: [
          // Week Header Bar
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_left_rounded, size: 22),
                onPressed: () => onWeekChanged(
                  focusedDate.subtract(const Duration(days: 7)),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                rangeText,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_right_rounded, size: 22),
                onPressed: () => onWeekChanged(
                  focusedDate.add(const Duration(days: 7)),
                ),
              ),
              const Spacer(),
              AnimatedScaleTap(
                onTap: onCurrentWeekTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4.5,
                  ),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: primary.withValues(alpha: 0.32),
                    ),
                  ),
                  child: Text(
                    strings.todayButton,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 7 Interactive Day Cards Row
          Row(
            children: [
              for (final day in weekDays)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final isSelected = selectedDate != null &&
                          _isSameDay(selectedDate!, day);
                      final isToday = _isSameDay(now, day);
                      final normKey = DateTime(day.year, day.month, day.day);
                      final dots = dotsByDate[normKey] ?? const <Color>[];

                      final dayAptsCount = appointments
                          .where((a) => _isSameDay(a.timeRange.start, day))
                          .length;

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onDateSelected(day);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 2,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: isSelected
                                ? LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      primary,
                                      SyncroColors.amethystViolet,
                                    ],
                                  )
                                : null,
                            color: isSelected
                                ? null
                                : (Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? SyncroColors.darkSurface
                                        .withValues(alpha: 0.5)
                                    : Colors.white.withValues(alpha: 0.6)),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.5)
                                  : (isToday
                                      ? SyncroColors.clinicalEmerald
                                      : Colors.white.withValues(alpha: 0.08)),
                              width: isToday && !isSelected ? 1.4 : 1.0,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                strings
                                    .weekdayName(day.weekday, short: true)
                                    .toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: isSelected
                                      ? Colors.white.withValues(alpha: 0.85)
                                      : Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.color
                                          ?.withValues(alpha: 0.6),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${day.day}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: isSelected ? Colors.white : null,
                                ),
                              ),
                              const SizedBox(height: 5),
                              if (dayAptsCount > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.white.withValues(alpha: 0.22)
                                        : primary.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$dayAptsCount',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w900,
                                      color: isSelected
                                          ? Colors.white
                                          : primary,
                                    ),
                                  ),
                                )
                              else
                                const SizedBox(height: 15),
                              const SizedBox(height: 4),
                              SizedBox(
                                height: 3.5,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    for (final dot in dots.take(3))
                                      Container(
                                        width: 3.5,
                                        height: 3.5,
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 0.6,
                                        ),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isSelected
                                              ? Colors.white
                                              : dot,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
