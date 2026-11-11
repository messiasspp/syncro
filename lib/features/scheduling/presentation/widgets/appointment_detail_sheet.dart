import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/syncro_theme.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../domain/models/appointment.dart';
import '../../domain/models/entity.dart';
import '../../domain/models/event_type.dart';
import '../../domain/models/time_range.dart';
import '../providers/scheduling_providers.dart';
import 'confirmation_sheet.dart';

/// Interactive frosted glassmorphic bottom sheet for editing appointment details,
/// picking new date/time windows, changing status, and 1-tap re-syncing with
/// native device calendars.
class AppointmentDetailSheet extends ConsumerStatefulWidget {
  final Appointment appointment;
  final Entity? entity;
  final EventType? eventType;
  final AppStrings strings;

  const AppointmentDetailSheet({
    super.key,
    required this.appointment,
    required this.entity,
    required this.eventType,
    required this.strings,
  });

  static Future<void> show(
    BuildContext context, {
    required Appointment appointment,
    required Entity? entity,
    required EventType? eventType,
    required AppStrings strings,
  }) {
    HapticFeedback.mediumImpact();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AppointmentDetailSheet(
        appointment: appointment,
        entity: entity,
        eventType: eventType,
        strings: strings,
      ),
    );
  }

  @override
  ConsumerState<AppointmentDetailSheet> createState() =>
      _AppointmentDetailSheetState();
}

class _AppointmentDetailSheetState
    extends ConsumerState<AppointmentDetailSheet> {
  late DateTime _selectedDate;
  late TimeOfDay _startTime;
  late int _durationMinutes;
  late AppointmentStatus _status;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final start = widget.appointment.timeRange.start;
    _selectedDate = DateTime(start.year, start.month, start.day);
    _startTime = TimeOfDay(hour: start.hour, minute: start.minute);
    _durationMinutes = widget.appointment.timeRange.duration.inMinutes;
    _status = widget.appointment.status;
  }

  TimeRange _buildComputedTimeRange() {
    final startDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _startTime.hour,
      _startTime.minute,
    );
    final endDateTime =
        startDateTime.add(Duration(minutes: _durationMinutes));
    return TimeRange(start: startDateTime, end: endDateTime);
  }

  Future<void> _pickDate() async {
    HapticFeedback.selectionClick();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2025, 1, 1),
      lastDate: DateTime(2030, 12, 31),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickStartTime() async {
    HapticFeedback.selectionClick();
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked != null) {
      setState(() => _startTime = picked);
    }
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    final newRange = _buildComputedTimeRange();
    final updated = widget.appointment.copyWith(
      timeRange: newRange,
      status: _status,
    );

    try {
      await ref.read(schedulingRepositoryProvider).upsertAppointment(updated);

      if (_status != AppointmentStatus.cancelled) {
        await ref
            .read(calendarSyncServiceProvider)
            .pushAppointmentToCalendar(updated);
      } else {
        await ref
            .read(calendarSyncServiceProvider)
            .deleteAppointmentFromCalendar(widget.appointment);
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.strings.rescheduleSuccess),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _confirmDelete() async {
    HapticFeedback.heavyImpact();
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.strings.confirmDeleteTitle),
        content: Text(widget.strings.confirmDeleteMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(widget.strings.cancelAction),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: SyncroColors.coralAlert,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(widget.strings.deleteAction),
          ),
        ],
      ),
    );

    if (shouldDelete == true && mounted) {
      Navigator.of(context).pop();
      await ref
          .read(calendarSyncServiceProvider)
          .deleteAppointmentFromCalendar(widget.appointment);
      await ref
          .read(schedulingRepositoryProvider)
          .deleteAppointment(widget.appointment.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.strings.deleteSuccess),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final categoryColor = parseHexColor(
      widget.eventType?.colorHex ?? '#6366F1',
    );
    final participantName = widget.entity?.name ?? widget.appointment.entityId;
    final categoryName =
        widget.eventType?.name ?? widget.appointment.eventTypeId;
    final visitNum = widget.appointment.visitIndex != null
        ? widget.appointment.visitIndex! + 1
        : null;

    final computedRange = _buildComputedTimeRange();

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      maxChildSize: 0.94,
      minChildSize: 0.50,
      expand: false,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              decoration: BoxDecoration(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                color: isDark
                    ? SyncroColors.darkSurface.withValues(alpha: 0.94)
                    : Colors.white.withValues(alpha: 0.96),
                border: Border(
                  top: BorderSide(
                    color: categoryColor.withValues(alpha: 0.45),
                    width: 1.5,
                  ),
                ),
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
                children: [
                  // Handle Bar
                  Center(
                    child: Container(
                      width: 44,
                      height: 4.5,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: (isDark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),

                  // Header Info
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 4.5,
                        height: 48,
                        decoration: BoxDecoration(
                          color: categoryColor,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                              color: categoryColor.withValues(alpha: 0.6),
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
                            Text(
                              participantName,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.3,
                                  ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              visitNum != null
                                  ? '$categoryName • ${widget.strings.isPt ? "Visita #$visitNum" : "Visit #$visitNum"}'
                                  : categoryName,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: categoryColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 22),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // 1. Status Selector Bar
                  Text(
                    widget.strings.statusLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _StatusChip(
                        label: widget.strings.confirmedLabel,
                        color: SyncroColors.clinicalEmerald,
                        isSelected: _status == AppointmentStatus.confirmed,
                        onTap: () => setState(
                          () => _status = AppointmentStatus.confirmed,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _StatusChip(
                        label: widget.strings.suggestedLabel,
                        color: SyncroColors.amberSuggested,
                        isSelected: _status == AppointmentStatus.suggested,
                        onTap: () => setState(
                          () => _status = AppointmentStatus.suggested,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _StatusChip(
                        label: widget.strings.completedLabel,
                        color: Colors.blue,
                        isSelected: _status == AppointmentStatus.completed,
                        onTap: () => setState(
                          () => _status = AppointmentStatus.completed,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _StatusChip(
                        label: widget.strings.cancelledLabel,
                        color: SyncroColors.coralAlert,
                        isSelected: _status == AppointmentStatus.cancelled,
                        onTap: () => setState(
                          () => _status = AppointmentStatus.cancelled,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 2. Date Picker Card
                  Text(
                    widget.strings.appointmentDateLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AnimatedScaleTap(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: primary.withValues(alpha: 0.28),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_month_rounded,
                            size: 20,
                            color: primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.strings.formatDateHeader(_selectedDate),
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.edit_calendar_rounded,
                            size: 18,
                            color: primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 3. Time Window Picker Card
                  Text(
                    widget.strings.appointmentTimeLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AnimatedScaleTap(
                    onTap: _pickStartTime,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: primary.withValues(alpha: 0.28),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 20,
                            color: primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.strings.formatTimeRange(computedRange),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Icon(Icons.tune_rounded, size: 18, color: primary),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 4. Duration Selector
                  Text(
                    widget.strings.durationLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [15, 30, 45, 60, 90, 120].map((dur) {
                      final isSelected = _durationMinutes == dur;
                      return AnimatedScaleTap(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _durationMinutes = dur);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: isSelected
                                ? LinearGradient(
                                    colors: [
                                      primary,
                                      SyncroColors.amethystViolet,
                                    ],
                                  )
                                : null,
                            color: isSelected
                                ? null
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.06)
                                    : Colors.black.withValues(alpha: 0.04)),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.transparent
                                  : primary.withValues(alpha: 0.22),
                            ),
                          ),
                          child: Text(
                            '$dur min',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: isSelected
                                  ? FontWeight.w900
                                  : FontWeight.w600,
                              color: isSelected ? Colors.white : null,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // 5. Linked Sub-Calendar Status Pill
                  if (widget.appointment.externalCalendarEventId != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: SyncroColors.clinicalEmerald
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: SyncroColors.clinicalEmerald
                              .withValues(alpha: 0.32),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.cloud_done_rounded,
                            size: 18,
                            color: SyncroColors.clinicalEmerald,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.strings.subCalendarProvisioned,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: SyncroColors.clinicalEmerald,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),

                  // 6. Action Row: Delete, Share & Save Changes
                  Row(
                    children: [
                      // Delete Button
                      IconButton.outlined(
                        tooltip: widget.strings.deleteAppointmentButton,
                        style: IconButton.styleFrom(
                          foregroundColor: SyncroColors.coralAlert,
                          side: BorderSide(
                            color: SyncroColors.coralAlert
                                .withValues(alpha: 0.45),
                          ),
                          padding: const EdgeInsets.all(13),
                        ),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 20,
                        ),
                        onPressed: _isSaving ? null : _confirmDelete,
                      ),
                      const SizedBox(width: 8),

                      // Share Button
                      IconButton.filledTonal(
                        tooltip: widget.strings.shareAction,
                        style: IconButton.styleFrom(
                          padding: const EdgeInsets.all(13),
                        ),
                        icon: const Icon(
                          Icons.share_outlined,
                          size: 20,
                        ),
                        onPressed: () => ConfirmationSheet.show(
                          context,
                          appointment: widget.appointment,
                          entity: widget.entity,
                          eventType: widget.eventType,
                          strings: widget.strings,
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Save & Reschedule Button
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.event_repeat_rounded,
                                  size: 19,
                                ),
                          label: Text(
                            widget.strings.saveChangesButton,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          onPressed: _isSaving ? null : _saveChanges,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _StatusChip({
    required this.label,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AnimatedScaleTap(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: isSelected
                ? color.withValues(alpha: 0.22)
                : color.withValues(alpha: 0.06),
            border: Border.all(
              color: isSelected
                  ? color
                  : color.withValues(alpha: 0.25),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                color: isSelected ? color : color.withValues(alpha: 0.75),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
