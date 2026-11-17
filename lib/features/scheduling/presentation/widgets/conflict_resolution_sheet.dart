import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/syncro_theme.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../domain/models/conflict_report.dart';
import '../../domain/models/entity.dart';
import '../../domain/models/event_type.dart';
import '../../domain/models/time_range.dart';
import '../providers/scheduling_providers.dart';
import 'appointment_detail_sheet.dart';

/// Glassmorphic bottom sheet for reviewing an external calendar collision
/// and 1-tap auto-resolving to an optimal alternative slot computed by [SlotFinder].
class ConflictResolutionSheet extends ConsumerStatefulWidget {
  final ConflictReport conflict;
  final Entity? entity;
  final EventType? eventType;
  final AppStrings strings;

  const ConflictResolutionSheet({
    super.key,
    required this.conflict,
    required this.entity,
    required this.eventType,
    required this.strings,
  });

  static Future<void> show(
    BuildContext context, {
    required ConflictReport conflict,
    required Entity? entity,
    required EventType? eventType,
    required AppStrings strings,
  }) {
    HapticFeedback.heavyImpact();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ConflictResolutionSheet(
        conflict: conflict,
        entity: entity,
        eventType: eventType,
        strings: strings,
      ),
    );
  }

  @override
  ConsumerState<ConflictResolutionSheet> createState() =>
      _ConflictResolutionSheetState();
}

class _ConflictResolutionSheetState
    extends ConsumerState<ConflictResolutionSheet> {
  List<TimeRange>? _candidateSlots;
  bool _isLoading = true;
  bool _isResolving = false;

  @override
  void initState() {
    super.initState();
    _loadAlternativeSlots();
  }

  Future<void> _loadAlternativeSlots() async {
    final syncService = ref.read(calendarSyncServiceProvider);
    final candidates = await syncService.suggestConflictResolutions(
      widget.conflict.appointment,
      maxSuggestions: 3,
    );
    if (mounted) {
      setState(() {
        _candidateSlots = candidates;
        _isLoading = false;
      });
    }
  }

  Future<void> _applyResolution(TimeRange targetSlot) async {
    setState(() => _isResolving = true);
    HapticFeedback.mediumImpact();

    final syncService = ref.read(calendarSyncServiceProvider);
    await syncService.autoResolveConflict(
      appointment: widget.conflict.appointment,
      newSlot: targetSlot,
    );
    ref.invalidate(calendarConflictsProvider);

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.strings.isPt
                ? 'Conflito resolvido! Agendamento movido para ${widget.strings.formatDateHeader(targetSlot.start)} (${widget.strings.formatTimeRange(targetSlot)})'
                : 'Conflict resolved! Moved to ${widget.strings.formatDateHeader(targetSlot.start)} (${widget.strings.formatTimeRange(targetSlot)})',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final participantName =
        widget.entity?.name ?? widget.conflict.appointment.entityId;
    final categoryName =
        widget.eventType?.name ?? widget.conflict.appointment.eventTypeId;

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      maxChildSize: 0.94,
      minChildSize: 0.45,
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
                    color: SyncroColors.coralAlert.withValues(alpha: 0.65),
                    width: 1.8,
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

                  // Header with Alert Badge
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: SyncroColors.coralAlert.withValues(alpha: 0.16),
                          border: Border.all(
                            color:
                                SyncroColors.coralAlert.withValues(alpha: 0.40),
                          ),
                        ),
                        child: const Icon(
                          Icons.warning_amber_rounded,
                          color: SyncroColors.coralAlert,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.strings.isPt
                                  ? 'Conflito de Agenda Detectado'
                                  : 'Calendar Collision Detected',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.2,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$participantName • $categoryName',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.color
                                    ?.withValues(alpha: 0.7),
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

                  // 1. Conflict Description Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: SyncroColors.coralAlert.withValues(alpha: 0.10),
                      border: Border.all(
                        color: SyncroColors.coralAlert.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.event_busy_rounded,
                              size: 16,
                              color: SyncroColors.coralAlert,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              widget.strings.isPt
                                  ? 'Evento Externo Concorrente'
                                  : 'Conflicting External Event',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: SyncroColors.coralAlert,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '"${widget.conflict.conflictingEvent.title}"',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.conflict.calendarName} • '
                          '${widget.strings.formatDateHeader(widget.conflict.conflictingEvent.timeRange.start)} '
                          '(${widget.strings.formatTimeRange(widget.conflict.conflictingEvent.timeRange)})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.color
                                ?.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 2. 1-Tap Auto-Resolve Action
                  Text(
                    widget.strings.isPt
                        ? 'Sugestões Sem Colisão (Motor Inteligente)'
                        : 'Collision-Free Slots (Smart Engine)',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 10),

                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    )
                  else if (_candidateSlots != null &&
                      _candidateSlots!.isNotEmpty) ...[
                    // Primary 1-Tap Auto-Resolve Button (Top Slot)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: SyncroColors.clinicalEmerald,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: _isResolving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.auto_fix_high_rounded,
                              size: 19,
                              color: Colors.white,
                            ),
                      label: Text(
                        widget.strings.isPt
                            ? 'Auto-Resolver para Melhor Horário'
                            : 'Auto-Resolve to Top Ranked Slot',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      onPressed: _isResolving
                          ? null
                          : () => _applyResolution(_candidateSlots!.first),
                    ),
                    const SizedBox(height: 14),

                    // Alternative candidate slot cards
                    for (int i = 0; i < _candidateSlots!.length; i++) ...[
                      _CandidateResolutionTile(
                        slot: _candidateSlots![i],
                        rankIndex: i,
                        strings: widget.strings,
                        onSelect: _isResolving
                            ? null
                            : () => _applyResolution(_candidateSlots![i]),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: primary.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            widget.strings.isPt
                                ? 'Nenhum horário livre encontrado em ±7 dias respeitando as regras da categoria.'
                                : 'No free slots found in ±7 days respecting category rules.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          FilledButton.tonal(
                            onPressed: () {
                              Navigator.of(context).pop();
                              AppointmentDetailSheet.show(
                                context,
                                appointment: widget.conflict.appointment,
                                entity: widget.entity,
                                eventType: widget.eventType,
                                strings: widget.strings,
                              );
                            },
                            child: Text(
                              widget.strings.isPt
                                  ? 'Ajustar Manualmente'
                                  : 'Adjust Manually',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CandidateResolutionTile extends StatelessWidget {
  final TimeRange slot;
  final int rankIndex;
  final AppStrings strings;
  final VoidCallback? onSelect;

  const _CandidateResolutionTile({
    required this.slot,
    required this.rankIndex,
    required this.strings,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final matchScore = (99 - (rankIndex * 4)).clamp(85, 99);

    return AnimatedScaleTap(
      onTap: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: primary.withValues(alpha: 0.07),
          border: Border.all(color: primary.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: SyncroColors.clinicalEmerald.withValues(alpha: 0.16),
              ),
              child: Text(
                '$matchScore%',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: SyncroColors.clinicalEmerald,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.formatDateHeader(slot.start),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    strings.formatTimeRange(slot),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.color
                          ?.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: primary,
            ),
          ],
        ),
      ),
    );
  }
}
