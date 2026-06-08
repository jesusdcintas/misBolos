import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../models/client.dart';
import '../../models/invoice.dart';
import '../../models/invoice_email_log.dart';
import '../../models/gig.dart';
import '../../providers/invoice_list_ui_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/invoice_email_log_provider.dart';
import '../../providers/client_provider.dart';
import '../../providers/gig_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/pdf_service.dart';
import '../../services/notification_service.dart';
import '../../services/google_auth_service.dart';
import '../../services/google_calendar_service.dart';
import 'package:share_plus/share_plus.dart';

class InvoiceDetailScreen extends ConsumerStatefulWidget {
  final String invoiceId;
  const InvoiceDetailScreen({super.key, required this.invoiceId});

  @override
  ConsumerState<InvoiceDetailScreen> createState() =>
      _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends ConsumerState<InvoiceDetailScreen> {
  static const _pageAnimDuration = Duration(milliseconds: 250);
  PageController? _pageController;
  bool _controllerReady = false;
  int _currentIndex = 0;

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleInvoices = ref.watch(filteredSortedInvoicesProvider);
    final allInvoices =
        ref.watch(invoicesProvider).valueOrNull ?? const <Invoice>[];
    final invoices = visibleInvoices.isNotEmpty
        ? visibleInvoices
        : ([...allInvoices]..sort((a, b) => b.numero.compareTo(a.numero)));

    if (invoices.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Factura no encontrada')),
      );
    }

    var currentIndex = invoices.indexWhere((inv) => inv.id == widget.invoiceId);
    if (currentIndex < 0) currentIndex = 0;
    final currentInvoice = invoices[currentIndex];
    final currentInvoiceId = currentInvoice.id;

    if (!_controllerReady) {
      _controllerReady = true;
      _currentIndex = currentIndex;
      _pageController = PageController(initialPage: currentIndex);
    } else if (((_pageController?.hasClients ?? false)
            ? _pageController?.page?.round()
            : _currentIndex) !=
        currentIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !(_pageController?.hasClients ?? false)) return;
        _pageController?.jumpToPage(currentIndex);
      });
      _currentIndex = currentIndex;
    }

    Future<void> goPrevious() async {
      if (_currentIndex <= 0) return;
      await _pageController!.previousPage(
        duration: _pageAnimDuration,
        curve: Curves.easeOutCubic,
      );
    }

    Future<void> goNext() async {
      if (_currentIndex >= invoices.length - 1) return;
      await _pageController!.nextPage(
        duration: _pageAnimDuration,
        curve: Curves.easeOutCubic,
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Volver',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/finanzas');
            }
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(currentInvoice.visualNumber),
            Text(
              'Factura ${currentIndex + 1} de ${invoices.length}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Factura anterior',
            onPressed: currentIndex == 0 ? null : goPrevious,
            icon: const Icon(Icons.arrow_back_ios_new),
          ),
          IconButton(
            tooltip: 'Factura siguiente',
            onPressed: currentIndex == invoices.length - 1 ? null : goNext,
            icon: const Icon(Icons.arrow_forward_ios),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: invoices.length,
        physics: const BouncingScrollPhysics(),
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
          final targetId = invoices[index].id;
          if (targetId != currentInvoiceId) {
            context.replace('/invoice/$targetId');
          }
        },
        itemBuilder: (context, index) {
          return _InvoiceDetailContent(
            invoiceId: invoices[index].id,
            invoice: invoices[index],
          );
        },
      ),
    );
  }
}

class _InvoiceDetailContent extends ConsumerWidget {
  final String invoiceId;
  final Invoice invoice;
  const _InvoiceDetailContent({required this.invoiceId, required this.invoice});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientAsync = ref.watch(clientByIdProvider(invoice.clientId));
    final settingsAsync = ref.watch(settingsProvider);
    final emailSendState = ref.watch(invoiceEmailSendProvider);
    final emailLogsAsync = ref.watch(invoiceEmailLogsProvider(invoice.id));
    final relatedRectificatives =
        ref
            .watch(invoicesProvider)
            .valueOrNull
            ?.where(
              (candidate) =>
                  candidate.rectifiesInvoiceId == invoice.id &&
                  candidate.deletedAt == null,
            )
            .toList(growable: false) ??
        const <Invoice>[];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Preview card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      invoice.displayName.toUpperCase(),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (invoice.isRectifying)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'RECTIFICATIVA',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          invoice.visualNumber,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (invoice.isRectifying) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warningBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Factura rectificativa',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AppColors.warning,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Factura rectificada: ${invoice.originalInvoiceNumber ?? '-'}',
                        ),
                        if (invoice.originalInvoiceDate != null)
                          Text(
                            'Fecha factura original: ${DateFormatter.display(invoice.originalInvoiceDate!)}',
                          ),
                        Text(
                          'Motivo: ${invoice.rectificationReasonType?.label ?? 'Sin motivo'}',
                        ),
                        Text(
                          'Tipo de rectificación: ${invoice.rectificationType == RectificationType.difference ? 'Diferencias' : 'Sustitución'}',
                        ),
                        if ((invoice.rectificationReasonDescription ?? '')
                            .trim()
                            .isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(invoice.rectificationReasonDescription!.trim()),
                        ],
                      ],
                    ),
                  ),
                ],
                const Divider(),
                const SizedBox(height: 8),

                // Emisor / Cliente
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppStrings.emisor,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          settingsAsync.when(
                            data: (s) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.emisorNombre,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                if (s.emisorNIF.isNotEmpty)
                                  Text(
                                    s.emisorNIF,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                if (s.emisorDireccion.isNotEmpty)
                                  Text(
                                    s.emisorDireccion,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                if (s.emisorCiudad.isNotEmpty ||
                                    s.emisorProvincia.isNotEmpty ||
                                    s.emisorCodigoPostal.isNotEmpty)
                                  Text(
                                    [
                                      s.emisorCiudad,
                                      if (s.emisorProvincia.isNotEmpty)
                                        s.emisorProvincia,
                                      if (s.emisorCodigoPostal.isNotEmpty)
                                        s.emisorCodigoPostal,
                                    ].where((str) => str.isNotEmpty).join(', '),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                if (s.emisorEmail.isNotEmpty)
                                  Text(
                                    s.emisorEmail,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue,
                                    ),
                                  ),
                                if (s.emisorTelefono.isNotEmpty)
                                  Text(
                                    s.emisorTelefono,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                              ],
                            ),
                            loading: () => const SizedBox(),
                            error: (_, __) => const SizedBox(),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppStrings.facturarA,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          clientAsync.when(
                            data: (c) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c?.nombre ?? '',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                if (c?.cifNif.isNotEmpty == true)
                                  Text(
                                    c!.cifNif,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                if (c?.direccion.isNotEmpty == true)
                                  Text(
                                    c!.direccion,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                if (c?.ciudad.isNotEmpty == true ||
                                    c?.codigoPostal.isNotEmpty == true ||
                                    c?.provincia.isNotEmpty == true)
                                  Text(
                                    [
                                      c?.ciudad ?? '',
                                      if (c?.provincia.isNotEmpty == true)
                                        c!.provincia,
                                      if (c?.codigoPostal.isNotEmpty == true)
                                        c!.codigoPostal,
                                    ].where((s) => s.isNotEmpty).join(', '),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                if (c?.email != null && c!.email!.isNotEmpty)
                                  Text(
                                    c.email!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue,
                                    ),
                                  ),
                                if (c?.telefono != null &&
                                    c!.telefono!.isNotEmpty)
                                  Text(
                                    c.telefono!,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                if (c?.whatsappPhone != null &&
                                    c!.whatsappPhone!.isNotEmpty)
                                  Text(
                                    'WhatsApp: ${c.whatsappPhone!}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                              ],
                            ),
                            loading: () => const SizedBox(),
                            error: (_, __) => const SizedBox(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Text(
                  'Fecha: ${DateFormatter.display(invoice.fecha)}',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 16),

                // Items table
                Table(
                  border: TableBorder.all(color: AppColors.divider),
                  columnWidths: const {
                    0: FlexColumnWidth(1),
                    1: FlexColumnWidth(3),
                    2: FlexColumnWidth(2),
                    3: FlexColumnWidth(2),
                  },
                  children: [
                    TableRow(
                      decoration: BoxDecoration(color: AppColors.primary),
                      children: [
                        _tableHeader(AppStrings.cantidad),
                        _tableHeader(AppStrings.descripcion),
                        _tableHeader(AppStrings.precioUnidad),
                        _tableHeader(AppStrings.totalLinea),
                      ],
                    ),
                    for (final item in invoice.items)
                      TableRow(
                        children: [
                          _tableCell('${item.cantidad}', TextAlign.center),
                          _tableCell(item.descripcion, TextAlign.left),
                          _tableCell(
                            CurrencyFormatter.format(item.precioUnitario),
                            TextAlign.right,
                          ),
                          _tableCell(
                            CurrencyFormatter.format(item.totalLinea),
                            TextAlign.right,
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // Totals
                Align(
                  alignment: Alignment.centerRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Subtotal: ${CurrencyFormatter.format(invoice.subtotal)}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      Text(
                        'IVA (${(invoice.ivaRate * 100).toStringAsFixed(0)}%): ${CurrencyFormatter.format(invoice.ivaAmount)}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      if (invoice.irpfRate > 0)
                        Text(
                          'Retención IRPF (${(invoice.irpfRate * 100).toStringAsFixed(0)}%): -${CurrencyFormatter.format(invoice.irpfAmount)}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.accentRed,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'TOTAL: ${CurrencyFormatter.format(invoice.total)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        if (relatedRectificatives.isNotEmpty) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Rectificativas asociadas',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  for (final rectifying in relatedRectificatives) ...[
                    InkWell(
                      onTap: () => context.push('/invoice/${rectifying.id}'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'RECTIFICATIVA',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${rectifying.visualNumber} · ${rectifying.rectificationReasonType?.label ?? 'Sin motivo'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Estado
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: _statusBgColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              invoice.status.label,
              style: TextStyle(
                color: _statusTextColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (invoice.isRectifying) ...[
          const SizedBox(height: 8),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Rectificativa',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
        if (invoice.isFiscallyIssued ||
            (invoice.fiscalHash?.isNotEmpty ?? false)) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Estado fiscal: ${invoice.fiscalStateLabel} · Hash: ${invoice.fiscalHash == null ? '-' : invoice.fiscalHash!.substring(0, invoice.fiscalHash!.length < 12 ? invoice.fiscalHash!.length : 12)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
        const SizedBox(height: 16),

        if (invoice.isFiscallyLocked) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warningBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.warning),
            ),
            child: const Text(
              'Factura bloqueada por modo VeriFactu',
              style: TextStyle(
                color: AppColors.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Cambiar estado
        if (invoice.status == InvoiceStatus.borrador)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _markAs(context, ref, InvoiceStatus.enviada),
              icon: const Icon(Icons.send),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
              ),
              label: const Text('Marcar como facturada'),
            ),
          ),
        if (invoice.status == InvoiceStatus.enviada)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _markAs(context, ref, InvoiceStatus.pagada),
              icon: const Icon(Icons.check_circle),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
              ),
              label: const Text('Marcar como cobrada'),
            ),
          ),
        if (invoice.status != InvoiceStatus.borrador &&
            !invoice.isFiscallyLocked) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _revertStatus(context, ref),
              icon: const Icon(Icons.undo),
              label: Text(
                invoice.status == InvoiceStatus.pagada
                    ? 'Revertir a pendiente de cobro'
                    : 'Revertir a borrador',
              ),
            ),
          ),
        ],
        if (invoice.status != InvoiceStatus.pagada) const SizedBox(height: 8),

        // Editar (solo en borrador)
        if (invoice.status == InvoiceStatus.borrador &&
            !invoice.isFiscallyLocked)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/invoice/edit/${invoice.id}'),
              icon: const Icon(Icons.edit),
              label: const Text('Editar factura'),
            ),
          ),
        if (invoice.status == InvoiceStatus.borrador &&
            !invoice.isFiscallyLocked)
          const SizedBox(height: 8),

        if (invoice.isFiscallyLocked)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _createRectifyingInvoice(context, ref),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Crear rectificativa'),
            ),
          ),
        if (invoice.isFiscallyLocked) const SizedBox(height: 8),

        // Compartir
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _share(context, ref),
            icon: const Icon(Icons.share),
            label: const Text(AppStrings.compartirPDF),
          ),
        ),
        const SizedBox(height: 8),

        // Enviar por email
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: emailSendState.isLoading
                ? null
                : () => _sendByEmail(context, ref),
            icon: emailSendState.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.mark_email_read_outlined),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            label: const Text('Enviar por email'),
          ),
        ),
        const SizedBox(height: 8),

        const SizedBox(height: 16),

        emailLogsAsync.when(
          data: (logs) => _EmailLogSection(logs: logs),
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
        const SizedBox(height: 8),

        // Eliminar factura
        if (!invoice.isFiscallyLocked)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _deleteInvoice(context, ref),
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
              label: const Text('Eliminar factura'),
            ),
          ),
      ],
    );
  }

  Color get _statusBgColor {
    if (invoice.isRectifying && invoice.status == InvoiceStatus.pagada) {
      return AppColors.fiscalBg;
    }
    if (invoice.isRectifying && invoice.status == InvoiceStatus.enviada) {
      return AppColors.purpleBg;
    }
    switch (invoice.status) {
      case InvoiceStatus.borrador:
        return AppColors.primaryLight;
      case InvoiceStatus.enviada:
        return AppColors.warningBg;
      case InvoiceStatus.pagada:
        return AppColors.successBg;
    }
  }

  Color get _statusTextColor {
    if (invoice.isRectifying && invoice.status == InvoiceStatus.pagada) {
      return AppColors.fiscal;
    }
    if (invoice.isRectifying && invoice.status == InvoiceStatus.enviada) {
      return AppColors.purple;
    }
    switch (invoice.status) {
      case InvoiceStatus.borrador:
        return AppColors.primary;
      case InvoiceStatus.enviada:
        return AppColors.warning;
      case InvoiceStatus.pagada:
        return AppColors.success;
    }
  }

  Widget _tableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _tableCell(String text, TextAlign align) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(text, style: const TextStyle(fontSize: 11), textAlign: align),
    );
  }

  Future<void> _share(BuildContext context, WidgetRef ref) async {
    final box = context.findRenderObject() as RenderBox?;
    final shareOrigin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 100, 100);
    try {
      final client = await ref.read(
        clientByIdProvider(invoice.clientId).future,
      );
      final settings = await ref.read(settingsProvider.future);

      if (client == null) return;

      final file = await PdfService().generateInvoicePdf(
        invoice: invoice,
        client: client,
        settings: settings,
      );

      await Share.shareXFiles([
        XFile(file.path),
      ], sharePositionOrigin: shareOrigin);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _sendByEmail(BuildContext context, WidgetRef ref) async {
    final client = await ref.read(clientByIdProvider(invoice.clientId).future);
    if (client == null) return;
    if (!context.mounted) return;
    if (client.email == null || client.email!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El cliente no tiene email configurado')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar factura por email'),
        content: Text(
          'Se enviará la factura ${invoice.visualNumber} a ${client.email}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    try {
      await ref.read(invoiceEmailSendProvider.notifier).send(invoice);

      final gig = await ref.read(gigByIdProvider(invoice.gigId).future);
      if (!context.mounted) return;
      if (gig != null) {
        final newGig = gig.copyWith(status: GigStatus.facturado);
        await _syncGigToCalendar(context, ref, newGig);
      }

      final settings = await ref.read(settingsProvider.future);
      if (settings.notificacionesActivas) {
        await NotificationService.instance.schedulePaymentReminder(
          id: invoice.numero,
          clientName: client.displayName,
          total: invoice.total,
          invoiceNumber: invoice.numero,
          scheduledDate: DateTime.now().add(
            Duration(days: settings.diasRecordatorio),
          ),
        );
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Factura enviada a ${client.email}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        String message;
        try {
          message = e.toString();
        } catch (_) {
          message = 'Error desconocido';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error enviando email: $message')),
        );
      }
    }
  }

  Future<void> _markAs(
    BuildContext context,
    WidgetRef ref,
    InvoiceStatus status,
  ) async {
    final statusLabel = status == InvoiceStatus.enviada ? 'enviada' : 'pagada';

    // Actualizar factura
    await ref.read(invoicesProvider.notifier).updateStatus(invoice.id, status);

    // Actualizar gig asociado
    final gig = await ref.read(gigByIdProvider(invoice.gigId).future);
    if (gig != null) {
      GigStatus newGigStatus;
      if (status == InvoiceStatus.enviada) {
        newGigStatus = GigStatus.facturado;
        // Programar recordatorio
        final settings = await ref.read(settingsProvider.future);
        if (settings.notificacionesActivas) {
          final client = await ref.read(
            clientByIdProvider(invoice.clientId).future,
          );
          if (client != null) {
            await NotificationService.instance.schedulePaymentReminder(
              id: invoice.numero,
              clientName: client.displayName,
              total: invoice.total,
              invoiceNumber: invoice.numero,
              scheduledDate: DateTime.now().add(
                Duration(days: settings.diasRecordatorio),
              ),
            );
          }
        }
      } else {
        newGigStatus = GigStatus.cobrado;
        // Cancelar recordatorio
        await NotificationService.instance.cancelNotification(invoice.numero);
      }

      await ref.read(gigsProvider.notifier).updateStatus(gig.id, newGigStatus);

      // Sincronizar con Google Calendar
      if (!context.mounted) return;
      await _syncGigToCalendar(
        context,
        ref,
        gig.copyWith(status: newGigStatus),
      );
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Factura marcada como $statusLabel')),
      );
    }
  }

  Future<void> _revertStatus(BuildContext context, WidgetRef ref) async {
    InvoiceStatus newStatus;
    GigStatus newGigStatus;
    String statusLabel;

    if (invoice.status == InvoiceStatus.pagada) {
      newStatus = InvoiceStatus.enviada;
      newGigStatus = GigStatus.facturado;
      statusLabel = 'enviada';
    } else {
      newStatus = InvoiceStatus.borrador;
      newGigStatus = GigStatus.facturado;
      statusLabel = 'borrador';
    }

    // Actualizar factura
    await ref
        .read(invoicesProvider.notifier)
        .updateStatus(invoice.id, newStatus);

    // Actualizar gig asociado
    final gig = await ref.read(gigByIdProvider(invoice.gigId).future);
    if (gig != null) {
      await ref.read(gigsProvider.notifier).updateStatus(gig.id, newGigStatus);
      if (!context.mounted) return;
      await _syncGigToCalendar(
        context,
        ref,
        gig.copyWith(status: newGigStatus),
      );
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Factura revertida a $statusLabel')),
      );
    }
  }

  Future<void> _syncGigToCalendar(
    BuildContext context,
    WidgetRef ref,
    Gig gig,
  ) async {
    if (!context.mounted) return;
    final authState = ref.read(googleAuthProvider);
    if (!authState.isSignedIn) return;
    try {
      if (!context.mounted) return;
      final client = await ref.read(clientByIdProvider(gig.clientId).future);
      await GoogleCalendarService().syncGig(
        gig: gig,
        clientName: client?.displayName ?? 'Cliente',
        cachet: gig.cachet,
      );
    } catch (_) {}
  }

  Future<void> _deleteInvoice(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar factura?'),
        content: Text(
          'Se eliminará permanentemente la factura ${invoice.visualNumber}. Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      var deleteFromDrive = false;
      final hasDriveFile = invoice.driveFileId?.trim().isNotEmpty == true;
      if (hasDriveFile) {
        final alsoDrive = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('¿Borrar también en Drive?'),
            content: const Text(
              'El PDF se enviará a la papelera de Drive. '
              'En MisBolos la factura se eliminará igualmente.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('No'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Sí, en Drive también'),
              ),
            ],
          ),
        );
        deleteFromDrive = alsoDrive == true;
      }
      await ref
          .read(invoicesProvider.notifier)
          .remove(invoice.id, deleteFromDrive: deleteFromDrive);

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Factura eliminada')));
        context.pop();
      }
    }
  }

  Future<void> _createRectifyingInvoice(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final reasonController = TextEditingController();
    RectificationReasonType selectedReasonType =
        RectificationReasonType.amountCorrection;
    RectificationType selectedRectificationType =
        RectificationType.substitution;
    int step = 0;

    final result =
        await showDialog<
          ({
            RectificationReasonType reasonType,
            RectificationType rectificationType,
            String description,
          })
        >(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDialogState) {
              final isOther =
                  selectedReasonType == RectificationReasonType.other;

              Widget content;
              switch (step) {
                case 0:
                  content = Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Paso 1 de 3',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<RectificationReasonType>(
                        initialValue: selectedReasonType,
                        decoration: const InputDecoration(
                          labelText: 'Motivo de rectificación',
                        ),
                        items: RectificationReasonType.values
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value.label),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => selectedReasonType = value);
                        },
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'El motivo es obligatorio para generar la rectificativa.',
                        style: TextStyle(fontSize: 12),
                      ),
                      if (isOther) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: reasonController,
                          onChanged: (_) => setDialogState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Descripción del motivo',
                            hintText: 'Explica el motivo concreto',
                          ),
                          minLines: 2,
                          maxLines: 4,
                        ),
                      ],
                    ],
                  );
                  break;
                case 1:
                  content = Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Paso 2 de 3',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => setDialogState(
                          () => selectedRectificationType =
                              RectificationType.substitution,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:
                                selectedRectificationType ==
                                    RectificationType.substitution
                                ? AppColors.primaryLight
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color:
                                  selectedRectificationType ==
                                      RectificationType.substitution
                                  ? AppColors.primary
                                  : AppColors.divider,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Row(
                                children: [
                                  Text(
                                    'Sustitución',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  _RecommendedChip(),
                                ],
                              ),
                              SizedBox(height: 4),
                              Text(
                                'La nueva factura sustituye completamente a la original.',
                              ),
                            ],
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => setDialogState(
                          () => selectedRectificationType =
                              RectificationType.difference,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:
                                selectedRectificationType ==
                                    RectificationType.difference
                                ? AppColors.primaryLight
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color:
                                  selectedRectificationType ==
                                      RectificationType.difference
                                  ? AppColors.primary
                                  : AppColors.divider,
                            ),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Diferencias',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'La rectificativa refleja únicamente la diferencia respecto a la factura original.',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                  break;
                default:
                  content = Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Paso 3 de 3',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text('Factura original: ${invoice.visualNumber}'),
                      Text('Motivo: ${selectedReasonType.label}'),
                      if (selectedReasonType == RectificationReasonType.other &&
                          reasonController.text.trim().isNotEmpty)
                        Text(reasonController.text.trim()),
                      Text(
                        'Tipo: ${selectedRectificationType == RectificationType.difference ? 'Diferencias' : 'Sustitución'}',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Al crearla se generará un borrador independiente con su propia numeración rectificativa.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  );
              }

              final canAdvance =
                  !(step == 0 &&
                      selectedReasonType == RectificationReasonType.other &&
                      reasonController.text.trim().isEmpty);

              return AlertDialog(
                title: const Text('Crear rectificativa'),
                content: SizedBox(
                  width: 520,
                  child: SingleChildScrollView(child: content),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      if (step == 0) {
                        Navigator.pop(ctx);
                      } else {
                        setDialogState(() => step -= 1);
                      }
                    },
                    child: Text(step == 0 ? 'Cancelar' : 'Atrás'),
                  ),
                  if (step < 2)
                    FilledButton(
                      onPressed: canAdvance
                          ? () => setDialogState(() => step += 1)
                          : null,
                      child: const Text('Siguiente'),
                    )
                  else
                    FilledButton(
                      onPressed: () {
                        if (selectedReasonType ==
                                RectificationReasonType.other &&
                            reasonController.text.trim().isEmpty) {
                          return;
                        }
                        final description =
                            selectedReasonType ==
                                    RectificationReasonType.other &&
                                reasonController.text.trim().isEmpty
                            ? ''
                            : reasonController.text.trim();
                        Navigator.pop(ctx, (
                          reasonType: selectedReasonType,
                          rectificationType: selectedRectificationType,
                          description: description.isNotEmpty
                              ? description
                              : selectedReasonType.label,
                        ));
                      },
                      child: const Text('Crear'),
                    ),
                ],
              );
            },
          ),
        );
    reasonController.dispose();
    if (!context.mounted || result == null) return;

    try {
      final rectifying = await ref
          .read(invoicesProvider.notifier)
          .createRectifyingInvoice(
            invoice.id,
            reasonType: result.reasonType,
            reasonDescription: result.description,
            type: result.rectificationType,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Rectificativa ${rectifying.visualNumber} creada'),
        ),
      );
      context.push('/invoice/edit/${rectifying.id}');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}

class _RecommendedChip extends StatelessWidget {
  const _RecommendedChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'Recomendado',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _EmailLogSection extends StatelessWidget {
  final List<InvoiceEmailLog> logs;

  const _EmailLogSection({required this.logs});

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) return const SizedBox.shrink();
    final latest = logs.first;
    final color = switch (latest.status) {
      InvoiceEmailStatus.sent => AppColors.success,
      InvoiceEmailStatus.failed => AppColors.error,
      InvoiceEmailStatus.pending => AppColors.warning,
    };
    final label = switch (latest.status) {
      InvoiceEmailStatus.sent => 'Enviada por email',
      InvoiceEmailStatus.failed => 'Email fallido',
      InvoiceEmailStatus.pending => 'Email pendiente',
    };

    return Card(
      child: ListTile(
        leading: Icon(Icons.email_outlined, color: color),
        title: Text(label),
        subtitle: Text(
          latest.status == InvoiceEmailStatus.failed &&
                  latest.errorMessage != null
              ? latest.errorMessage!
              : latest.recipientEmail,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          '${logs.length}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
