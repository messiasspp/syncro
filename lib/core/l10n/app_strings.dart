import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../features/scheduling/domain/models/time_range.dart';

/// Supported application languages.
enum AppLanguage {
  en('en', 'English (US)'),
  ptBr('pt_BR', 'Português (Brasil)');

  final String code;
  final String label;
  const AppLanguage(this.code, this.label);
}

/// Holds the active language selection (EN or PT-BR).
final appLanguageProvider = StateProvider<AppLanguage>((ref) {
  return AppLanguage.en;
});

/// Holds whether times are formatted in 24-hour (`19:00`) or 12-hour (`7:00 PM`) style.
final use24HourFormatProvider = StateProvider<bool>((ref) {
  return true;
});

/// Localization dictionary and date/time formatter for English and Portuguese (pt-BR).
class AppStrings {
  final AppLanguage language;
  final bool use24Hour;

  const AppStrings({
    required this.language,
    this.use24Hour = true,
  });

  bool get isPt => language == AppLanguage.ptBr;

  // Navigation Tabs
  String get tabAgenda => isPt ? 'Agenda' : 'Agenda';
  String get tabEventTypes => isPt ? 'Tipos' : 'Event Types';
  String get tabEntities => isPt ? 'Pessoas' : 'Entities';
  String get tabScheduler => isPt ? 'Motor' : 'Scheduler';
  String get tabSettings => isPt ? 'Ajustes' : 'Settings';

  // App Bar & Global Actions
  String get appTitle =>
      isPt ? 'Syncro • Motor de Agenda' : 'Syncro Calendar Engine';
  String get syncCalendarsTooltip => isPt
      ? 'Sincronizar com Calendários do Dispositivo'
      : 'Sync with Device Calendars';
  String get resetDemoDataTooltip => isPt
      ? 'Restaurar Cenários de Demonstração'
      : 'Reset & Re-seed Demo Data';
  String get demoResetSuccess => isPt
      ? 'Cenários de demonstração recriados sem conflitos!'
      : 'Demo scenarios reset & re-seeded collision-free!';

  // Agenda Screen
  String get allFilter => isPt ? 'Todos' : 'All';
  String get confirmedLabel => isPt ? 'Confirmado' : 'Confirmed';
  String get suggestedLabel => isPt ? 'Sugerido' : 'Suggested';
  String get completedLabel => isPt ? 'Concluído' : 'Completed';
  String get cancelledLabel => isPt ? 'Cancelado' : 'Cancelled';
  String get totalAppointmentsLabel => isPt ? 'Total' : 'Total';
  String get noAppointmentsFound => isPt
      ? 'Nenhum agendamento encontrado para este filtro.'
      : 'No appointments found for this filter.';
  String get confirmAction => isPt ? 'Confirmar' : 'Confirm';
  String get shareAction => isPt ? 'Mensagem' : 'Share';
  String get syncedBadge => isPt ? 'Sincronizado' : 'Synced';

  // Event Types Screen
  String get eventTypesHeader => isPt
      ? 'Categorias e Regras de Agendamento'
      : 'Event Categories & Scheduling Rules';
  String get newEventTypeButton =>
      isPt ? 'Novo Tipo de Evento' : 'New Event Type';
  String get workHoursOnlyLabel =>
      isPt ? 'Apenas Horário Comercial' : 'Work Hours Only';
  String get outsideWorkHoursLabel =>
      isPt ? 'Fora do Expediente (Pessoal)' : 'Outside Work Hours';
  String get bothFlexibleLabel =>
      isPt ? 'Flexível (Qualquer Horário)' : 'Flexible (Any Time)';
  String get instantAutoLabel =>
      isPt ? 'Auto-Agendamento Instantâneo' : 'Instant Auto-Schedule';
  String get suggestTopRankedLabel =>
      isPt ? 'Revisão de Sugestões' : 'Suggestion Review';
  String get durationLabel => isPt ? 'Duração' : 'Duration';
  String get buffersLabel => isPt ? 'Margens (Buffer)' : 'Buffers';
  String get allowedWindowsLabel =>
      isPt ? 'Janelas Permitidas' : 'Allowed Windows';
  String get subCalendarProvisioned =>
      isPt ? 'Sub-calendário dedicado ativo' : 'Dedicated sub-calendar linked';
  String get subCalendarPending => isPt
      ? 'Sub-calendário será criado ao sincronizar'
      : 'Sub-calendar created on next sync';

  // Entities Screen
  String get entitiesHeader => isPt
      ? 'Participantes, Amigos e Pacientes'
      : 'Participants, Friends & Patients';
  String get newEntityButton => isPt ? 'Novo Participante' : 'New Entity';
  String get customOverridesLabel =>
      isPt ? 'Restrição Personalizada' : 'Availability Override';
  String get defaultScheduleLabel =>
      isPt ? 'Segue regras padrão da categoria' : 'Follows default Event Type rules';
  String get viewProtocolRoadmap =>
      isPt ? 'Ver Protocolo (24 Visitas)' : 'View Protocol Roadmap (24 Visits)';

  // Smart Scheduler & Cascade Screen
  String get slotFinderTab =>
      isPt ? 'Buscador de Horários' : 'Smart Slot Finder';
  String get cascadeManagerTab =>
      isPt ? 'Cascata de Protocolo' : 'Protocol Cascade';
  String get findOptimalSlotsButton =>
      isPt ? 'Calcular Horários Livres' : 'Find Collision-Free Slots';
  String get bookSlotButton => isPt ? 'Agendar' : 'Book Slot';
  String get delayVisitAndCascadeButton => isPt
      ? 'Adiar Visita e Recalcular Cascata'
      : 'Delay Visit & Recalculate Cascade';
  String get cascadeSuccessBanner => isPt
      ? 'Cascata aplicada! Visitas seguintes foram recalculadas sem colisões.'
      : 'Cascade applied! Downstream visits recalculated without collisions.';

  // Settings Screen
  String get appearanceSectionTitle =>
      isPt ? 'Aparência e Tema Visual' : 'Visual Appearance & Theme';
  String get darkGlassThemeLabel =>
      isPt ? 'Obsidian Dark (Glass)' : 'Obsidian Dark (Glass)';
  String get lightGlassThemeLabel =>
      isPt ? 'Luminous Light' : 'Luminous Light';
  String get languageSectionTitle =>
      isPt ? 'Idioma e Formato de Hora' : 'Language & Time Format';
  String get use24HourLabel =>
      isPt ? 'Formato 24 horas (19:00)' : '24-Hour Time Format (19:00)';
  String get workScheduleSectionTitle =>
      isPt ? 'Expediente de Trabalho' : 'Primary Work Schedule';
  String get workHoursRangeLabel =>
      isPt ? 'Horário de Trabalho' : 'Working Hours';
  String get connectedCalendarsSectionTitle => isPt
      ? 'Calendários Conectados no Dispositivo'
      : 'Connected Device Calendars';
  String get syncNowButton =>
      isPt ? 'Sincronizar Agora' : 'Sync All Confirmed Appointments';
  String get resetDemoButton =>
      isPt ? 'Restaurar Dados de Demonstração' : 'Reset Pre-seeded Demo Data';
  String get swipeToConfirmHint => isPt
      ? 'Deslize para confirmar →'
      : 'Swipe right to confirm →';
  String get allDatesLabel => isPt ? 'Todas as Datas' : 'All Dates';

  // Weekday Names
  String weekdayName(int weekday, {bool short = false}) {
    if (isPt) {
      const fullPt = {
        DateTime.monday: 'Segunda-feira',
        DateTime.tuesday: 'Terça-feira',
        DateTime.wednesday: 'Quarta-feira',
        DateTime.thursday: 'Quinta-feira',
        DateTime.friday: 'Sexta-feira',
        DateTime.saturday: 'Sábado',
        DateTime.sunday: 'Domingo',
      };
      const shortPt = {
        DateTime.monday: 'Seg',
        DateTime.tuesday: 'Ter',
        DateTime.wednesday: 'Qua',
        DateTime.thursday: 'Qui',
        DateTime.friday: 'Sex',
        DateTime.saturday: 'Sáb',
        DateTime.sunday: 'Dom',
      };
      return (short ? shortPt[weekday] : fullPt[weekday]) ?? '';
    } else {
      const fullEn = {
        DateTime.monday: 'Monday',
        DateTime.tuesday: 'Tuesday',
        DateTime.wednesday: 'Wednesday',
        DateTime.thursday: 'Thursday',
        DateTime.friday: 'Friday',
        DateTime.saturday: 'Saturday',
        DateTime.sunday: 'Sunday',
      };
      const shortEn = {
        DateTime.monday: 'Mon',
        DateTime.tuesday: 'Tue',
        DateTime.wednesday: 'Wed',
        DateTime.thursday: 'Thu',
        DateTime.friday: 'Fri',
        DateTime.saturday: 'Sat',
        DateTime.sunday: 'Sun',
      };
      return (short ? shortEn[weekday] : fullEn[weekday]) ?? '';
    }
  }

  String formatDateHeader(DateTime date) {
    final dayName = weekdayName(date.weekday);
    final formatted = DateFormat('MMM d, yyyy').format(date);
    return '$dayName, $formatted';
  }

  String formatTime(DateTime time) {
    if (use24Hour) {
      final hh = time.hour.toString().padLeft(2, '0');
      final mm = time.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    } else {
      return DateFormat('h:mm a').format(time);
    }
  }

  String formatTimeRange(TimeRange range) {
    return '${formatTime(range.start)} – ${formatTime(range.end)}';
  }

  String buildConfirmationMessage({
    required String participantName,
    required String eventTypeName,
    required TimeRange timeRange,
    int? visitNumber,
  }) {
    final dateStr = formatDateHeader(timeRange.start);
    final timeStr = formatTimeRange(timeRange);
    final visitTag = visitNumber != null
        ? (isPt ? ' (Visita #$visitNumber)' : ' (Visit #$visitNumber)')
        : '';

    if (isPt) {
      return 'Olá $participantName! Seu agendamento de "$eventTypeName$visitTag" '
          'está marcado para $dateStr, das $timeStr. Até lá!';
    } else {
      return 'Hi $participantName! Your "$eventTypeName$visitTag" appointment '
          'is scheduled for $dateStr at $timeStr. Please reply to confirm!';
    }
  }
}

/// Reactive provider supplying the localized [AppStrings] instance.
final appStringsProvider = Provider<AppStrings>((ref) {
  final lang = ref.watch(appLanguageProvider);
  final use24h = ref.watch(use24HourFormatProvider);
  return AppStrings(language: lang, use24Hour: use24h);
});
