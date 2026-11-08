import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../domain/models/appointment.dart';
import '../../domain/models/entity.dart';
import '../../domain/models/event_type.dart';

/// Parses a hex string like `'#7C4DFF'` into a Flutter [Color].
Color parseHexColor(String hex, {Color fallback = Colors.indigo}) {
  final cleaned = hex.replaceAll('#', '').trim();
  if (cleaned.length != 6 && cleaned.length != 8) return fallback;
  final fullHex = cleaned.length == 6 ? 'FF$cleaned' : cleaned;
  final value = int.tryParse(fullHex, radix: 16);
  return value != null ? Color(value) : fallback;
}

/// Bottom sheet displaying a 1-tap WhatsApp, SMS, and Email confirmation template
/// for a scheduled or suggested [Appointment].
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
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
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

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.send_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  strings.isPt
                      ? 'Confirmar com $participantName'
                      : '1-Tap Confirmation • $participantName',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(
              messageText,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('WhatsApp'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
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
                icon: const Icon(Icons.sms_outlined),
                label: const Text('SMS'),
                onPressed: () => _launchChannel(
                  context,
                  Uri.parse(
                    'sms:$phoneDigits?body=${Uri.encodeComponent(messageText)}',
                  ),
                  messageText,
                ),
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.email_outlined),
                label: const Text('Email'),
                onPressed: () => _launchChannel(
                  context,
                  Uri.parse(
                    'mailto:$emailAddress?subject=${Uri.encodeComponent('Syncro: $categoryName')}&body=${Uri.encodeComponent(messageText)}',
                  ),
                  messageText,
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy_rounded),
                label: Text(strings.isPt ? 'Copiar' : 'Copy'),
                onPressed: () async {
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
