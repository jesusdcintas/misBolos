import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import '../models/invoice.dart';
import '../models/client.dart';
import '../models/app_settings.dart';
import '../models/gig.dart';
import '../models/pdf_theme.dart';
import '../providers/stats_provider.dart';

class PdfService {
  static const _white = PdfColors.white;

  static pw.Font? _regularFont;
  static pw.Font? _boldFont;

  static Future<void> _loadFonts() async {
    if (_regularFont == null) {
      final regularData = await rootBundle.load(
        'assets/fonts/Roboto-Regular.ttf',
      );
      _regularFont = pw.Font.ttf(regularData);
    }
    if (_boldFont == null) {
      final boldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
      _boldFont = pw.Font.ttf(boldData);
    }
  }

  Future<File> generateInvoicePdf({
    required Invoice invoice,
    required Client client,
    required AppSettings settings,
  }) async {
    await _loadFonts();

    final pdf = pw.Document();
    final theme = PdfTheme.fromName(settings.pdfTheme);
    final primaryColor = theme.primaryColor;
    final headerBg = theme.headerBg;
    final rowAlt = theme.rowAlt;

    pw.ImageProvider? logoImage;
    if (settings.logoPath.isNotEmpty) {
      final logoFile = File(settings.logoPath);
      if (await logoFile.exists()) {
        final bytes = await logoFile.readAsBytes();
        logoImage = pw.MemoryImage(bytes);
      }
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(56.7), // ~2cm
        theme: pw.ThemeData.withFont(base: _regularFont, bold: _boldFont),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header: Logo + FACTURA
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Expanded(
                    child: pw.Align(
                      alignment: pw.Alignment.centerLeft,
                      child: logoImage != null
                          ? pw.Image(
                              logoImage,
                              height: settings.logoSize,
                              fit: pw.BoxFit.contain,
                            )
                          : pw.SizedBox(height: settings.logoSize),
                    ),
                  ),
                  pw.Text(
                    'FACTURA',
                    style: pw.TextStyle(
                      fontSize: 36,
                      fontWeight: pw.FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Divider(color: PdfColors.grey400, thickness: 1),
              pw.SizedBox(height: 8),

              // Emisor / Facturar a
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 2,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'EMISOR',
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                        pw.SizedBox(height: 6),
                        pw.Text(
                          settings.emisorNombre,
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                        pw.Text(
                          settings.emisorNIF,
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                        if (settings.emisorDireccion.isNotEmpty)
                          pw.Text(
                            settings.emisorDireccion,
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                        pw.Text(
                          [
                            settings.emisorCiudad,
                            if (settings.emisorProvincia.isNotEmpty)
                              settings.emisorProvincia,
                            if (settings.emisorCodigoPostal.isNotEmpty)
                              settings.emisorCodigoPostal,
                          ].where((s) => s.isNotEmpty).join(', '),
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                        if (settings.emisorEmail.isNotEmpty)
                          pw.Text(
                            settings.emisorEmail,
                            style: pw.TextStyle(
                              fontSize: 10,
                              color: PdfColors.blue800,
                            ),
                          ),
                        if (settings.emisorTelefono.isNotEmpty)
                          pw.Text(
                            settings.emisorTelefono,
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 40),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'FACTURAR A',
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                        pw.SizedBox(height: 6),
                        pw.Text(
                          client.nombre,
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                        pw.Text(
                          client.cifNif,
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                        pw.Text(
                          client.direccion,
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                        pw.Text(
                          [
                            client.ciudad,
                            if (client.provincia.isNotEmpty) client.provincia,
                            if (client.codigoPostal.isNotEmpty)
                              client.codigoPostal,
                          ].where((s) => s.isNotEmpty).join(', '),
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                        if (client.email != null && client.email!.isNotEmpty)
                          pw.Text(
                            client.email!,
                            style: pw.TextStyle(
                              fontSize: 10,
                              color: PdfColors.blue800,
                            ),
                          ),
                        if (client.telefono != null &&
                            client.telefono!.isNotEmpty)
                          pw.Text(
                            client.telefono!,
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),

              // Fecha, nº factura, IBAN
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 2,
                    child: pw.Row(
                      children: [
                        pw.Text(
                          'Fecha:       ',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                        pw.Text(
                          '${invoice.fecha.day}/${invoice.fecha.month}/${invoice.fecha.year}',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 40),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Row(
                      children: [
                        pw.Text(
                          'N.º de factura',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                        pw.SizedBox(width: 30),
                        pw.Text(
                          '${invoice.numero}',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                children: [
                  pw.Text(
                    'Información de pago: ',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                  pw.Text(
                    settings.iban,
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

              // Table
              _buildInvoiceTable(invoice, headerBg, rowAlt),
              pw.SizedBox(height: 12),

              // Totals
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.SizedBox(
                          width: 180,
                          child: pw.Text(
                            'Subtotal',
                            textAlign: pw.TextAlign.right,
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                        ),
                        pw.SizedBox(width: 20),
                        pw.SizedBox(
                          width: 80,
                          child: pw.Text(
                            _formatCurrency(invoice.subtotal),
                            textAlign: pw.TextAlign.right,
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.SizedBox(
                          width: 180,
                          child: pw.Text(
                            'Impuesto sobre las ventas al ${(invoice.ivaRate * 100).round()}%',
                            textAlign: pw.TextAlign.right,
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                        ),
                        pw.SizedBox(width: 20),
                        pw.SizedBox(
                          width: 80,
                          child: pw.Text(
                            _formatCurrency(invoice.ivaAmount),
                            textAlign: pw.TextAlign.right,
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                    if (invoice.irpfRate > 0) ...[
                      pw.SizedBox(height: 4),
                      pw.Row(
                        mainAxisSize: pw.MainAxisSize.min,
                        children: [
                          pw.SizedBox(
                            width: 180,
                            child: pw.Text(
                              'Retención IRPF (${(invoice.irpfRate * 100).toStringAsFixed(0)}%)',
                              textAlign: pw.TextAlign.right,
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                          ),
                          pw.SizedBox(width: 20),
                          pw.SizedBox(
                            width: 80,
                            child: pw.Text(
                              '-${_formatCurrency(invoice.irpfAmount)}',
                              textAlign: pw.TextAlign.right,
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                          ),
                        ],
                      ),
                    ],
                    pw.SizedBox(height: 8),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: pw.BoxDecoration(
                        color: headerBg,
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: pw.Row(
                        mainAxisSize: pw.MainAxisSize.min,
                        children: [
                          pw.SizedBox(
                            width: 100,
                            child: pw.Text(
                              'TOTAL',
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold,
                                color: _white,
                              ),
                            ),
                          ),
                          pw.SizedBox(width: 20),
                          pw.SizedBox(
                            width: 80,
                            child: pw.Text(
                              _formatCurrency(invoice.total),
                              textAlign: pw.TextAlign.right,
                              style: pw.TextStyle(
                                fontSize: 14,
                                fontWeight: pw.FontWeight.bold,
                                color: _white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/factura_${invoice.numero}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static pw.Widget _buildInvoiceTable(
    Invoice invoice,
    PdfColor headerBg,
    PdfColor rowAlt,
  ) {
    final items = invoice.items;

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(1),
        1: const pw.FlexColumnWidth(3),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FlexColumnWidth(2),
      },
      children: [
        // Header
        pw.TableRow(
          decoration: pw.BoxDecoration(color: headerBg),
          children: [
            _headerCell('Cantidad'),
            _headerCell('Descripción'),
            _headerCell('Precio por unidad'),
            _headerCell('Total de línea'),
          ],
        ),
        // Data rows only (no empty rows)
        for (int i = 0; i < items.length; i++)
          pw.TableRow(
            decoration: pw.BoxDecoration(color: i % 2 == 1 ? rowAlt : _white),
            children: [
              _dataCell('${items[i].cantidad}', pw.TextAlign.center),
              _dataCell(items[i].descripcion, pw.TextAlign.left),
              _dataCell(
                _formatCurrency(items[i].precioUnitario),
                pw.TextAlign.right,
              ),
              _dataCell(
                _formatCurrency(items[i].totalLinea),
                pw.TextAlign.right,
              ),
            ],
          ),
      ],
    );
  }

  static pw.Widget _headerCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          color: _white,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  static pw.Widget _dataCell(String text, pw.TextAlign align) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 10),
        textAlign: align,
      ),
    );
  }

  static String _formatCurrency(double amount) {
    final formatted = amount.toStringAsFixed(2).replaceAll('.', ',');
    return '$formatted €';
  }

  // ================== RESUMEN FINANCIERO ==================

  Future<File> generateSummaryPdf({
    required FinancialPeriodSummary summary,
  }) async {
    await _loadFonts();

    final pdf = pw.Document();
    const primary = PdfColor.fromInt(0xFF1B2A4A);
    const success = PdfColor.fromInt(0xFF1B8A56);
    const warning = PdfColor.fromInt(0xFFB7680A);
    const purple = PdfColor.fromInt(0xFF5B2C8D);
    const grey = PdfColors.grey600;
    const headerBg = PdfColor.fromInt(0xFF1B2A4A);
    const rowAlt = PdfColor.fromInt(0xFFF5F6FA);
    final dateFormat = DateFormat('dd/MM/yyyy');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        theme: pw.ThemeData.withFont(base: _regularFont, bold: _boldFont),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'RESUMEN FINANCIERO',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: primary,
                  ),
                ),
                pw.Text(
                  summary.period.label,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: primary,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Generado el ${dateFormat.format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 9, color: grey),
            ),
            pw.Divider(color: primary, thickness: 2),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (context) {
          final widgets = <pw.Widget>[];

          // === RESUMEN GENERAL ===
          widgets.add(_sectionTitle('Resumen General', primary));
          widgets.add(pw.SizedBox(height: 8));

          widgets.add(
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                children: [
                  _summaryRow('Bolos', '${summary.numBolos}'),
                  _summaryRow(
                    'Facturas cobradas',
                    '${summary.numFacturasPagadas}',
                  ),
                  _summaryRow(
                    'Facturas pendientes',
                    '${summary.pendienteCount}',
                  ),
                  pw.Divider(color: PdfColors.grey300),
                  _summaryRow(
                    'Cobrado (facturas)',
                    _formatCurrency(summary.cobradoFacturas),
                    color: success,
                  ),
                  if (summary.cobradoHistorico > 0)
                    _summaryRow(
                      'Cobrado (histórico)',
                      _formatCurrency(summary.cobradoHistorico),
                      color: success,
                    ),
                  _summaryRow(
                    'Pendiente',
                    _formatCurrency(summary.pendiente),
                    color: warning,
                  ),
                  _summaryRow(
                    'Cobrado en B',
                    _formatCurrency(summary.cobradoEnB),
                    color: purple,
                  ),
                  if (summary.pendienteEnB > 0)
                    _summaryRow(
                      'Pendiente en B',
                      _formatCurrency(summary.pendienteEnB),
                      color: purple,
                    ),
                  if (summary.previstoEnB > 0)
                    _summaryRow(
                      'Previsto en B',
                      _formatCurrency(summary.previstoEnB),
                      color: purple,
                    ),
                  if (summary.previsto > 0)
                    _summaryRow(
                      'Previsto',
                      _formatCurrency(summary.previsto),
                      color: primary,
                    ),
                  pw.Divider(color: PdfColors.grey300),
                  _summaryRow(
                    'Acumulado',
                    _formatCurrency(summary.acumuladoTotal),
                    color: success,
                    bold: true,
                  ),
                  _summaryRow(
                    'Total previsto',
                    _formatCurrency(summary.totalPrevistoGlobal),
                    color: primary,
                    bold: true,
                  ),
                ],
              ),
            ),
          );

          widgets.add(pw.SizedBox(height: 16));

          // === IVA TRIMESTRAL ===
          if (summary.ivaQuarters.isNotEmpty) {
            widgets.add(_sectionTitle('IVA Trimestral', primary));
            widgets.add(pw.SizedBox(height: 8));

            for (final q in summary.ivaQuarters) {
              widgets.add(
                pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 8),
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'T${q.quarter} ${q.year}',
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 13,
                              color: primary,
                            ),
                          ),
                          pw.Text(
                            'IVA: ${_formatCurrency(q.ivaTotal)}',
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Declaración: ${dateFormat.format(q.declarationDate)}',
                        style: const pw.TextStyle(fontSize: 9, color: grey),
                      ),
                      if (q.invoices.isNotEmpty) ...[
                        pw.SizedBox(height: 8),
                        pw.Table(
                          border: pw.TableBorder.all(
                            color: PdfColors.grey300,
                            width: 0.5,
                          ),
                          columnWidths: {
                            0: const pw.FlexColumnWidth(1),
                            1: const pw.FlexColumnWidth(3),
                            2: const pw.FlexColumnWidth(2),
                            3: const pw.FlexColumnWidth(2),
                            4: const pw.FlexColumnWidth(2),
                          },
                          children: [
                            pw.TableRow(
                              decoration: const pw.BoxDecoration(
                                color: headerBg,
                              ),
                              children: [
                                _headerCell('Nº'),
                                _headerCell('Cliente'),
                                _headerCell('Fecha'),
                                _headerCell('Base'),
                                _headerCell('IVA'),
                              ],
                            ),
                            for (int i = 0; i < q.invoices.length; i++)
                              pw.TableRow(
                                decoration: pw.BoxDecoration(
                                  color: i % 2 == 1 ? rowAlt : _white,
                                ),
                                children: [
                                  _dataCell(
                                    '#${q.invoices[i].numero}',
                                    pw.TextAlign.center,
                                  ),
                                  _dataCell(
                                    q.invoices[i].clientName,
                                    pw.TextAlign.left,
                                  ),
                                  _dataCell(
                                    dateFormat.format(q.invoices[i].fecha),
                                    pw.TextAlign.center,
                                  ),
                                  _dataCell(
                                    _formatCurrency(q.invoices[i].base),
                                    pw.TextAlign.right,
                                  ),
                                  _dataCell(
                                    _formatCurrency(q.invoices[i].iva),
                                    pw.TextAlign.right,
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }

            widgets.add(pw.SizedBox(height: 16));
          }

          // === DESGLOSE POR PERÍODOS ===
          if (summary.subPeriods.isNotEmpty) {
            widgets.add(_sectionTitle('Desglose por Períodos', primary));
            widgets.add(pw.SizedBox(height: 8));

            widgets.add(
              pw.Table(
                border: pw.TableBorder.all(
                  color: PdfColors.grey300,
                  width: 0.5,
                ),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2),
                  1: const pw.FlexColumnWidth(1),
                  2: const pw.FlexColumnWidth(2),
                  3: const pw.FlexColumnWidth(2),
                  4: const pw.FlexColumnWidth(2),
                  5: const pw.FlexColumnWidth(2),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: headerBg),
                    children: [
                      _headerCell('Período'),
                      _headerCell('Bolos'),
                      _headerCell('Cobrado'),
                      _headerCell('Pendiente'),
                      _headerCell('En B'),
                      _headerCell('T. Previsto'),
                    ],
                  ),
                  for (int i = 0; i < summary.subPeriods.length; i++)
                    pw.TableRow(
                      decoration: pw.BoxDecoration(
                        color: i % 2 == 1 ? rowAlt : _white,
                      ),
                      children: [
                        _dataCell(
                          summary.subPeriods[i].label,
                          pw.TextAlign.center,
                        ),
                        _dataCell(
                          '${summary.subPeriods[i].numBolos}',
                          pw.TextAlign.center,
                        ),
                        _dataCell(
                          _formatCurrency(summary.subPeriods[i].cobradoOficial),
                          pw.TextAlign.right,
                        ),
                        _dataCell(
                          _formatCurrency(summary.subPeriods[i].pendiente),
                          pw.TextAlign.right,
                        ),
                        _dataCell(
                          _formatCurrency(summary.subPeriods[i].cobradoEnB),
                          pw.TextAlign.right,
                        ),
                        _dataCell(
                          _formatCurrency(
                            summary.subPeriods[i].totalPrevistoGlobal,
                          ),
                          pw.TextAlign.right,
                        ),
                      ],
                    ),
                ],
              ),
            );

            widgets.add(pw.SizedBox(height: 16));
          }

          // === DETALLE DE BOLOS ===
          final allGigs = summary.subPeriods.expand((sp) => sp.gigs).toList();
          if (allGigs.isNotEmpty) {
            widgets.add(_sectionTitle('Detalle de Bolos', primary));
            widgets.add(pw.SizedBox(height: 8));

            widgets.add(
              pw.Table(
                border: pw.TableBorder.all(
                  color: PdfColors.grey300,
                  width: 0.5,
                ),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2),
                  1: const pw.FlexColumnWidth(3),
                  2: const pw.FlexColumnWidth(2),
                  3: const pw.FlexColumnWidth(2),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: headerBg),
                    children: [
                      _headerCell('Fecha'),
                      _headerCell('Cliente'),
                      _headerCell('Importe'),
                      _headerCell('Estado'),
                    ],
                  ),
                  for (int i = 0; i < allGigs.length; i++)
                    pw.TableRow(
                      decoration: pw.BoxDecoration(
                        color: i % 2 == 1 ? rowAlt : _white,
                      ),
                      children: [
                        _dataCell(
                          dateFormat.format(allGigs[i].fecha),
                          pw.TextAlign.center,
                        ),
                        _dataCell(allGigs[i].clientName, pw.TextAlign.left),
                        _dataCell(
                          _formatCurrency(allGigs[i].importe),
                          pw.TextAlign.right,
                        ),
                        _dataCell(allGigs[i].status.label, pw.TextAlign.center),
                      ],
                    ),
                ],
              ),
            );
          }

          return widgets;
        },
      ),
    );

    final dir = await getTemporaryDirectory();
    final safeName = summary.period.label
        .replaceAll(' ', '_')
        .replaceAll('/', '-');
    final file = File('${dir.path}/resumen_$safeName.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static pw.Widget _sectionTitle(String text, PdfColor color) {
    return pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 14,
        fontWeight: pw.FontWeight.bold,
        color: color,
      ),
    );
  }

  static pw.Widget _summaryRow(
    String label,
    String value, {
    PdfColor? color,
    bool bold = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: bold ? pw.FontWeight.bold : null,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: bold ? pw.FontWeight.bold : null,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
