import 'dart:typed_data';
import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/client.dart';
import '../models/gig.dart';
import '../models/invoice.dart';
import '../repositories/invoice_repository.dart';

class ImportColumn {
  final int index;
  final String header;
  final List<String> sampleValues;

  ImportColumn({
    required this.index,
    required this.header,
    required this.sampleValues,
  });
}

enum ColumnRole {
  fecha('Fecha del bolo', true),
  cliente('Nombre del cliente/venue', true),
  importeFacturable('Importe facturable', false),
  importeEnB('Importe en B', false),
  numeroFactura('Número de factura', false),
  estado('Estado', false),
  ignorar('— Ignorar —', false);

  final String label;
  final bool required;
  const ColumnRole(this.label, this.required);
}

enum ImportDefaultStatus {
  cobrado('Cobrado'),
  pendienteCobro('Pendiente'),
  borrador('Borrador');

  final String label;
  const ImportDefaultStatus(this.label);
}

class ImportMapping {
  final Map<int, ColumnRole> columnRoles;
  final int year;
  final ImportDefaultStatus defaultStatus;
  final bool createClients;

  ImportMapping({
    required this.columnRoles,
    required this.year,
    this.defaultStatus = ImportDefaultStatus.cobrado,
    this.createClients = true,
  });
}

class ImportPreview {
  final int bolosFacturables;
  final int bolosEnB;
  final int clientesNuevos;
  final double totalImporte;
  final DateTime? fechaMin;
  final DateTime? fechaMax;

  ImportPreview({
    required this.bolosFacturables,
    required this.bolosEnB,
    required this.clientesNuevos,
    required this.totalImporte,
    this.fechaMin,
    this.fechaMax,
  });
}

class ImportResult {
  final int imported;
  final int skipped;
  final int clientsCreated;
  final String? error;

  ImportResult({
    required this.imported,
    required this.skipped,
    required this.clientsCreated,
    this.error,
  });
}

class XlsxRepairPreview {
  final int year;
  final int candidates;
  final double totalActual;
  final double totalCorregido;
  final double totalBase;
  final double totalIva;

  XlsxRepairPreview({
    required this.year,
    required this.candidates,
    required this.totalActual,
    required this.totalCorregido,
    required this.totalBase,
    required this.totalIva,
  });
}

class _ParsedRow {
  final DateTime fecha;
  final String clienteName;
  final double? importeFacturable;
  final double? importeEnB;
  final int? numeroFactura;

  _ParsedRow({
    required this.fecha,
    required this.clienteName,
    this.importeFacturable,
    this.importeEnB,
    this.numeroFactura,
  });
}

class ImportService {
  ImportService._();
  static const double _ivaRate = 0.21;

  /// Parse an Excel file and return rows as `List<List<String>>`
  static List<List<String>> parseExcel(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables[excel.tables.keys.first]!;
    final rows = <List<String>>[];
    for (final row in sheet.rows) {
      rows.add(row.map((cell) => cell?.value?.toString() ?? '').toList());
    }
    return rows;
  }

  /// Parse a CSV file and return rows as `List<List<String>>`
  static List<List<String>> parseCsv(String content, {String separator = ','}) {
    return const CsvToListConverter()
        .convert(content, fieldDelimiter: separator, eol: '\n')
        .map((row) => row.map((cell) => cell.toString()).toList())
        .toList();
  }

  /// Detect columns from parsed rows
  static List<ImportColumn> detectColumns(List<List<String>> rows) {
    if (rows.isEmpty) return [];

    // Use first row as headers
    final headerRow = rows.first;
    final dataRows = rows.length > 1
        ? rows.sublist(1, (rows.length).clamp(0, 6))
        : <List<String>>[];

    final columns = <ImportColumn>[];
    for (int i = 0; i < headerRow.length; i++) {
      columns.add(
        ImportColumn(
          index: i,
          header: headerRow[i].trim().isEmpty
              ? 'Col ${String.fromCharCode(65 + i)}'
              : headerRow[i].trim(),
          sampleValues: dataRows
              .where((r) => i < r.length)
              .map((r) => r[i].trim())
              .where((v) => v.isNotEmpty)
              .take(4)
              .toList(),
        ),
      );
    }
    return columns;
  }

  /// Try to auto-detect column mapping for Jesús's Excel format
  static Map<int, ColumnRole>? autoDetectJesusFormat(List<List<String>> rows) {
    if (rows.isEmpty || rows.first.length < 7) return null;

    final dataRows = rows.length > 1
        ? rows.sublist(1, (rows.length).clamp(0, 10))
        : <List<String>>[];
    if (dataRows.isEmpty) return null;

    // Jesús format: Col C(2)=nº factura, D(3)=fecha, E(4)=venue, F(5)=importe A, G(6)=importe B
    bool colCNumeric = dataRows.any((r) => r.length > 2 && _isNumeric(r[2]));
    bool colDDate = dataRows.any(
      (r) => r.length > 3 && _tryParseDate(r[3]) != null,
    );
    bool colEText = dataRows.any(
      (r) => r.length > 4 && r[4].trim().isNotEmpty && !_isNumeric(r[4]),
    );
    bool colFNumeric = dataRows.any((r) => r.length > 5 && _isNumeric(r[5]));

    if (colDDate && colEText && (colCNumeric || colFNumeric)) {
      return {
        2: ColumnRole.numeroFactura,
        3: ColumnRole.fecha,
        4: ColumnRole.cliente,
        5: ColumnRole.importeFacturable,
        6: ColumnRole.importeEnB,
      };
    }
    return null;
  }

  /// Compute preview stats from mapped data
  static Future<ImportPreview> computePreview(
    List<List<String>> rows,
    ImportMapping mapping,
    List<Client> existingClients,
  ) async {
    final parsed = _parseRows(rows, mapping);
    final existingNames = <String>{};
    for (final c in existingClients) {
      existingNames.add(c.nombre.toLowerCase());
      if (c.alias.isNotEmpty) existingNames.add(c.alias.toLowerCase());
      for (final a in c.aliases) {
        existingNames.add(a.toLowerCase());
      }
    }

    int facturables = 0;
    int enB = 0;
    double total = 0;
    DateTime? minDate;
    DateTime? maxDate;
    final newClientNames = <String>{};

    for (final row in parsed) {
      if (row.importeEnB != null &&
          row.importeEnB! > 0 &&
          (row.importeFacturable == null || row.importeFacturable == 0)) {
        enB++;
        total += row.importeEnB!;
      } else {
        facturables++;
        total += row.importeFacturable ?? 0;
      }

      if (minDate == null || row.fecha.isBefore(minDate)) minDate = row.fecha;
      if (maxDate == null || row.fecha.isAfter(maxDate)) maxDate = row.fecha;

      final normalized = _capitalizeVenue(row.clienteName).toLowerCase();
      if (!existingNames.contains(normalized)) {
        newClientNames.add(normalized);
      }
    }

    return ImportPreview(
      bolosFacturables: facturables,
      bolosEnB: enB,
      clientesNuevos: newClientNames.length,
      totalImporte: total,
      fechaMin: minDate,
      fechaMax: maxDate,
    );
  }

  /// Execute the import in a single transaction
  static Future<ImportResult> executeImport(
    List<List<String>> rows,
    ImportMapping mapping,
    List<Client> existingClients, {
    void Function(int current, int total)? onProgress,
  }) async {
    final parsed = _parseRows(rows, mapping);
    if (parsed.isEmpty) {
      return ImportResult(
        imported: 0,
        skipped: 0,
        clientsCreated: 0,
        error: 'No se encontraron filas válidas',
      );
    }

    final db = await DatabaseHelper.instance.database;
    int imported = 0;
    int skipped = 0;
    int clientsCreated = 0;

    // Build client lookup map (case-insensitive, includes aliases)
    final clientMap = <String, String>{};
    for (final c in existingClients) {
      clientMap[c.nombre.toLowerCase()] = c.id;
      if (c.alias.isNotEmpty) {
        clientMap[c.alias.toLowerCase()] = c.id;
      }
      for (final a in c.aliases) {
        clientMap[a.toLowerCase()] = c.id;
      }
    }

    try {
      await db.transaction((txn) async {
        Future<int> nextInvoiceNumberForYear(int year) async {
          final result = await txn.rawQuery(
            '''
            SELECT MAX(numero) as max_num
            FROM invoices
            WHERE CAST(strftime('%Y', fecha) AS INTEGER) = ?
            ''',
            [year],
          );
          final maxNum = result.first['max_num'] as int?;
          return (maxNum ?? 0) + 1;
        }

        for (int i = 0; i < parsed.length; i++) {
          final row = parsed[i];
          onProgress?.call(i + 1, parsed.length);

          final venueName = _capitalizeVenue(row.clienteName);
          final venueKey = venueName.toLowerCase();

          // Get or create client
          String clientId;
          if (clientMap.containsKey(venueKey)) {
            clientId = clientMap[venueKey]!;
          } else if (mapping.createClients) {
            final newClient = Client(nombre: venueName);
            await txn.insert('clients', newClient.toMap());
            clientMap[venueKey] = newClient.id;
            clientId = newClient.id;
            clientsCreated++;
          } else {
            skipped++;
            continue;
          }

          // Determine if this is a B-type gig
          final isEnB =
              row.importeEnB != null &&
              row.importeEnB! > 0 &&
              (row.importeFacturable == null || row.importeFacturable == 0);

          final totalA = row.importeFacturable ?? 0;
          final totalB = row.importeEnB ?? 0;
          final importesA = _calculateOfficialAmountsFromTotal(totalA);
          final cachet = isEnB ? totalB : importesA.base;

          // Determine status
          GigStatus status;
          if (isEnB) {
            status = GigStatus.cobradoB;
          } else {
            switch (mapping.defaultStatus) {
              case ImportDefaultStatus.cobrado:
                status = GigStatus.cobrado;
              case ImportDefaultStatus.pendienteCobro:
                status = GigStatus.facturado;
              case ImportDefaultStatus.borrador:
                status = GigStatus.facturado;
            }
          }

          // Check for duplicates: same date + client + amount
          final dateStr = row.fecha.toIso8601String();
          final existing = await txn.query(
            'gigs',
            where: 'fecha = ? AND client_id = ? AND cachet = ?',
            whereArgs: [dateStr, clientId, cachet],
          );

          if (existing.isNotEmpty) {
            skipped++;
            continue;
          }

          final gig = Gig(
            fecha: row.fecha,
            clientId: clientId,
            cachet: cachet,
            facturable: !isEnB,
            status: status,
            notas: isEnB ? 'XLSX_IMPORT:B' : 'XLSX_IMPORT:A',
          );

          await txn.insert('gigs', gig.toMap());

          if (!isEnB) {
            final desiredInvoiceStatus = switch (status) {
              GigStatus.facturado => mapping.defaultStatus ==
                      ImportDefaultStatus.borrador
                  ? InvoiceStatus.borrador
                  : InvoiceStatus.enviada,
              GigStatus.cobrado => InvoiceStatus.pagada,
              _ => InvoiceStatus.borrador,
            };

            var invoiceNumber = row.numeroFactura;
            if (invoiceNumber != null) {
              final existingInvoiceNumber = await txn.query(
                'invoices',
                columns: ['id'],
                where:
                    "numero = ? AND CAST(strftime('%Y', fecha) AS INTEGER) = ?",
                whereArgs: [invoiceNumber, row.fecha.year],
                limit: 1,
              );
              if (existingInvoiceNumber.isNotEmpty) {
                skipped++;
                continue;
              }
            }
            invoiceNumber ??= await nextInvoiceNumberForYear(row.fecha.year);

            final invoice = Invoice(
              numero: invoiceNumber,
              fecha: row.fecha,
              clientId: clientId,
              gigId: gig.id,
              items: [
                InvoiceLineItem(
                  cantidad: 1,
                  descripcion: venueName.toUpperCase(),
                  precioUnitario: importesA.base,
                ),
              ],
              subtotal: importesA.base,
              ivaRate: _ivaRate,
              ivaAmount: importesA.iva,
              total: importesA.total,
              status: desiredInvoiceStatus,
            );

            await txn.insert('invoices', invoice.toMap());
            await txn.insert('invoice_number_changes', {
              'id': const Uuid().v4(),
              'invoice_id': invoice.id,
              'user_id': null,
              'old_number': null,
              'new_number': invoice.numero,
              'source': InvoiceNumberChangeSource.createInvoice,
              'reason': 'import_excel_create_invoice',
              'created_at': DateTime.now().toIso8601String(),
            });
            await txn.update(
              'gigs',
              {'invoice_id': invoice.id},
              where: 'id = ?',
              whereArgs: [gig.id],
            );
          }

          imported++;
        }
      });
    } catch (e) {
      return ImportResult(
        imported: 0,
        skipped: 0,
        clientsCreated: 0,
        error: 'Error durante la importación: $e',
      );
    }

    return ImportResult(
      imported: imported,
      skipped: skipped,
      clientsCreated: clientsCreated,
    );
  }

  // --- Private helpers ---

  static List<_ParsedRow> _parseRows(
    List<List<String>> rows,
    ImportMapping mapping,
  ) {
    // Determine column indices from mapping
    int? fechaCol, clienteCol, importeACol, importeBCol, numFacturaCol;
    for (final entry in mapping.columnRoles.entries) {
      switch (entry.value) {
        case ColumnRole.fecha:
          fechaCol = entry.key;
        case ColumnRole.cliente:
          clienteCol = entry.key;
        case ColumnRole.importeFacturable:
          importeACol = entry.key;
        case ColumnRole.importeEnB:
          importeBCol = entry.key;
        case ColumnRole.numeroFactura:
          numFacturaCol = entry.key;
        default:
          break;
      }
    }

    if (fechaCol == null || clienteCol == null) return [];

    final parsed = <_ParsedRow>[];
    // Skip header row
    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (fechaCol >= row.length || clienteCol >= row.length) continue;

      final dateStr = row[fechaCol].trim();
      final clienteStr = row[clienteCol].trim();
      if (dateStr.isEmpty || clienteStr.isEmpty) continue;

      DateTime? fecha = _tryParseDate(dateStr);
      // If year needs override
      if (fecha != null) {
        fecha = DateTime(mapping.year, fecha.month, fecha.day);
      } else {
        continue; // skip rows with unparseable dates
      }

      double? importeA;
      if (importeACol != null && importeACol < row.length) {
        importeA = _tryParseDouble(row[importeACol]);
      }

      double? importeB;
      if (importeBCol != null && importeBCol < row.length) {
        importeB = _tryParseDouble(row[importeBCol]);
      }

      // Skip rows with no amounts at all
      if ((importeA == null || importeA == 0) &&
          (importeB == null || importeB == 0)) {
        continue;
      }

      int? numFactura;
      if (numFacturaCol != null && numFacturaCol < row.length) {
        numFactura = int.tryParse(row[numFacturaCol].trim());
      }

      parsed.add(
        _ParsedRow(
          fecha: fecha,
          clienteName: clienteStr,
          importeFacturable: importeA,
          importeEnB: importeB,
          numeroFactura: numFactura,
        ),
      );
    }

    return parsed;
  }

  static DateTime? _tryParseDate(String s) {
    s = s.trim();
    if (s.isEmpty) return null;

    // Try common date formats
    final formats = [
      DateFormat('dd/MM/yyyy'),
      DateFormat('d/M/yyyy'),
      DateFormat('dd-MM-yyyy'),
      DateFormat('yyyy-MM-dd'),
      DateFormat('dd/MM/yy'),
      DateFormat('d/M/yy'),
    ];

    for (final fmt in formats) {
      try {
        return fmt.parseStrict(s);
      } catch (_) {}
    }

    // Try DateTime.tryParse as fallback (ISO 8601)
    return DateTime.tryParse(s);
  }

  static double? _tryParseDouble(String s) {
    s = s.trim().replaceAll('€', '').replaceAll(' ', '');
    if (s.isEmpty) return null;
    // Handle European format: 1.234,56 → 1234.56
    if (s.contains(',') && s.contains('.')) {
      s = s.replaceAll('.', '').replaceAll(',', '.');
    } else if (s.contains(',')) {
      s = s.replaceAll(',', '.');
    }
    return double.tryParse(s);
  }

  static bool _isNumeric(String s) {
    return _tryParseDouble(s) != null;
  }

  static String _capitalizeVenue(String name) {
    name = name.trim();
    if (name.isEmpty) return name;
    // If all uppercase, capitalize properly
    if (name == name.toUpperCase() && name.length > 2) {
      return name
          .split(' ')
          .map((word) {
            if (word.isEmpty) return word;
            return word[0].toUpperCase() + word.substring(1).toLowerCase();
          })
          .join(' ');
    }
    // Otherwise just capitalize first letter
    return name[0].toUpperCase() + name.substring(1);
  }

  static Future<XlsxRepairPreview> previewXlsxOfficialRepair({
    required int year,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await _xlsxOfficialRows(db, year);
    var totalActual = 0.0;
    var totalCorregido = 0.0;
    var totalBase = 0.0;
    var totalIva = 0.0;
    for (final row in rows) {
      final totalActualFila = (row['total'] as num?)?.toDouble() ?? 0;
      if (totalActualFila <= 0) continue;
      final fixed = _calculateXlsxRepairAmounts(totalActualFila);
      totalActual += totalActualFila;
      totalCorregido += fixed.totalCorregido;
      totalBase += fixed.base;
      totalIva += fixed.iva;
    }
    return XlsxRepairPreview(
      year: year,
      candidates: rows.length,
      totalActual: _round2(totalActual),
      totalCorregido: _round2(totalCorregido),
      totalBase: _round2(totalBase),
      totalIva: _round2(totalIva),
    );
  }

  static Future<int> applyXlsxOfficialRepair({required int year}) async {
    final db = await DatabaseHelper.instance.database;
    return db.transaction((txn) async {
      final rows = await _xlsxOfficialRows(txn, year);
      var updated = 0;
      for (final row in rows) {
        final invoiceId = row['id']?.toString();
        final totalActual = (row['total'] as num?)?.toDouble();
        if (invoiceId == null || totalActual == null || totalActual <= 0) {
          continue;
        }

        final fixed = _calculateXlsxRepairAmounts(totalActual);
        final itemsRaw = row['items']?.toString();
        final patchedItems = _patchItemsBase(itemsRaw, fixed.base);

        await txn.update(
          'invoices',
          {
            'subtotal': fixed.base,
            'iva_rate': _ivaRate,
            'iva_amount': fixed.iva,
            'total': fixed.totalCorregido,
            if (patchedItems != null) 'items': patchedItems,
          },
          where: 'id = ?',
          whereArgs: [invoiceId],
        );

        await txn.update(
          'gigs',
          {'cachet': fixed.base},
          where: 'id = ?',
          whereArgs: [row['gig_id']],
        );
        updated++;
      }
      return updated;
    });
  }

  static Future<List<Map<String, Object?>>> _xlsxOfficialRows(
    DatabaseExecutor db,
    int year,
  ) {
    return db.rawQuery(
      '''
      SELECT i.id, i.gig_id, i.total, i.items
      FROM invoices i
      JOIN gigs g ON g.id = i.gig_id
      WHERE g.facturable = 1
        AND g.notas LIKE 'XLSX_IMPORT:%'
        AND CAST(strftime('%Y', i.fecha) AS INTEGER) = ?
      ''',
      [year],
    );
  }

  static ({double totalCorregido, double base, double iva})
  _calculateXlsxRepairAmounts(double totalActual) {
    final totalCorregido = _round2(totalActual / (1 + _ivaRate));
    final base = _round2(totalCorregido / (1 + _ivaRate));
    final iva = _round2(totalCorregido - base);
    return (totalCorregido: totalCorregido, base: base, iva: iva);
  }

  static String? _patchItemsBase(String? raw, double base) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.isEmpty) return null;
      final first = Map<String, dynamic>.from(decoded.first as Map);
      first['precio_unitario'] = base;
      first['total_linea'] = base;
      decoded[0] = first;
      return jsonEncode(decoded);
    } catch (_) {
      return null;
    }
  }

  static ({double base, double iva, double total})
  _calculateOfficialAmountsFromTotal(double total) {
    final base = _round2(total / (1 + _ivaRate));
    final iva = _round2(total - base);
    final fixedTotal = _round2(total);
    return (base: base, iva: iva, total: fixedTotal);
  }

  static double _round2(double value) => (value * 100).round() / 100.0;
}
