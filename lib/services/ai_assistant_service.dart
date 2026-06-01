import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ai_assistant.dart';
import '../models/client.dart';
import '../models/gig.dart';
import '../models/invoice.dart';
import '../providers/client_provider.dart';
import '../providers/financial_summary_provider.dart';
import '../providers/gig_provider.dart';
import '../providers/invoice_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/stats_provider.dart';
import '../repositories/client_repository.dart';
import '../repositories/gig_repository.dart';
import '../repositories/invoice_repository.dart';
import 'ai_service.dart';
import 'ai_entity_resolver_service.dart';
import 'date_resolver_service.dart';
import 'invoice_email_service.dart';

class AiAssistantService {
  AiAssistantService._();

  static final AiAssistantService instance = AiAssistantService._();

  Future<AiAssistantAction> interpret(
    String message, {
    List<Map<String, String>> conversationEntities = const [],
    List<String> collectionGigIds = const [],
  }) async {
    final localBulkAction = _tryParseBulkInvoiceAction(
      message,
      collectionGigIds: collectionGigIds,
    );
    if (localBulkAction != null) {
      return localBulkAction;
    }
    final context = await _buildContext(
      conversationEntities: conversationEntities,
    );
    final json = await AiService.instance.interpretAssistantAction(
      message: message,
      contextData: context,
    );
    final enriched = Map<String, dynamic>.from(json)
      ..['_source_message'] = message
      ..['_conversation_entities'] = conversationEntities;
    return AiAssistantAction.fromJson(enriched);
  }

  Future<AiActionPreview> buildPreview(AiAssistantAction action) async {
    switch (action.accion) {
      case 'crear_bolos':
        return _previewCreateGigs(action);
      case 'buscar_bolos':
      case 'resumen_agenda':
        final result = await _searchGigs(action);
        final facturableFilter = _resolveFacturableFilter(action);
        final invoiceSearch = _isInvoiceSearch(action);
        final chargeFilter = _resolveChargeFilter(action);
        final title = action.accion == 'resumen_agenda'
            ? 'Resumen de agenda'
            : invoiceSearch
            ? chargeFilter == _ChargeFilter.pending
                  ? 'Facturas pendientes de cobro'
                  : chargeFilter == _ChargeFilter.collected
                  ? 'Facturas cobradas'
                  : 'Facturas encontradas'
            : (facturableFilter == true
                  ? 'Bolos facturables encontrados'
                  : facturableFilter == false
                  ? 'Bolos no facturables encontrados'
                  : 'Bolos encontrados');
        return AiActionPreview(
          title: title,
          description: result.isEmpty
              ? 'No he encontrado bolos con esos filtros.'
              : 'He encontrado ${result.length} bolo(s).',
          items: await _gigLines(result),
          requiresConfirmation: false,
          executable: false,
        );
      case 'actualizar_bolo':
        final gigResolution = await _resolveTargetGig(action);
        final gig = gigResolution.selected;
        final detail = await _buildGigUpdatePreview(action, gig);
        return AiActionPreview(
          title: 'Actualizar bolo',
          description: gig == null
              ? _buildAmbiguousGigMessage(gigResolution)
              : detail.$1,
          items: gig == null
              ? gigResolution.candidates.take(5).map((c) => c.label).toList()
              : detail.$2,
          requiresConfirmation: true,
          executable: gig != null,
        );
      case 'crear_factura':
        final gigResolution = await _resolveTargetGig(
          action,
          onlyFacturable: true,
        );
        final gig = gigResolution.selected;
        return AiActionPreview(
          title: 'Crear factura',
          description: gig == null
              ? _buildAmbiguousGigMessage(gigResolution)
              : 'Se creará una factura borrador para este bolo.',
          items: gig == null
              ? gigResolution.candidates.take(5).map((c) => c.label).toList()
              : await _gigLines([gig]),
          requiresConfirmation: true,
          executable: gig != null,
        );
      case 'crear_facturas_masivas':
        final plan = await _buildBulkInvoicePlan(action);
        final usesCollection = _readStringList(action.raw['gig_ids']).isNotEmpty;
        if (plan.eligible.isEmpty) {
          return AiActionPreview(
            title: 'Facturación masiva',
            description: 'No hay bolos facturables pendientes de facturar.',
            requiresConfirmation: true,
            executable: false,
          );
        }
        final items = <String>[
          'Facturas a crear: ${plan.eligible.length}',
          ...await _bulkInvoiceGigLines(plan.eligible),
          'Importe total: ${_money(plan.totalAmount)}',
          if (plan.skippedAlreadyInvoiced > 0)
            'Omitidos (ya facturados): ${plan.skippedAlreadyInvoiced}',
          if (plan.skippedNotBillable > 0)
            'Omitidos (no facturables): ${plan.skippedNotBillable}',
          if (plan.skippedCancelled > 0)
            'Omitidos (cancelados): ${plan.skippedCancelled}',
        ];
        return AiActionPreview(
          title: 'Crear facturas masivas',
          description: usesCollection
              ? 'Voy a crear ${plan.eligible.length} facturas para estos bolos facturables pendientes de facturar.'
              : 'Voy a crear ${plan.eligible.length} facturas para todos los bolos facturables pendientes de facturar.',
          items: items,
          requiresConfirmation: true,
          executable: true,
        );
      case 'enviar_factura_email':
        final invoiceResolution = await _resolveTargetInvoice(action);
        final invoice = invoiceResolution.selected;
        final client = invoice == null
            ? null
            : await ClientRepository.instance.getById(invoice.clientId);
        return AiActionPreview(
          title: 'Enviar factura por email',
          description: invoice == null
              ? (invoiceResolution.reason ??
                    'Necesito identificar una factura concreta antes de enviar.')
              : 'Enviar a ${client?.email?.trim().isNotEmpty == true ? client!.email : 'cliente sin email configurado'}.',
          items: invoice == null
              ? invoiceResolution.candidates
                    .take(5)
                    .map((c) => c.label)
                    .toList()
              : [
                  'Factura #${invoice.numero}',
                  if (client != null) client.nombre,
                ],
          requiresConfirmation: true,
          executable:
              invoice != null && client?.email?.trim().isNotEmpty == true,
        );
      case 'buscar_cliente':
        final clients = await _searchClients(action);
        return AiActionPreview(
          title: 'Clientes encontrados',
          description: clients.isEmpty
              ? 'No he encontrado clientes con ese criterio.'
              : 'He encontrado ${clients.length} cliente(s).',
          items: clients.map((client) => client.nombre).toList(),
          requiresConfirmation: false,
          executable: false,
        );
      case 'crear_cliente':
        final draft = _clientDraftFromMap(action.cliente);
        final clientLines = _clientPreviewLines([draft]);
        return AiActionPreview(
          title: 'Crear cliente',
          description: !draft.hasName
              ? 'Necesito el nombre del cliente.'
              : 'Se creará un cliente nuevo.',
          items: clientLines,
          requiresConfirmation: true,
          executable: draft.hasName,
        );
      case 'crear_clientes':
        final drafts = action.clientes;
        final validCount = drafts.where((client) => client.hasName).length;
        return AiActionPreview(
          title: 'Crear $validCount cliente(s)',
          description: validCount == 0
              ? 'No he encontrado clientes con nombre claro.'
              : 'Revisa los clientes antes de crearlos.',
          items: _clientPreviewLines(drafts),
          requiresConfirmation: true,
          executable: validCount > 0,
        );
      case 'pregunta_aclaratoria':
        return AiActionPreview(
          title: 'Necesito un dato más',
          description: action.pregunta ?? '¿Puedes concretarlo un poco más?',
          requiresConfirmation: false,
          executable: false,
        );
      default:
        return const AiActionPreview(
          title: 'Acción no disponible',
          description:
              'Esta acción todavía no está soportada por el asistente.',
          requiresConfirmation: false,
          executable: false,
        );
    }
  }

  Future<AiAssistantAction> resolveEntities(AiAssistantAction action) async {
    if (action.accion == 'crear_bolos') {
      return _normalizeCreateBolos(action);
    }
    switch (action.accion) {
      case 'actualizar_bolo':
      case 'crear_factura':
        final gig = (await _resolveTargetGig(
          action,
          onlyFacturable: action.accion == 'crear_factura',
        )).selected;
        if (gig == null) return action;
        return _withResolvedEntity(action, type: 'gig', id: gig.id);
      case 'enviar_factura_email':
        final invoice = (await _resolveTargetInvoice(action)).selected;
        if (invoice == null) return action;
        return _withResolvedEntity(action, type: 'invoice', id: invoice.id);
      default:
        return action;
    }
  }

  Future<AiAssistantActionResult> execute(
    AiAssistantAction action,
    Ref ref,
  ) async {
    switch (action.accion) {
      case 'crear_bolos':
        final result = await _executeCreateGigs(action, ref);
        return AiAssistantActionResult(
          message:
              'He creado ${result.$1} bolo(s) y los he dejado en la agenda.',
          referencedEntity: result.$2 == null
              ? null
              : {
                  'entity_type': 'gig',
                  'entity_id': result.$2!.id,
                  'entity_name': await _gigDisplayName(result.$2!),
                },
        );
      case 'actualizar_bolo':
        final message = await _executeUpdateGig(action, ref);
        return AiAssistantActionResult(
          message: message,
          referencedEntity: action.resolvedEntityId == null
              ? null
              : {
                  'entity_type': 'gig',
                  'entity_id': action.resolvedEntityId!,
                  'entity_name': await _gigDisplayNameById(
                    action.resolvedEntityId!,
                  ),
                },
        );
      case 'crear_factura':
        final message = await _executeCreateInvoice(action, ref);
        return AiAssistantActionResult(message: message);
      case 'crear_facturas_masivas':
        final message = await _executeCreateBulkInvoices(action, ref);
        return AiAssistantActionResult(message: message);
      case 'enviar_factura_email':
        final message = await _executeSendInvoiceEmail(action, ref);
        return AiAssistantActionResult(message: message);
      case 'crear_cliente':
        final message = await _executeCreateClients([
          _clientDraftFromMap(action.cliente),
        ], ref);
        return AiAssistantActionResult(message: message);
      case 'crear_clientes':
        final message = await _executeCreateClients(action.clientes, ref);
        return AiAssistantActionResult(message: message);
      default:
        final preview = await buildPreview(action);
        return AiAssistantActionResult(
          message: preview.description,
          preview: preview,
        );
    }
  }

  Future<Map<String, dynamic>> _buildContext({
    List<Map<String, String>> conversationEntities = const [],
  }) async {
    final clients = await ClientRepository.instance.getAll();
    final gigs = await GigRepository.instance.getAll();
    final invoices = await InvoiceRepository.instance.getAll();
    final now = DateTime.now();

    return {
      'current_date': _date(now),
      'current_year': now.year,
      'locale': 'es-ES',
      'clients': clients.take(40).map((client) {
        return {
          'id': client.id,
          'nombre': _clip(client.nombre, 80),
          'alias': _clip(client.alias, 40),
          'aliases': client.aliases
              .take(3)
              .map((alias) => _clip(alias, 40))
              .toList(),
          'email': _clip(client.email, 80),
        };
      }).toList(),
      'recent_gigs': gigs.reversed.take(30).map((gig) {
        return {
          'id': gig.id,
          'fecha': _date(gig.fecha),
          'client_id': gig.clientId,
          'cachet': gig.cachet,
          'facturable': gig.facturable,
          'status': gig.status.dbValue,
          'invoice_id': gig.invoiceId,
        };
      }).toList(),
      'recent_invoices': invoices.reversed.take(20).map((invoice) {
        return {
          'id': invoice.id,
          'numero': invoice.numero,
          'fecha': _date(invoice.fecha),
          'client_id': invoice.clientId,
          'gig_id': invoice.gigId,
          'total': invoice.total,
          'status': invoice.status.dbValue,
        };
      }).toList(),
      'conversation_entities': conversationEntities.take(8).toList(),
    };
  }

  AiActionPreview _previewCreateGigs(AiAssistantAction action) {
    if (action.bolos.isEmpty) {
      return const AiActionPreview(
        title: 'Crear bolos',
        description: 'No he encontrado bolos claros en el mensaje.',
        requiresConfirmation: true,
        executable: false,
      );
    }
    final hasMissingRequired = action.bolos.any(
      (bolo) =>
          (bolo.fecha ?? '').trim().isEmpty ||
          bolo.nombre.trim().isEmpty ||
          bolo.importe == null ||
          bolo.facturable == null,
    );
    return AiActionPreview(
      title: 'Crear ${action.bolos.length} bolo(s)',
      description: hasMissingRequired
          ? 'Faltan datos obligatorios (cliente/nombre, fecha, importe o tipo facturable).'
          : 'Revisa los datos antes de añadirlos a la agenda.',
      items: action.bolos.map((bolo) {
        final type = bolo.facturable == null
            ? 'facturable sin definir'
            : (bolo.facturable! ? 'facturable' : 'no facturable');
        final amount = bolo.importe == null
            ? ''
            : ' · ${_money(bolo.importe!)}';
        return '${bolo.fecha ?? 'Sin fecha'} · ${bolo.nombre}$amount · $type';
      }).toList(),
      requiresConfirmation: true,
      executable: !hasMissingRequired,
    );
  }

  Future<(int, Gig?)> _executeCreateGigs(AiAssistantAction action, Ref ref) async {
    var created = 0;
    Gig? lastCreated;
    for (final draft in action.bolos) {
      final date = DateTime.tryParse(draft.fecha ?? '');
      if (date == null ||
          draft.nombre.trim().isEmpty ||
          draft.importe == null ||
          draft.facturable == null) {
        continue;
      }
      var client = await ClientRepository.instance.findByNameOrAlias(
        draft.nombre,
      );
      if (client == null) {
        client = Client(nombre: draft.nombre);
        await ref.read(clientsProvider.notifier).add(client);
      }
      final gig = Gig(
        fecha: date,
        clientId: client.id,
        cachet: draft.importe,
        facturable: draft.facturable!,
        status: draft.facturable!
            ? GigStatus.confirmado
            : GigStatus.confirmadoB,
        notas: draft.notas,
      );
      await ref.read(gigsProvider.notifier).add(gig);
      created++;
      lastCreated = gig;
    }
    ref.invalidate(clientsProvider);
    ref.invalidate(gigsProvider);
    return (created, lastCreated);
  }

  Future<String> _executeUpdateGig(AiAssistantAction action, Ref ref) async {
    final gig = (await _resolveTargetGig(action)).selected;
    if (gig == null) {
      return 'Necesito identificar un único bolo para actualizarlo.';
    }
    var updated = gig;
    final status = _readString(action.cambios['estado']);
    if (status == 'cobrado') {
      updated = updated.copyWith(
        status: updated.facturable ? GigStatus.cobrado : GigStatus.cobradoB,
      );
    }
    final fecha = DateTime.tryParse(_readString(action.cambios['fecha']) ?? '');
    if (fecha != null) updated = updated.copyWith(fecha: fecha);
    final importe = _readNumber(action.cambios['importe']);
    if (importe != null) updated = updated.copyWith(cachet: importe);
    await ref.read(gigsProvider.notifier).updateGig(updated);
    ref.invalidate(gigsProvider);
    ref.invalidate(dashboardStatsProvider);
    ref.invalidate(financialSummaryProvider);
    final detail = await _buildGigUpdatePreview(action, gig);
    return 'Bolo actualizado correctamente. ${detail.$1}';
  }

  Future<String> _executeCreateInvoice(
    AiAssistantAction action,
    Ref ref,
  ) async {
    final gig = (await _resolveTargetGig(action, onlyFacturable: true)).selected;
    if (gig == null) return 'No he encontrado un bolo facturable válido.';
    final existing = await InvoiceRepository.instance.getByGigId(gig.id);
    if (existing != null) return 'Ese bolo ya tiene factura.';
    final settings = ref.read(settingsProvider).valueOrNull;
    final numero = await InvoiceRepository.instance.getNextNumberForYear(
      gig.fecha.year,
    );
    final client = await ClientRepository.instance.getById(gig.clientId);
    final subtotal = gig.cachet ?? 0;
    final invoice = Invoice(
      numero: numero,
      fecha: gig.fecha,
      clientId: gig.clientId,
      gigId: gig.id,
      items: [
        InvoiceLineItem(
          cantidad: 1,
          descripcion: 'Actuación ${client?.nombre ?? ''}'.trim(),
          precioUnitario: subtotal,
        ),
      ],
      subtotal: subtotal,
      ivaRate: settings?.ivaDefault ?? 0.21,
      irpfRate: settings?.irpfDefault ?? 0,
    );
    await ref.read(invoicesProvider.notifier).addAndLinkToGig(invoice);
    return 'Factura #$numero creada en borrador.';
  }

  Future<String> _executeSendInvoiceEmail(
    AiAssistantAction action,
    Ref ref,
  ) async {
    final invoice = (await _resolveTargetInvoice(action)).selected;
    if (invoice == null) return 'No he encontrado la factura.';
    final client = await ClientRepository.instance.getById(invoice.clientId);
    if (client == null) return 'No he encontrado el cliente de la factura.';
    final settings = ref.read(settingsProvider).valueOrNull;
    if (settings == null) return 'No he podido cargar la configuración fiscal.';
    await InvoiceEmailService().sendInvoice(
      invoice: invoice,
      client: client,
      settings: settings,
    );
    await ref
        .read(invoicesProvider.notifier)
        .updateStatus(invoice.id, InvoiceStatus.enviada);
    return 'Factura #${invoice.numero} enviada a ${client.email}.';
  }

  Future<String> _executeCreateBulkInvoices(
    AiAssistantAction action,
    Ref ref,
  ) async {
    final plan = await _buildBulkInvoicePlan(action);
    debugPrint(
      '[BULK_INVOICE_CREATE] candidates=${plan.eligible.length} skippedAlreadyInvoiced=${plan.skippedAlreadyInvoiced} skippedNotBillable=${plan.skippedNotBillable} createdInvoices=0',
    );
    if (plan.eligible.isEmpty) {
      return 'No hay bolos facturables pendientes de facturar.';
    }
    final settings = ref.read(settingsProvider).valueOrNull;
    var created = 0;
    for (final gig in plan.eligible) {
      final numero = await InvoiceRepository.instance.getNextNumberForYear(
        gig.fecha.year,
      );
      final client = await ClientRepository.instance.getById(gig.clientId);
      final subtotal = gig.cachet ?? 0;
      final invoice = Invoice(
        numero: numero,
        fecha: gig.fecha,
        clientId: gig.clientId,
        gigId: gig.id,
        items: [
          InvoiceLineItem(
            cantidad: 1,
            descripcion: 'Actuación ${client?.nombre ?? ''}'.trim(),
            precioUnitario: subtotal,
          ),
        ],
        subtotal: subtotal,
        ivaRate: settings?.ivaDefault ?? 0.21,
        irpfRate: settings?.irpfDefault ?? 0,
      );
      await ref.read(invoicesProvider.notifier).addAndLinkToGig(invoice);
      created++;
    }
    ref.invalidate(gigsProvider);
    ref.invalidate(invoicesProvider);
    ref.invalidate(dashboardStatsProvider);
    ref.invalidate(financialSummaryProvider);
    debugPrint(
      '[BULK_INVOICE_CREATE] candidates=${plan.eligible.length} skippedAlreadyInvoiced=${plan.skippedAlreadyInvoiced} skippedNotBillable=${plan.skippedNotBillable} createdInvoices=$created',
    );
    return 'He creado $created factura(s) y he actualizado agenda, facturas, dashboard y resumen financiero.';
  }

  Future<String> _executeCreateClients(
    List<AiClientDraft> drafts,
    Ref ref,
  ) async {
    final created = <String>[];
    final failed = <String>[];

    for (final draft in drafts) {
      final name = draft.nombre.trim();
      if (name.isEmpty) {
        failed.add('Cliente sin nombre');
        continue;
      }
      try {
        final existing = await ClientRepository.instance.findByNameOrAlias(
          name,
        );
        if (existing != null) {
          failed.add('$name: ya existe');
          continue;
        }
        await ref.read(clientsProvider.notifier).add(_clientFromDraft(draft));
        created.add(name);
      } catch (e) {
        failed.add('$name: $e');
      }
    }

    if (created.isEmpty && failed.isEmpty) return 'No había clientes válidos.';
    final parts = <String>[];
    if (created.isNotEmpty) {
      parts.add(
        '${created.length} cliente${created.length == 1 ? '' : 's'} creado${created.length == 1 ? '' : 's'}',
      );
    }
    if (failed.isNotEmpty) {
      parts.add('No creados: ${failed.join('; ')}');
    }
    return '${parts.join('. ')}.';
  }

  Future<List<Gig>> _searchGigs(AiAssistantAction action) async {
    final gigs = await GigRepository.instance.getAll();
    final invoices = await InvoiceRepository.instance.getAll();
    final invoiceByGigId = {for (final invoice in invoices) invoice.gigId: invoice};
    final sourceDate = _readString(action.filtros['fecha']);
    final exactDate = DateTime.tryParse(sourceDate ?? '');
    final from = DateTime.tryParse(
      _readString(action.filtros['fecha_desde']) ?? '',
    );
    final to = DateTime.tryParse(
      _readString(action.filtros['fecha_hasta']) ?? '',
    );
    final query = _readString(action.filtros['texto'])?.toLowerCase();
    final facturableFilter = _resolveFacturableFilter(action);
    final chargeFilter = _resolveChargeFilter(action);
    final invoiceOnly = _isInvoiceSearch(action);
    final monthFilter = _resolveMonthFilter(action);
    final statusFilter = _resolveInvoiceStatusFilter(action);
    final clients = await ClientRepository.instance.getAll();
    final clientById = {for (final client in clients) client.id: client};
    final clientFilterId = _resolveClientFilterId(action, clients);
    return gigs.where((gig) {
      final invoice = invoiceByGigId[gig.id];
      final effectiveDate = invoiceOnly && invoice != null ? invoice.fecha : gig.fecha;
      if (from != null && effectiveDate.isBefore(from)) return false;
      if (to != null && effectiveDate.isAfter(to.add(const Duration(days: 1)))) {
        return false;
      }
      if (exactDate != null &&
          (effectiveDate.year != exactDate.year ||
              effectiveDate.month != exactDate.month ||
              effectiveDate.day != exactDate.day)) {
        return false;
      }
      if (monthFilter != null && effectiveDate.month != monthFilter) {
        return false;
      }
      if (query != null) {
        final client = clientById[gig.clientId];
        final name = client?.nombre.toLowerCase() ?? '';
        if (!name.contains(query)) return false;
      }
      if (clientFilterId != null && gig.clientId != clientFilterId) return false;
      if (facturableFilter != null && gig.facturable != facturableFilter) {
        return false;
      }
      if (invoiceOnly && invoice == null) return false;
      if (statusFilter != null) {
        if (invoice == null || invoice.status != statusFilter) return false;
      }
      if (chargeFilter == _ChargeFilter.pending) {
        if (invoiceOnly) {
          if (invoice == null) return false;
          if (invoice.status == InvoiceStatus.pagada) return false;
        } else {
          if (gig.status == GigStatus.cobrado || gig.status == GigStatus.cobradoB) {
            return false;
          }
        }
      }
      if (chargeFilter == _ChargeFilter.collected) {
        if (invoiceOnly) {
          if (invoice == null) return false;
          if (invoice.status != InvoiceStatus.pagada) return false;
        } else {
          if (gig.status != GigStatus.cobrado && gig.status != GigStatus.cobradoB) {
            return false;
          }
        }
      }
      return true;
    }).toList();
  }

  Future<List<Client>> _searchClients(AiAssistantAction action) async {
    final query =
        _readString(action.cliente['nombre']) ??
        _readString(action.filtros['texto']) ??
        '';
    if (query.trim().isEmpty) return ClientRepository.instance.getAll();
    return ClientRepository.instance.search(query);
  }

  AiClientDraft _clientDraftFromMap(Map<String, dynamic> cliente) {
    return AiClientDraft(
      nombre: _readString(cliente['nombre']) ?? '',
      aliasPrincipal: _readString(cliente['alias_principal']) ?? '',
      nombresAlternativos: _readStringList(cliente['nombres_alternativos']),
      cifNif: _readString(cliente['cif_nif']) ?? '',
      direccion: _readString(cliente['direccion']) ?? '',
      ciudad: _readString(cliente['ciudad']) ?? '',
      codigoPostal: _readString(cliente['codigo_postal']) ?? '',
      provincia: _readString(cliente['provincia']) ?? '',
      email: _readString(cliente['email']) ?? '',
      telefono: _readString(cliente['telefono']) ?? '',
      telefonoWhatsapp: _readString(cliente['telefono_whatsapp']) ?? '',
      notas: _readString(cliente['notas']) ?? '',
    );
  }

  Client _clientFromDraft(AiClientDraft draft) {
    return Client(
      nombre: draft.nombre,
      alias: draft.aliasPrincipal,
      aliases: draft.nombresAlternativos,
      cifNif: draft.cifNif,
      direccion: draft.direccion,
      ciudad: draft.ciudad,
      provincia: draft.provincia,
      codigoPostal: draft.codigoPostal,
      email: _readString(draft.email),
      telefono: _readString(draft.telefono),
      whatsappPhone: _readString(draft.telefonoWhatsapp),
      notas: draft.notas,
    );
  }

  List<String> _clientPreviewLines(List<AiClientDraft> drafts) {
    final lines = <String>[];
    for (var i = 0; i < drafts.length; i++) {
      final client = drafts[i];
      final fields = <String>[];
      void add(String label, String value) {
        final text = value.trim();
        if (text.isNotEmpty) fields.add('$label: $text');
      }

      add('Nombre', client.nombre);
      add('Alias principal', client.aliasPrincipal);
      if (client.nombresAlternativos.isNotEmpty) {
        fields.add(
          'Nombres alternativos: ${client.nombresAlternativos.join(', ')}',
        );
      }
      add('CIF/NIF', client.cifNif);
      add('Dirección', client.direccion);
      add('Ciudad', client.ciudad);
      add('C.P.', client.codigoPostal);
      add('Provincia', client.provincia);
      add('Email', client.email);
      add('Teléfono', client.telefono);
      add('WhatsApp', client.telefonoWhatsapp);
      add('Notas', client.notas);
      if (fields.isEmpty) {
        lines.add('Cliente ${i + 1}: sin datos válidos');
      } else {
        lines.add('Cliente ${i + 1}: ${fields.join(' · ')}');
      }
    }
    return lines;
  }

  Future<AiEntityResolution<Gig>> _resolveTargetGig(
    AiAssistantAction action, {
    bool onlyFacturable = false,
  }) async {
    return AiEntityResolverService.instance.resolveGig(
      action,
      onlyFacturable: onlyFacturable,
    );
  }

  Future<AiEntityResolution<Invoice>> _resolveTargetInvoice(
    AiAssistantAction action,
  ) async {
    return AiEntityResolverService.instance.resolveInvoice(action);
  }

  String _buildAmbiguousGigMessage(AiEntityResolution<Gig> resolution) {
    if (resolution.isAmbiguous) {
      return 'He encontrado varios bolos posibles. Elige uno para continuar.';
    }
    return resolution.reason ??
        'Necesito identificar un único bolo antes de continuar.';
  }

  AiAssistantAction _withResolvedEntity(
    AiAssistantAction action, {
    required String type,
    required String id,
  }) {
    final raw = Map<String, dynamic>.from(action.raw);
    raw['resolved_entity_type'] = type;
    raw['resolved_entity_id'] = id;
    return AiAssistantAction.fromJson(raw);
  }

  Future<(String, List<String>)> _buildGigUpdatePreview(
    AiAssistantAction action,
    Gig? gig,
  ) async {
    if (gig == null) {
      return (
        'Necesito identificar un único bolo antes de actualizarlo.',
        const <String>[],
      );
    }
    final client = await ClientRepository.instance.getById(gig.clientId);
    final before = <String>[
      'before|Nombre|Bolo para ${client?.nombre ?? 'Cliente'}',
      'before|Fecha|${_formatDateEs(gig.fecha)}',
      'before|Importe|${gig.cachet == null ? 'Sin importe' : _money(gig.cachet!)}',
      'before|Estado|${gig.status.label}',
      'before|Tipo|${gig.facturable ? 'Facturable' : 'No facturable'}',
    ];

    final changes = <String>[];
    final fecha = DateTime.tryParse(_readString(action.cambios['fecha']) ?? '');
    if (fecha != null) {
      changes.add('diff|Fecha|${_formatDateEs(gig.fecha)}|${_formatDateEs(fecha)}');
    }
    final importeNuevo = _readNumber(action.cambios['importe']);
    if (importeNuevo != null) {
      changes.add(
        'diff|Importe|${gig.cachet == null ? 'Sin importe' : _money(gig.cachet!)}|${_money(importeNuevo)}',
      );
    }
    final status = _readString(action.cambios['estado']);
    if (status == 'cobrado') {
      final next = gig.facturable ? GigStatus.cobrado.label : GigStatus.cobradoB.label;
      changes.add('diff|Estado|${gig.status.label}|$next');
    }

    final description = changes.isEmpty
        ? 'Voy a actualizar el bolo de ${client?.nombre ?? 'este cliente'}.'
        : 'Estos son los cambios que se aplicarán:';
    final items = <String>[
      'section|Bolo encontrado|',
      ...before,
      if (changes.isNotEmpty) 'section|Cambios|',
      ...changes,
    ];
    return (description, items);
  }

  Future<List<String>> _gigLines(List<Gig> gigs) async {
    final clients = await ClientRepository.instance.getAll();
    final byId = {for (final client in clients) client.id: client};
    return gigs.map((gig) {
      final client = byId[gig.clientId];
      final amount = gig.cachet == null ? '' : ' · ${_money(gig.cachet!)}';
      final type = gig.facturable ? 'facturable' : 'no facturable';
      return '${_date(gig.fecha)} · ${client?.nombre ?? 'Cliente'}$amount · $type';
    }).toList();
  }

  Future<List<String>> _bulkInvoiceGigLines(List<Gig> gigs) async {
    final clients = await ClientRepository.instance.getAll();
    final byId = {for (final client in clients) client.id: client};
    return gigs.map((gig) {
      final clientName = byId[gig.clientId]?.nombre ?? 'Cliente';
      final amount = gig.cachet == null ? 'Sin importe' : _money(gig.cachet!);
      return 'Fecha: ${_date(gig.fecha)} · Nombre: Bolo · Cliente: $clientName · Importe: $amount';
    }).toList();
  }

  String? _readString(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  List<String> _readStringList(Object? value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    final text = _readString(value);
    if (text == null) return const [];
    return text
        .split(RegExp(r'\n|,|;'))
        .map((item) => item.replaceFirst(RegExp(r'^[-*]\s*'), '').trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String _date(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _money(double value) => '${value.toStringAsFixed(2)} €';

  String _clip(String? value, int max) {
    final text = (value ?? '').trim();
    if (text.length <= max) return text;
    return text.substring(0, max);
  }

  double? _readNumber(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.replaceAll(',', '.'));
    return null;
  }

  String _formatDateEs(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString().padLeft(4, '0');
    return '$day/$month/$year';
  }

  Future<String> _gigDisplayName(Gig gig) async {
    final client = await ClientRepository.instance.getById(gig.clientId);
    return 'Bolo para ${client?.nombre ?? 'Cliente'}';
  }

  Future<String> _gigDisplayNameById(String gigId) async {
    final gig = await GigRepository.instance.getById(gigId);
    if (gig == null) return 'Bolo';
    return _gigDisplayName(gig);
  }

  bool? _resolveFacturableFilter(AiAssistantAction action) {
    final fromFilters = action.filtros['facturable'];
    if (fromFilters is bool) return fromFilters;
    final source = (action.raw['_source_message']?.toString() ?? '').toLowerCase();
    if (source.contains('no facturable') ||
        source.contains(' en b') ||
        source.contains('sin factura')) {
      return false;
    }
    if (source.contains('facturable') ||
        source.contains('facturables') ||
        source.contains('con factura') ||
        source.contains('oficial')) {
      return true;
    }
    return null;
  }

  _ChargeFilter? _resolveChargeFilter(AiAssistantAction action) {
    final estado = _readString(action.filtros['estado'])?.toLowerCase() ?? '';
    if (estado.contains('cobrad') || estado == 'pagada') {
      return _ChargeFilter.collected;
    }
    if (estado.contains('pendiente') ||
        estado.contains('por cobrar') ||
        estado == 'enviada') {
      return _ChargeFilter.pending;
    }
    final source = (action.raw['_source_message']?.toString() ?? '').toLowerCase();
    if (source.contains('por cobrar') ||
        source.contains('pendiente de cobro') ||
        source.contains('pendientes de cobro') ||
        source.contains('sin cobrar') ||
        source.contains('pendientes')) {
      return _ChargeFilter.pending;
    }
    if (source.contains('cobradas') ||
        source.contains('cobrados') ||
        source.contains('pagadas') ||
        source.contains('pagados')) {
      return _ChargeFilter.collected;
    }
    return null;
  }

  InvoiceStatus? _resolveInvoiceStatusFilter(AiAssistantAction action) {
    final status = _readString(action.filtros['status'])?.toLowerCase() ??
        _readString(action.filtros['estado'])?.toLowerCase() ??
        '';
    if (status.contains('borrador')) return InvoiceStatus.borrador;
    if (status.contains('enviada') ||
        status.contains('pendiente') ||
        status.contains('por cobrar')) {
      return InvoiceStatus.enviada;
    }
    if (status.contains('pagada') || status.contains('cobrada')) {
      return InvoiceStatus.pagada;
    }
    return null;
  }

  int? _resolveMonthFilter(AiAssistantAction action) {
    final value = action.filtros['mes'];
    if (value is num) {
      final month = value.toInt();
      if (month >= 1 && month <= 12) return month;
    }
    final text = _readString(value)?.toLowerCase();
    if (text == null) return null;
    const byName = {
      'enero': 1,
      'febrero': 2,
      'marzo': 3,
      'abril': 4,
      'mayo': 5,
      'junio': 6,
      'julio': 7,
      'agosto': 8,
      'septiembre': 9,
      'setiembre': 9,
      'octubre': 10,
      'noviembre': 11,
      'diciembre': 12,
    };
    if (byName.containsKey(text)) return byName[text];
    final parsed = int.tryParse(text);
    if (parsed != null && parsed >= 1 && parsed <= 12) return parsed;
    return null;
  }

  String? _resolveClientFilterId(
    AiAssistantAction action,
    List<Client> clients,
  ) {
    final rawClientId = _readString(action.filtros['cliente_id']);
    if (rawClientId != null &&
        clients.any((client) => client.id == rawClientId)) {
      return rawClientId;
    }
    final clientText = _readString(action.filtros['cliente']) ??
        _readString(action.filtros['cliente_nombre']) ??
        _readString(action.objetivo['cliente']) ??
        _readString(action.objetivo['cliente_nombre']);
    if (clientText == null) return null;
    final query = clientText.toLowerCase().trim();
    for (final client in clients) {
      if (client.nombre.toLowerCase() == query) return client.id;
      if (client.alias.toLowerCase() == query) return client.id;
      if (client.aliases.map((a) => a.toLowerCase()).contains(query)) {
        return client.id;
      }
    }
    for (final client in clients) {
      if (client.nombre.toLowerCase().contains(query) ||
          client.alias.toLowerCase().contains(query) ||
          client.aliases.any((alias) => alias.toLowerCase().contains(query))) {
        return client.id;
      }
    }
    return null;
  }

  bool _isInvoiceSearch(AiAssistantAction action) {
    final source = (action.raw['_source_message']?.toString() ?? '').toLowerCase();
    return source.contains('factura') ||
        action.filtros.containsKey('status') ||
        action.filtros.containsKey('mes') ||
        action.filtros.containsKey('cliente') ||
        action.filtros.containsKey('cliente_id');
  }

  Future<List<String>> collectionGigIdsFor(AiAssistantAction action) async {
    if (action.accion != 'buscar_bolos' && action.accion != 'resumen_agenda') {
      return const [];
    }
    final gigs = await _searchGigs(action);
    return gigs.map((gig) => gig.id).toList();
  }

  AiAssistantAction? _tryParseBulkInvoiceAction(
    String message, {
    List<String> collectionGigIds = const [],
  }) {
    final normalized = _normalizeForParser(message);
    final hasInvoiceIntent = RegExp(
      r'\bfactura(?:r|s)?\b',
    ).hasMatch(normalized);
    final referencesAll =
        RegExp(r'\btod[oa]s?\b').hasMatch(normalized) ||
        normalized.contains('a los facturables');
    final referencesCollection =
        normalized.contains('estos') ||
        normalized.contains('estas') ||
        normalized.contains('los de la lista') ||
        normalized.contains('las de la lista') ||
        normalized.contains('los bolos de la lista');
    final isBulkInvoice =
        hasInvoiceIntent &&
        !normalized.contains('email') &&
        (referencesAll || (referencesCollection && collectionGigIds.isNotEmpty));
    if (!isBulkInvoice) return null;
    final gigIds = referencesAll ? const <String>[] : collectionGigIds;
    final raw = <String, dynamic>{
      'accion': 'crear_facturas_masivas',
      'requiere_confirmacion': true,
      'confianza': 0.99,
      'filtros': {
        'facturable': true,
        'sin_factura': true,
        'cancelado': false,
      },
      'gig_ids': gigIds,
      'advertencias': const <String>[],
      '_source_message': message,
    };
    return AiAssistantAction.fromJson(raw);
  }

  String _normalizeForParser(String input) {
    return input
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .trim();
  }

  Future<_BulkInvoicePlan> _buildBulkInvoicePlan(
    AiAssistantAction action,
  ) async {
    final gigs = await GigRepository.instance.getAll();
    final requestedIds = _readStringList(action.raw['gig_ids']).toSet();
    var skippedNotBillable = 0;
    var skippedAlreadyInvoiced = 0;
    var skippedCancelled = 0;
    final eligible = <Gig>[];
    for (final gig in gigs) {
      if (requestedIds.isNotEmpty && !requestedIds.contains(gig.id)) {
        continue;
      }
      if (gig.status == GigStatus.cancelado) {
        skippedCancelled++;
        continue;
      }
      if (!gig.facturable) {
        skippedNotBillable++;
        continue;
      }
      if (gig.invoiceId != null && gig.invoiceId!.trim().isNotEmpty) {
        skippedAlreadyInvoiced++;
        continue;
      }
      final existing = await InvoiceRepository.instance.getByGigId(gig.id);
      if (existing != null) {
        skippedAlreadyInvoiced++;
        continue;
      }
      eligible.add(gig);
    }
    final totalAmount = eligible.fold<double>(
      0,
      (sum, gig) => sum + (gig.cachet ?? 0),
    );
    return _BulkInvoicePlan(
      eligible: eligible,
      skippedAlreadyInvoiced: skippedAlreadyInvoiced,
      skippedNotBillable: skippedNotBillable,
      skippedCancelled: skippedCancelled,
      totalAmount: totalAmount,
    );
  }

  Future<AiAssistantAction> _normalizeCreateBolos(AiAssistantAction action) async {
    if (action.bolos.isEmpty) return action;
    final raw = Map<String, dynamic>.from(action.raw);
    final now = DateTime.now();
    final source = (raw['_source_message']?.toString() ?? '').trim();
    final massParsed = await _parseMassGigLines(source: source, now: now);
    final pattern = await _extractCreateGigClientDatePattern(
      source: source,
      now: now,
    );
    final tokens = DateResolverService.instance.extractRelativeDateTokens(source);
    final todayIso = _date(now);
    final bolos = <Map<String, dynamic>>[];
    for (var i = 0; i < action.bolos.length; i++) {
      final draft = action.bolos[i];
      var nombre = draft.nombre.trim();
      var fecha = draft.fecha;
      var importe = draft.importe;
      bool? facturable = draft.facturable;

      if (i < massParsed.length) {
        final parsed = massParsed[i];
        if (parsed.client.isNotEmpty) nombre = parsed.client;
        fecha = _date(parsed.date);
        if (parsed.amount != null) {
          importe = parsed.amount;
        }
        // Solo usar facturable si se detectó explícitamente en la línea.
        if (parsed.facturableDetected != null) {
          facturable = parsed.facturableDetected;
        } else {
          facturable = null;
        }
      }

      if (i == 0 && pattern != null) {
        if (pattern.client.isNotEmpty) {
          nombre = pattern.client;
        }
        if (pattern.resolvedDate != null) {
          fecha = _date(pattern.resolvedDate!);
        }
      }

      if (i >= massParsed.length) {
        final token = tokens.isNotEmpty
            ? tokens[i < tokens.length ? i : tokens.length - 1]
            : null;
        if (token != null) {
          final resolved = DateResolverService.instance.resolveExpression(
            token,
            now: now,
          );
          if (resolved != null) {
            fecha = _date(resolved);
            debugPrint('[AiAssistant] fecha_resuelta token=$token -> $fecha');
          }
        } else {
          final parsed = DateTime.tryParse(draft.fecha ?? '');
          if (parsed == null || fecha == todayIso) {
            fecha = draft.fecha;
          }
        }
      }
      bolos.add({
        'fecha': fecha,
        'nombre': nombre,
        'importe': importe,
        'facturable': facturable,
        'estado': draft.estado,
        'notas': draft.notas,
      });
    }
    raw['bolos'] = bolos;
    return AiAssistantAction.fromJson(raw);
  }

  Future<_CreateGigClientDatePattern?> _extractCreateGigClientDatePattern({
    required String source,
    required DateTime now,
  }) async {
    final pattern = RegExp(
      r'crea(?:r)?\s+un\s+bolo\s+para\s+(.+?)\s+para\s+(?:el\s+)?(lunes|martes|miércoles|miercoles|jueves|viernes|sábado|sabado|domingo|mañana|manana|hoy|pasado mañana|pasado manana|\d{1,2}\s+de\s+[a-záéíóúñ]+)',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(source);
    if (match == null) return null;

    final extractedClient = (match.group(1) ?? '').trim();
    final extractedDateText = (match.group(2) ?? '').trim();
    final resolvedDate = DateResolverService.instance.resolveExpression(
      extractedDateText,
      now: now,
    );

    var normalizedClient = extractedClient;
    final existing = await ClientRepository.instance.findByNameOrAlias(
      extractedClient,
    );
    if (existing != null) {
      normalizedClient = existing.nombre.trim();
    }

    debugPrint(
      '[CREATE_GIG_CLIENT_DATE_PATTERN] extractedClient=$normalizedClient extractedDateText=$extractedDateText resolvedDate=${resolvedDate == null ? null : _date(resolvedDate)}',
    );

    return _CreateGigClientDatePattern(
      client: normalizedClient,
      dateText: extractedDateText,
      resolvedDate: resolvedDate == null
          ? null
          : DateTime(resolvedDate.year, resolvedDate.month, resolvedDate.day),
    );
  }

  Future<List<_MassGigParsedLine>> _parseMassGigLines({
    required String source,
    required DateTime now,
  }) async {
    final lines = source
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final parsed = <_MassGigParsedLine>[];
    final pattern = RegExp(
      r'^(lunes|martes|miércoles|miercoles|jueves|viernes|sábado|sabado|domingo)\s+(\d{1,2})\s+(enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre)\s+(.+)$',
      caseSensitive: false,
    );
    final monthMap = <String, int>{
      'enero': 1,
      'febrero': 2,
      'marzo': 3,
      'abril': 4,
      'mayo': 5,
      'junio': 6,
      'julio': 7,
      'agosto': 8,
      'septiembre': 9,
      'octubre': 10,
      'noviembre': 11,
      'diciembre': 12,
    };
    final weekdayMap = <String, int>{
      'lunes': DateTime.monday,
      'martes': DateTime.tuesday,
      'miercoles': DateTime.wednesday,
      'miércoles': DateTime.wednesday,
      'jueves': DateTime.thursday,
      'viernes': DateTime.friday,
      'sabado': DateTime.saturday,
      'sábado': DateTime.saturday,
      'domingo': DateTime.sunday,
    };
    for (final rawLine in lines) {
      final match = pattern.firstMatch(rawLine);
      if (match == null) continue;
      final weekdayText = (match.group(1) ?? '').toLowerCase();
      final day = int.tryParse(match.group(2) ?? '');
      final monthText = (match.group(3) ?? '').toLowerCase();
      final clientRaw = (match.group(4) ?? '').trim();
      final month = monthMap[monthText];
      if (day == null || month == null || clientRaw.isEmpty) continue;

      final date = DateTime(now.year, month, day);
      final resolvedClient = await _resolveClientName(clientRaw);
      final lineLower = rawLine.toLowerCase();
      final amount = _extractAmountFromText(rawLine);
      final facturableDetected = _extractFacturableHint(lineLower);
      final expectedWeekday = weekdayMap[weekdayText];
      if (expectedWeekday != null && date.weekday != expectedWeekday) {
        debugPrint(
          '[MASS_GIG_PARSE] weekday_mismatch rawLine="$rawLine" weekday=$weekdayText resolvedDate=${_date(date)}',
        );
      }
      final missing = <String>[
        if (amount == null) 'importe',
        if (facturableDetected == null) 'facturable',
      ];
      debugPrint(
        '[MASS_GIG_PARSE] rawLine="$rawLine" resolvedDate=${_date(date)} usedAbsoluteDate=true facturableDetected=$facturableDetected missingFields=$missing',
      );
      parsed.add(
        _MassGigParsedLine(
          client: resolvedClient,
          date: date,
          amount: amount,
          facturableDetected: facturableDetected,
        ),
      );
    }
    return parsed;
  }

  Future<String> _resolveClientName(String raw) async {
    final normalized = raw.trim();
    final existing = await ClientRepository.instance.findByNameOrAlias(
      normalized,
    );
    if (existing != null) return existing.nombre.trim();
    return normalized;
  }

  double? _extractAmountFromText(String text) {
    final match = RegExp(r'(\d+(?:[.,]\d{1,2})?)\s*€').firstMatch(text);
    if (match == null) return null;
    return double.tryParse(match.group(1)!.replaceAll(',', '.'));
  }

  bool? _extractFacturableHint(String textLower) {
    if (textLower.contains('no facturable') ||
        textLower.contains(' en b') ||
        textLower.contains('sin factura')) {
      return false;
    }
    if (textLower.contains('facturable') ||
        textLower.contains('con factura') ||
        textLower.contains('oficial')) {
      return true;
    }
    return null;
  }
}

enum _ChargeFilter { pending, collected }

class _BulkInvoicePlan {
  final List<Gig> eligible;
  final int skippedAlreadyInvoiced;
  final int skippedNotBillable;
  final int skippedCancelled;
  final double totalAmount;

  const _BulkInvoicePlan({
    required this.eligible,
    required this.skippedAlreadyInvoiced,
    required this.skippedNotBillable,
    required this.skippedCancelled,
    required this.totalAmount,
  });
}

class _CreateGigClientDatePattern {
  final String client;
  final String dateText;
  final DateTime? resolvedDate;

  const _CreateGigClientDatePattern({
    required this.client,
    required this.dateText,
    required this.resolvedDate,
  });
}

class _MassGigParsedLine {
  final String client;
  final DateTime date;
  final double? amount;
  final bool? facturableDetected;

  const _MassGigParsedLine({
    required this.client,
    required this.date,
    required this.amount,
    required this.facturableDetected,
  });
}
