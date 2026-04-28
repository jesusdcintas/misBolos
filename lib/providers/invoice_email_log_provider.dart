import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_event.dart';
import '../models/invoice.dart';
import '../models/invoice_email_log.dart';
import '../repositories/app_event_repository.dart';
import '../repositories/gig_repository.dart';
import '../repositories/invoice_email_log_repository.dart';
import '../services/invoice_email_service.dart';
import 'client_provider.dart';
import 'gig_provider.dart';
import 'invoice_provider.dart';
import 'settings_provider.dart';

final invoiceEmailServiceProvider = Provider((ref) => InvoiceEmailService());

final invoiceEmailLogRepositoryProvider = Provider(
  (ref) => InvoiceEmailLogRepository.instance,
);

final invoiceEmailLogsProvider =
    FutureProvider.family<List<InvoiceEmailLog>, String>((ref, invoiceId) {
      return ref
          .read(invoiceEmailLogRepositoryProvider)
          .getByInvoice(invoiceId);
    });

final invoiceEmailSendProvider =
    AsyncNotifierProvider<InvoiceEmailSendNotifier, void>(
      InvoiceEmailSendNotifier.new,
    );

class InvoiceEmailSendNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> send(Invoice invoice) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final client = await ref.read(
        clientByIdProvider(invoice.clientId).future,
      );
      if (client == null) {
        throw InvoiceEmailException('Cliente no encontrado.');
      }
      final recipient = client.email?.trim() ?? '';
      final settings = await ref.read(settingsProvider.future);
      final service = ref.read(invoiceEmailServiceProvider);
      final repository = ref.read(invoiceEmailLogRepositoryProvider);
      final subject = service.buildSubject(invoice);
      final log = InvoiceEmailLog(
        invoiceId: invoice.id,
        clientId: invoice.clientId,
        recipientEmail: recipient,
        provider: InvoiceEmailService.provider,
        subject: subject,
      );

      await repository.insert(log);

      try {
        await service.sendInvoice(
          invoice: invoice,
          client: client,
          settings: settings,
        );

        await repository.update(
          log.copyWith(status: InvoiceEmailStatus.sent, sentAt: DateTime.now()),
        );
        await AppEventRepository.instance.insert(
          AppEvent(
            entityType: 'invoice',
            entityId: invoice.id,
            eventType: 'invoice_email_sent',
            payload: {
              'numero': invoice.numero,
              'client_id': invoice.clientId,
              'recipient_email': recipient,
              'provider': InvoiceEmailService.provider,
            },
          ),
        );

        await ref
            .read(invoicesProvider.notifier)
            .updateStatus(invoice.id, InvoiceStatus.enviada);
        final updated = invoice.copyWith(status: InvoiceStatus.enviada);
        await GigRepository.instance.repairStatusesFromInvoices([updated]);
        ref.invalidate(gigByIdProvider(invoice.gigId));
        ref.invalidate(gigsProvider);
        ref.invalidate(invoiceEmailLogsProvider(invoice.id));
      } catch (e) {
        await repository.update(
          log.copyWith(
            status: InvoiceEmailStatus.failed,
            errorMessage: e.toString(),
          ),
        );
        await AppEventRepository.instance.insert(
          AppEvent(
            entityType: 'invoice',
            entityId: invoice.id,
            eventType: 'invoice_email_failed',
            payload: {
              'numero': invoice.numero,
              'client_id': invoice.clientId,
              'recipient_email': recipient,
              'provider': InvoiceEmailService.provider,
              'error': e.toString(),
            },
          ),
        );
        ref.invalidate(invoiceEmailLogsProvider(invoice.id));
        rethrow;
      }
    });
  }
}
