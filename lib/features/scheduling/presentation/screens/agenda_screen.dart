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
import '../widgets/confirmation_sheet.dart';

/// Tab 1: Redesigned Glassmorphic Agenda & Interactive Timeline View.
class AgendaScreen extends ConsumerStatefulWidget {
  const AgendaScreen({super.key});

  @override
  ConsumerState<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends ConsumerState<AgendaScreen> {
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

    final filtered = _selectedDateFilter == null
        ? filteredByType
        : filteredByType.where((apt) {
            final s = apt.timeRange.start;
            return s.year == _selectedDateFilter!.year &&
                s.month == _selectedDateFilter!.month &&
                s.day == _selectedDateFilter!.day;
          }).toList();

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

                // 2. Category Filter Strip
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

                // 3. Interactive Horizontal Date Scroller Ribbon
                if (distinctDates.isNotEmpty)
                  SizedBox(
                    height: 66,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: distinctDates.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, idx) {
                        if (idx == 0) {
                          final isAllSelected = _selectedDateFilter == null;
                          return _DateRibbonChip(
                            topText: strings.isPt ? 'VER' : 'VIEW',
                            middleText: strings.isPt ? 'Tudo' : 'All',
                            bottomText: '${filteredByType.length}',
                            isSelected: isAllSelected,
                            dotColors: const [
                              SyncroColors.electricIndigo,
                              SyncroColors.clinicalEmerald,
                            ],
                            onTap: () =>
                                _applyFilter(() => _selectedDateFilter = null),
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
                            _selectedDateFilter = isSelected ? null : date;
                          }),
                        );
                      },
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
                child: Text(
                  strings.noAppointmentsFound,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
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
      onTap: () => ConfirmationSheet.show(
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

    if (isSuggested) {
      cardContent = Dismissible(
        key: ValueKey('swipe_${appointment.id}'),
        direction: DismissDirection.startToEnd,
        confirmDismiss: (_) async {
          onConfirm();
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
        child: cardContent,
      );
    }

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
