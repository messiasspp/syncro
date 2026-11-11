import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/syncro_theme.dart';
import '../../domain/models/appointment.dart';
import '../../domain/models/entity.dart';
import '../../domain/models/event_type.dart';

/// Parses a hex string like `'#7C4DFF'` into a Flutter [Color].
Color parseHexColor(String hex,
    {Color fallback = SyncroColors.electricIndigo}) {
  final cleaned = hex.replaceAll('#', '').trim();
  if (cleaned.length != 6 && cleaned.length != 8) return fallback;
  final fullHex = cleaned.length == 6 ? 'FF$cleaned' : cleaned;
  final value = int.tryParse(fullHex, radix: 16);
  return value != null ? Color(value) : fallback;
}

/// Frosted glassmorphic bottom sheet displaying a 1-tap WhatsApp, SMS, and Email
/// confirmation template for a scheduled or suggested [Appointment].
class ConfirmationSheet extends StatelessWidget {
  final Appointment appointment;
  final Entity? entity;
  final EventType? eventType;
  final AppStrings strings;

  const ConfirmationSheet({
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
      builder: (_) => ConfirmationSheet(
        appointment: appointment,
        entity: entity,
        eventType: eventType,
        strings: strings,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final participantName = entity?.name ?? appointment.entityId;
    final categoryName = eventType?.name ?? appointment.eventTypeId;
    final visitNum =
        appointment.visitIndex != null ? appointment.visitIndex! + 1 : null;

    final messageText = strings.buildConfirmationMessage(
      participantName: participantName,
      eventTypeName: categoryName,
      timeRange: appointment.timeRange,
      visitNumber: visitNum,
    );

    final phoneDigits =
        (entity?.phone ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
    final emailAddress = entity?.email ?? '';

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.of(context).viewInsets.bottom + 28,
          ),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.18)
                    : SyncroColors.electricIndigo.withValues(alpha: 0.20),
                width: 1.2,
              ),
            ),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? [
                      const Color(0xFF17223B).withValues(alpha: 0.90),
                      const Color(0xFF0B101D).withValues(alpha: 0.94),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.92),
                      const Color(0xFFF1F5F9).withValues(alpha: 0.96),
                    ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.send_rounded,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      strings.isPt
                          ? 'Confirmar com $participantName'
                          : '1-Tap Confirmation • $participantName',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.black : Colors.white)
                      .withValues(alpha: isDark ? 0.28 : 0.75),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: (isDark ? Colors.white : SyncroColors.electricIndigo)
                        .withValues(alpha: 0.12),
                  ),
                ),
                child: SelectableText(
                  messageText,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.45,
                      ),
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('WhatsApp'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => _launchChannel(
                      context,
                      Uri.parse(
                        'https://wa.me/${phoneDigits.replaceAll('+', '')}?text=${Uri.encodeComponent(messageText)}',
                      ),
                      messageText,
                    ),
                  ),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.sms_outlined, size: 18),
                    label: const Text('SMS'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => _launchChannel(
                      context,
                      Uri.parse(
                        'sms:$phoneDigits?body=${Uri.encodeComponent(messageText)}',
                      ),
                      messageText,
                    ),
                  ),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.email_outlined, size: 18),
                    label: const Text('Email'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => _launchChannel(
                      context,
                      Uri.parse(
                        'mailto:$emailAddress?subject=${Uri.encodeComponent('Syncro: $categoryName')}&body=${Uri.encodeComponent(messageText)}',
                      ),
                      messageText,
                    ),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: Text(strings.isPt ? 'Copiar' : 'Copy'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () async {
                      HapticFeedback.lightImpact();
                      await Clipboard.setData(ClipboardData(text: messageText));
                      if (context.mounted) {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              strings.isPt
                                  ? 'Mensagem copiada para a área de transferência!'
                                  : 'Confirmation message copied to clipboard!',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launchChannel(
    BuildContext context,
    Uri uri,
    String fallbackCopyText,
  ) async {
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        await Clipboard.setData(ClipboardData(text: fallbackCopyText));
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                strings.isPt
                    ? 'App externo indisponível no emulador — mensagem copiada!'
                    : 'External app unavailable on emulator — message copied!',
              ),
            ),
          );
        }
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: fallbackCopyText));
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              strings.isPt
                  ? 'Mensagem copiada para envio!'
                  : 'Confirmation message copied!',
            ),
          ),
        );
      }
    }
  }
}
