import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/client_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/pdf_service.dart';

class InvoicePreviewScreen extends ConsumerWidget {
  final String invoiceId;
  const InvoicePreviewScreen({super.key, required this.invoiceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoiceAsync = ref.watch(invoiceByIdProvider(invoiceId));

    return Scaffold(
      appBar: AppBar(title: const Text('Vista previa')),
      body: invoiceAsync.when(
        data: (invoice) {
          if (invoice == null) {
            return const Center(child: Text('Factura no encontrada'));
          }
          return FutureBuilder(
            future: Future.wait([
              ref.read(clientByIdProvider(invoice.clientId).future),
              ref.read(settingsProvider.future),
            ]),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final client = snapshot.data![0];
              final settings = snapshot.data![1];
              if (client == null) {
                return const Center(child: Text('Cliente no encontrado'));
              }
              return PdfPreview(
                build: (format) async {
                  final file = await PdfService().generateInvoicePdf(
                    invoice: invoice,
                    client: client as dynamic,
                    settings: settings as dynamic,
                  );
                  return file.readAsBytesSync();
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
