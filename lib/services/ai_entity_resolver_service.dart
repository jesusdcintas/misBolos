import 'package:flutter/foundation.dart';

import '../models/ai_assistant.dart';
import '../models/client.dart';
import '../models/gig.dart';
import '../models/invoice.dart';
import '../repositories/client_repository.dart';
import '../repositories/gig_repository.dart';
import '../repositories/invoice_repository.dart';

class AiEntityCandidate<T> {
  final T entity;
  final int score;
  final String label;

  const AiEntityCandidate({
    required this.entity,
    required this.score,
    required this.label,
  });
}

class AiEntityResolution<T> {
  final T? selected;
  final List<AiEntityCandidate<T>> candidates;
  final String? reason;

  const AiEntityResolution({
    required this.selected,
    this.candidates = const [],
    this.reason,
  });

  bool get isResolved => selected != null;
  bool get isAmbiguous => selected == null && candidates.length > 1;
}

class AiEntityResolverService {
  AiEntityResolverService._();

  static final AiEntityResolverService instance = AiEntityResolverService._();

  Future<AiEntityResolution<Gig>> resolveGig(
    AiAssistantAction action, {
    bool onlyFacturable = false,
  }) async {
    final directId = _readString(action.resolvedEntityId) ??
        _readString(action.objetivo['gig_id']);
    if (directId != null) {
      final gig = await GigRepository.instance.getById(directId);
      if (gig != null) {
        return AiEntityResolution(selected: gig, candidates: const []);
      }
    }

    final gigs = await GigRepository.instance.getAll();
    if (gigs.isEmpty) {
      return const AiEntityResolution(
        selected: null,
        reason: 'No hay bolos para resolver.',
      );
    }

    final clients = await ClientRepository.instance.getAll();
    final invoices = await InvoiceRepository.instance.getAll();
    final clientById = {for (final client in clients) client.id: client};
    final invoiceByGigId = {for (final invoice in invoices) invoice.gigId: invoice};

    final selector = (_readString(action.objetivo['selector']) ?? '').toLowerCase();
    final contextGigIds = _readContextEntityIds(action, type: 'gig');

    var pool = gigs.where((gig) {
      if (gig.status == GigStatus.cancelado) return false;
      if (onlyFacturable && (!gig.facturable || gig.invoiceId != null)) return false;
      return true;
    }).toList();

    if (pool.isEmpty) {
      return const AiEntityResolution(
        selected: null,
        reason: 'No hay bolos válidos con esos filtros.',
      );
    }

    if (selector == 'ultimo_bolo' || selector == 'ultimo_bolo_facturable') {
      pool.sort((a, b) => b.fecha.compareTo(a.fecha));
      return AiEntityResolution(selected: pool.first, candidates: const []);
    }

    if (_containsAny(action, const ['ese bolo', 'el anterior', 'el último', 'ultimo'])) {
      final contextual = pool.where((gig) => contextGigIds.contains(gig.id)).toList();
      if (contextual.length == 1) {
        return AiEntityResolution(selected: contextual.first, candidates: const []);
      }
    }

    final sourceText = _sourceText(action);
    final clueDates = _extractDates(action, sourceText);
    final clueCurrentAmount = _extractCurrentAmount(action, sourceText);
    final clueInvoiceNumber = _extractInvoiceNumber(action, sourceText);
    final clueClientQuery = _extractClientQuery(action, sourceText);
    final clueGigName = _extractGigQuery(action, sourceText);
    final clueClientOrName = _extractClientOrNameQuery(
      action,
      sourceText,
      clueClientQuery: clueClientQuery,
      clueGigName: clueGigName,
    );

    _logResolver(
      'filtros',
      {
        'cliente_o_nombre': clueClientOrName,
        'cliente': clueClientQuery,
        'nombre': clueGigName,
        'fecha': clueDates.map(_isoDate).toList(),
        'importe_actual': clueCurrentAmount,
        'importe_nuevo': _extractUpdatedAmount(action, sourceText),
      },
    );
    _logCandidates(
      'antes_filtros_duros',
      pool,
      clientById,
    );

    final hasHardClientOrName = clueClientOrName != null;
    final hasHardDate = clueDates.isNotEmpty;
    final hasHardAmount = clueCurrentAmount != null;

    if (clueClientOrName != null) {
      final hardQuery = clueClientOrName;
      pool = pool.where((gig) {
        final client = clientById[gig.clientId];
        return _matchesClientOrName(
          gig,
          client,
          hardQuery,
          sourceText: sourceText,
        );
      }).toList();
    }
    if (hasHardDate) {
      pool = pool.where((gig) {
        return clueDates.any((date) => _sameDay(date, gig.fecha));
      }).toList();
    }
    if (hasHardAmount) {
      pool = pool.where((gig) {
        if (gig.cachet == null) return false;
        return (gig.cachet! - clueCurrentAmount).abs() < 0.01;
      }).toList();
    }

    _logCandidates(
      'despues_filtros_duros',
      pool,
      clientById,
    );

    if (pool.isEmpty && (hasHardClientOrName || hasHardDate || hasHardAmount)) {
      return const AiEntityResolution(
        selected: null,
        reason: 'No he encontrado un bolo que cumpla los filtros indicados.',
      );
    }

    final scored = <AiEntityCandidate<Gig>>[];
    for (final gig in pool) {
      final client = clientById[gig.clientId];
      final invoice = invoiceByGigId[gig.id];
      var score = 0;

      if (clueClientQuery != null && client != null) {
        if (_isExactClientMatch(client, clueClientQuery)) {
          score += 100;
        } else if (_isPartialClientMatch(client, clueClientQuery)) {
          score += 60;
        }
      }

      if (clueGigName != null && clueGigName.isNotEmpty) {
        final haystack = '${client?.nombre ?? ''} ${client?.alias ?? ''} ${gig.notas ?? ''}'.toLowerCase();
        if (haystack.contains(clueGigName.toLowerCase())) {
          score += 60;
        }
      }

      if (clueDates.isNotEmpty) {
        final exact = clueDates.any((date) => _sameDay(date, gig.fecha));
        if (exact) {
          score += 80;
        } else {
          final near = clueDates.any((date) => (gig.fecha.difference(date).inDays).abs() <= 1);
          if (near) score += 50;
        }
      }

      if (clueCurrentAmount != null && gig.cachet != null) {
        if ((gig.cachet! - clueCurrentAmount).abs() < 0.01) {
          score += 40;
        }
      }

      if (clueInvoiceNumber != null && invoice?.numero == clueInvoiceNumber) {
        score += 90;
      }

      if (score > 0) {
        scored.add(
          AiEntityCandidate(
            entity: gig,
            score: score,
            label: _gigLabel(gig, client),
          ),
        );
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    _logResolver(
      'score_final',
      {
        'candidatos': scored
            .map((candidate) => '${candidate.label} (score=${candidate.score})')
            .toList(),
      },
    );
    if (scored.isEmpty) {
      if (pool.length == 1 && !hasHardClientOrName && !hasHardDate && !hasHardAmount) {
        return AiEntityResolution(selected: pool.first, candidates: const []);
      }
      return const AiEntityResolution(
        selected: null,
        reason: 'Necesito más datos para identificar el bolo.',
      );
    }

    final best = scored.first;
    if (scored.length == 1 && best.score >= 80) {
      _logResolver('entidad_seleccionada', {'gig_id': best.entity.id, 'score': best.score});
      return AiEntityResolution(selected: best.entity, candidates: scored);
    }
    if (scored.length > 1) {
      final second = scored[1];
      if (best.score >= 120 && (best.score - second.score) >= 25) {
        _logResolver('entidad_seleccionada', {'gig_id': best.entity.id, 'score': best.score});
        return AiEntityResolution(selected: best.entity, candidates: scored);
      }
      return AiEntityResolution(
        selected: null,
        candidates: scored.take(5).toList(),
        reason: 'He encontrado varios bolos posibles.',
      );
    }
    return AiEntityResolution(
      selected: null,
      candidates: scored,
      reason: 'Necesito más datos para identificar el bolo.',
    );
  }

  Future<AiEntityResolution<Client>> resolveClient(
    AiAssistantAction action,
  ) async {
    final directId = _readString(action.resolvedEntityId) ??
        _readString(action.objetivo['client_id']);
    if (directId != null) {
      final client = await ClientRepository.instance.getById(directId);
      if (client != null) {
        return AiEntityResolution(selected: client, candidates: const []);
      }
    }
    final query = _extractClientQuery(action, _sourceText(action));
    if (query == null || query.isEmpty) {
      return const AiEntityResolution(selected: null, reason: 'Falta cliente.');
    }
    final clients = await ClientRepository.instance.search(query);
    if (clients.length == 1) {
      return AiEntityResolution(selected: clients.first, candidates: const []);
    }
    return AiEntityResolution(
      selected: null,
      candidates: clients
          .map(
            (client) => AiEntityCandidate(
              entity: client,
              score: _isExactClientMatch(client, query) ? 100 : 60,
              label: client.nombre,
            ),
          )
          .toList(),
      reason: clients.isEmpty
          ? 'No he encontrado el cliente.'
          : 'Hay varios clientes parecidos.',
    );
  }

  Future<AiEntityResolution<Invoice>> resolveInvoice(
    AiAssistantAction action,
  ) async {
    final directId = _readString(action.resolvedEntityId) ??
        _readString(action.objetivo['invoice_id']);
    if (directId != null) {
      final invoice = await InvoiceRepository.instance.getById(directId);
      if (invoice != null) {
        return AiEntityResolution(selected: invoice, candidates: const []);
      }
    }

    final invoices = await InvoiceRepository.instance.getAll();
    if (invoices.isEmpty) {
      return const AiEntityResolution(selected: null, reason: 'No hay facturas.');
    }
    final selector = (_readString(action.objetivo['selector']) ?? '').toLowerCase();
    if (selector == 'ultima_factura') {
      invoices.sort((a, b) => b.fecha.compareTo(a.fecha));
      return AiEntityResolution(selected: invoices.first, candidates: const []);
    }
    final number = _extractInvoiceNumber(action, _sourceText(action));
    if (number != null) {
      final byNumber = invoices.where((invoice) => invoice.numero == number).toList();
      if (byNumber.length == 1) {
        return AiEntityResolution(selected: byNumber.first, candidates: const []);
      }
      return AiEntityResolution(
        selected: null,
        candidates: byNumber
            .map(
              (invoice) => AiEntityCandidate(
                entity: invoice,
                score: 100,
                label: 'Factura #${invoice.numero}',
              ),
            )
            .toList(),
        reason: byNumber.isEmpty
            ? 'No he encontrado esa factura.'
            : 'Hay varias facturas candidatas.',
      );
    }
    return const AiEntityResolution(
      selected: null,
      reason: 'Necesito identificar una factura concreta.',
    );
  }

  List<String> _readContextEntityIds(
    AiAssistantAction action, {
    required String type,
  }) {
    final context = action.raw['_conversation_entities'];
    if (context is! List) return const [];
    return context
        .whereType<Map>()
        .where(
          (item) =>
              item['type']?.toString().trim().toLowerCase() ==
              type.toLowerCase(),
        )
        .map((item) => item['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }

  String _sourceText(AiAssistantAction action) {
    return (_readString(action.raw['_source_message']) ?? '').toLowerCase();
  }

  bool _containsAny(AiAssistantAction action, List<String> values) {
    final text = _sourceText(action);
    return values.any((value) => text.contains(value));
  }

  String? _extractGigQuery(AiAssistantAction action, String sourceText) {
    return _readString(action.objetivo['nombre']) ??
        _readString(action.objetivo['gig_nombre']) ??
        _readString(action.filtros['texto']) ??
        _quotedTerm(sourceText);
  }

  String? _extractClientQuery(AiAssistantAction action, String sourceText) {
    return _readString(action.objetivo['cliente']) ??
        _readString(action.objetivo['cliente_nombre']) ??
        _readString(action.cliente['nombre']) ??
        _matchAfter(sourceText, RegExp(r'bolo\s+de\s+([a-z0-9áéíóúñ ._-]+)')) ??
        _matchAfter(sourceText, RegExp(r'cliente\s+([a-z0-9áéíóúñ ._-]+)'));
  }

  int? _extractInvoiceNumber(AiAssistantAction action, String sourceText) {
    final fromAction = _readString(action.factura['numero']) ??
        _readString(action.objetivo['numero_factura']);
    final parsed = int.tryParse(fromAction ?? '');
    if (parsed != null) return parsed;
    final match = RegExp(r'factura\s*#?\s*(\d{1,8})').firstMatch(sourceText);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  double? _extractCurrentAmount(AiAssistantAction action, String sourceText) {
    final fromAction = action.filtros['importe_actual'] ?? action.objetivo['importe_actual'];
    if (fromAction is num) return fromAction.toDouble();
    if (fromAction is String) {
      final parsed = double.tryParse(fromAction.replaceAll(',', '.'));
      if (parsed != null) return parsed;
    }
    final deA = RegExp(
      r'de\s+(\d+(?:[.,]\d{1,2})?)\s*€?\s+a\s+(\d+(?:[.,]\d{1,2})?)\s*€?',
    ).firstMatch(sourceText);
    if (deA != null) {
      return double.tryParse(deA.group(1)!.replaceAll(',', '.'));
    }
    final match = RegExp(r'(\d+(?:[.,]\d{1,2})?)\s*€').firstMatch(sourceText);
    if (match == null) return null;
    return double.tryParse(match.group(1)!.replaceAll(',', '.'));
  }

  double? _extractUpdatedAmount(AiAssistantAction action, String sourceText) {
    final fromAction = action.cambios['importe'] ?? action.objetivo['importe'];
    if (fromAction is num) return fromAction.toDouble();
    if (fromAction is String) {
      final parsed = double.tryParse(fromAction.replaceAll(',', '.'));
      if (parsed != null) return parsed;
    }
    final deA = RegExp(
      r'de\s+(\d+(?:[.,]\d{1,2})?)\s*€?\s+a\s+(\d+(?:[.,]\d{1,2})?)\s*€?',
    ).firstMatch(sourceText);
    if (deA == null) return null;
    return double.tryParse(deA.group(2)!.replaceAll(',', '.'));
  }

  List<DateTime> _extractDates(AiAssistantAction action, String sourceText) {
    final dates = <DateTime>[];
    final rawDates = [
      _readString(action.filtros['fecha']),
      _readString(action.objetivo['fecha']),
      _readString(action.cambios['fecha']),
      _readString(action.filtros['fecha_desde']),
      _readString(action.filtros['fecha_hasta']),
    ].whereType<String>();
    for (final raw in rawDates) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) dates.add(DateTime(parsed.year, parsed.month, parsed.day));
    }
    dates.addAll(_parseSpanishDates(sourceText));
    return dates;
  }

  List<DateTime> _parseSpanishDates(String sourceText) {
    final now = DateTime.now();
    final monthByName = <String, int>{
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
    final result = <DateTime>[];
    final slash = RegExp(r'\b(\d{1,2})[\/.-](\d{1,2})(?:[\/.-](\d{2,4}))?\b');
    for (final m in slash.allMatches(sourceText)) {
      final day = int.tryParse(m.group(1) ?? '');
      final month = int.tryParse(m.group(2) ?? '');
      final year = int.tryParse(m.group(3) ?? '') ?? now.year;
      if (day == null || month == null) continue;
      result.add(DateTime(year < 100 ? year + 2000 : year, month, day));
    }
    final named = RegExp(
      r'\b(\d{1,2})\s+de\s+(enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|setiembre|octubre|noviembre|diciembre)(?:\s+de\s+(\d{4}))?\b',
    );
    for (final m in named.allMatches(sourceText)) {
      final day = int.tryParse(m.group(1) ?? '');
      final month = monthByName[m.group(2) ?? ''];
      final year = int.tryParse(m.group(3) ?? '') ?? now.year;
      if (day == null || month == null) continue;
      result.add(DateTime(year, month, day));
    }
    return result;
  }

  String _gigLabel(Gig gig, Client? client) {
    final year = gig.fecha.year.toString().padLeft(4, '0');
    final month = gig.fecha.month.toString().padLeft(2, '0');
    final day = gig.fecha.day.toString().padLeft(2, '0');
    final amount = gig.cachet == null ? '' : ' - ${gig.cachet!.toStringAsFixed(2)} €';
    return '$day/$month/$year - ${client?.nombre ?? 'Cliente'}$amount';
  }

  bool _isExactClientMatch(Client client, String query) {
    final q = _normalize(query);
    final values = <String>[
      client.nombre,
      client.alias,
      ...client.aliases,
    ].map(_normalize);
    return values.contains(q);
  }

  bool _isPartialClientMatch(Client client, String query) {
    final q = _normalize(query);
    final values = <String>[
      client.nombre,
      client.alias,
      ...client.aliases,
    ].map(_normalize);
    return values.any((value) => value.contains(q) || q.contains(value));
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String? _quotedTerm(String sourceText) {
    final m = RegExp(r'"([^"]+)"').firstMatch(sourceText);
    final text = m?.group(1)?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  String? _matchAfter(String text, RegExp pattern) {
    final match = pattern.firstMatch(text);
    final value = match?.group(1)?.trim() ?? '';
    if (value.isEmpty) return null;
    final clean = value
        .replaceAll(RegExp(r'\s+(del?|al?)\s+\d{1,2}.*$'), '')
        .replaceAll(RegExp(r'\s+a\s+\d+[.,]?\d*\s*€.*$'), '')
        .trim();
    return clean.isEmpty ? null : clean;
  }

  String _normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String? _extractClientOrNameQuery(
    AiAssistantAction action,
    String sourceText, {
    String? clueClientQuery,
    String? clueGigName,
  }) {
    return _readString(action.filtros['cliente_o_nombre']) ??
        clueClientQuery ??
        clueGigName ??
        _matchAfter(sourceText, RegExp(r'bolo\s+de\s+([a-z0-9áéíóúñ ._-]+)'));
  }

  bool _matchesClientOrName(
    Gig gig,
    Client? client,
    String query, {
    required String sourceText,
  }) {
    final normalized = _normalize(query);
    if (client != null) {
      if (_isExactClientMatch(client, query) || _isPartialClientMatch(client, query)) {
        return true;
      }
    }
    final haystack = _normalize(
      '${client?.nombre ?? ''} ${client?.alias ?? ''} ${(client?.aliases.join(' ') ?? '')} ${gig.notas ?? ''}',
    );
    if (haystack.contains(normalized)) return true;
    final quoted = _quotedTerm(sourceText);
    if (quoted != null && haystack.contains(_normalize(quoted))) return true;
    return false;
  }

  void _logResolver(String stage, Map<String, Object?> payload) {
    debugPrint('[AiEntityResolver][Gig][$stage] $payload');
  }

  void _logCandidates(
    String stage,
    List<Gig> gigs,
    Map<String, Client> clientById,
  ) {
    final values = gigs
        .map((gig) => _gigLabel(gig, clientById[gig.clientId]))
        .toList();
    debugPrint('[AiEntityResolver][Gig][$stage] count=${gigs.length} values=$values');
  }

  String _isoDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String? _readString(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}
