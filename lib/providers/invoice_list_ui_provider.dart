import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/client.dart';
import '../models/invoice.dart';
import 'client_provider.dart';
import 'invoice_provider.dart';

enum InvoiceSortOption {
  fechaDesc,
  fechaAsc,
  numeroDesc,
  numeroAsc,
  clienteAsc,
  clienteDesc,
  precioDesc,
  precioAsc,
}

final invoiceStatusFilterProvider = StateProvider<InvoiceStatus?>(
  (ref) => null,
);
final invoiceYearFilterProvider = StateProvider<int?>(
  (ref) => DateTime.now().year,
);
final invoiceMonthFilterProvider = StateProvider<int?>((ref) => null);
final invoiceClientFilterProvider = StateProvider<String?>((ref) => null);

// Orden por defecto: número de factura descendente.
final invoiceSortProvider = StateProvider<InvoiceSortOption>(
  (ref) => InvoiceSortOption.numeroDesc,
);

final filteredSortedInvoicesProvider = Provider<List<Invoice>>((ref) {
  final invoices = ref.watch(invoicesProvider).valueOrNull ?? const <Invoice>[];
  final statusFilter = ref.watch(invoiceStatusFilterProvider);
  final selectedYear = ref.watch(invoiceYearFilterProvider);
  final selectedMonth = ref.watch(invoiceMonthFilterProvider);
  final clientFilter = ref.watch(invoiceClientFilterProvider);
  final sortOption = ref.watch(invoiceSortProvider);

  final clients = ref.watch(clientsProvider).valueOrNull ?? const <Client>[];
  final clientsById = {for (final client in clients) client.id: client};

  final filtered = invoices.where((invoice) {
    if (statusFilter != null && invoice.status != statusFilter) {
      return false;
    }
    if (selectedYear != null && invoice.fecha.year != selectedYear) {
      return false;
    }
    if (selectedMonth != null && invoice.fecha.month != selectedMonth) {
      return false;
    }
    if (clientFilter != null && invoice.clientId != clientFilter) {
      return false;
    }
    return true;
  }).toList();

  filtered.sort((a, b) {
    switch (sortOption) {
      case InvoiceSortOption.fechaDesc:
        return b.fecha.compareTo(a.fecha);
      case InvoiceSortOption.fechaAsc:
        return a.fecha.compareTo(b.fecha);
      case InvoiceSortOption.numeroDesc:
        return b.numero.compareTo(a.numero);
      case InvoiceSortOption.numeroAsc:
        return a.numero.compareTo(b.numero);
      case InvoiceSortOption.clienteAsc:
        final aName =
            (clientsById[a.clientId]?.alias.isNotEmpty == true
                ? clientsById[a.clientId]!.alias
                : clientsById[a.clientId]?.nombre) ??
            '';
        final bName =
            (clientsById[b.clientId]?.alias.isNotEmpty == true
                ? clientsById[b.clientId]!.alias
                : clientsById[b.clientId]?.nombre) ??
            '';
        return aName.toLowerCase().compareTo(bName.toLowerCase());
      case InvoiceSortOption.clienteDesc:
        final aName =
            (clientsById[a.clientId]?.alias.isNotEmpty == true
                ? clientsById[a.clientId]!.alias
                : clientsById[a.clientId]?.nombre) ??
            '';
        final bName =
            (clientsById[b.clientId]?.alias.isNotEmpty == true
                ? clientsById[b.clientId]!.alias
                : clientsById[b.clientId]?.nombre) ??
            '';
        return bName.toLowerCase().compareTo(aName.toLowerCase());
      case InvoiceSortOption.precioDesc:
        return b.total.compareTo(a.total);
      case InvoiceSortOption.precioAsc:
        return a.total.compareTo(b.total);
    }
  });

  return filtered;
});
