import 'package:flutter/foundation.dart';

import '../models/ai_assistant.dart';
import 'date_resolver_service.dart';

class AiConversationContext {
  final Map<String, dynamic>? pendingAction;
  final List<Map<String, dynamic>> pendingBulkEntities;
  final List<String> missingFields;
  final Map<String, dynamic> partialData;
  final String? lastCreatedActionId;
  final Map<String, String>? lastReferencedEntity;
  final String? lastPreviewAction;

  const AiConversationContext({
    this.pendingAction,
    this.pendingBulkEntities = const [],
    this.missingFields = const [],
    this.partialData = const {},
    this.lastCreatedActionId,
    this.lastReferencedEntity,
    this.lastPreviewAction,
  });

  bool get hasPendingCreateBolo => pendingAction?['action'] == 'crear_bolo';
  bool get hasPendingBulkCreateBolos => pendingBulkEntities.isNotEmpty;

  Map<String, dynamic> toMap() => {
    if (pendingAction != null) 'pending_action': pendingAction,
    if (pendingBulkEntities.isNotEmpty)
      'pending_bulk_entities': pendingBulkEntities,
    'missing_fields': missingFields,
    'partial_data': partialData,
    if (lastCreatedActionId != null) 'last_created_action_id': lastCreatedActionId,
    if (lastReferencedEntity != null)
      'last_referenced_entity': lastReferencedEntity,
    if (lastPreviewAction != null) 'last_preview_action': lastPreviewAction,
  };

  factory AiConversationContext.fromMap(Map<String, dynamic> map) {
    final missing = map['missing_fields'];
    final partial = map['partial_data'];
    final bulk = map['pending_bulk_entities'];
    return AiConversationContext(
      pendingAction: map['pending_action'] is Map
          ? Map<String, dynamic>.from(map['pending_action'] as Map)
          : null,
      pendingBulkEntities: bulk is List
          ? bulk
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : const [],
      missingFields: missing is List
          ? missing.map((item) => item.toString()).toList()
          : const [],
      partialData: partial is Map
          ? Map<String, dynamic>.from(partial)
          : const {},
      lastCreatedActionId: map['last_created_action_id']?.toString(),
      lastReferencedEntity: map['last_referenced_entity'] is Map
          ? Map<String, String>.from(map['last_referenced_entity'] as Map)
          : null,
      lastPreviewAction: map['last_preview_action']?.toString(),
    );
  }
}

class PendingResolutionResult {
  final AiAssistantAction? action;
  final AiConversationContext context;
  final String? assistantMessage;

  const PendingResolutionResult({
    required this.action,
    required this.context,
    this.assistantMessage,
  });
}

class AiConversationContextService {
  AiConversationContextService._();

  static final AiConversationContextService instance =
      AiConversationContextService._();

  AiConversationContext fromMessages(List<AiAssistantMessage> messages) {
    for (final message in messages.reversed) {
      final metadata = message.metadata;
      final raw = metadata?['conversation_context'];
      if (raw is Map) {
        return AiConversationContext.fromMap(Map<String, dynamic>.from(raw));
      }
    }
    return const AiConversationContext();
  }

  Map<String, dynamic> attach(
    Map<String, dynamic> metadata,
    AiConversationContext context,
  ) {
    final next = <String, dynamic>{...metadata};
    next['conversation_context'] = context.toMap();
    return next;
  }

  AiConversationContext fromAction({
    required AiAssistantAction action,
    required AiConversationContext current,
  }) {
    if (action.accion == 'crear_bolos') {
      if (action.bolos.isEmpty) return current;
      final entities = <Map<String, dynamic>>[];
      for (var i = 0; i < action.bolos.length; i++) {
        final draft = action.bolos[i];
        final entity = <String, dynamic>{
          'temp_id': 'bulk_${DateTime.now().microsecondsSinceEpoch}_$i',
          'cliente': draft.nombre.trim(),
          'fecha': (draft.fecha ?? '').trim(),
          'importe': draft.importe,
          'facturable': draft.facturable,
        };
        final missing = _missingFieldsFromEntity(entity);
        entity['missing_fields'] = missing;
        entity['ready_to_create'] = missing.isEmpty;
        entities.add(entity);
      }
      final hasMissing = entities.any(
        (entity) => (entity['missing_fields'] as List<String>).isNotEmpty,
      );
      if (hasMissing) {
        if (entities.length > 1) {
          return AiConversationContext(
            pendingAction: null,
            pendingBulkEntities: entities,
            missingFields: const [],
            partialData: const {},
            lastCreatedActionId: current.lastCreatedActionId,
            lastPreviewAction: action.accion,
            lastReferencedEntity: current.lastReferencedEntity,
          );
        }
        final only = entities.first;
        return AiConversationContext(
          pendingAction: {'action': 'crear_bolo'},
          pendingBulkEntities: const [],
          missingFields: (only['missing_fields'] as List<String>),
          partialData: {
            'cliente_o_nombre': only['cliente'],
            'fecha': only['fecha'],
            if (only['importe'] != null) 'importe': only['importe'],
            if (only['facturable'] != null) 'facturable': only['facturable'],
          },
          lastCreatedActionId: current.lastCreatedActionId,
          lastPreviewAction: action.accion,
          lastReferencedEntity: current.lastReferencedEntity,
        );
      }
    }
    return AiConversationContext(
      pendingAction: null,
      pendingBulkEntities: const [],
      missingFields: const [],
      partialData: const {},
      lastCreatedActionId: current.lastCreatedActionId,
      lastPreviewAction: action.accion,
      lastReferencedEntity: action.resolvedEntityId == null
          ? current.lastReferencedEntity
          : {
              'entity_type': 'gig',
              'entity_id': action.resolvedEntityId!,
              'entity_name': 'Bolo',
            },
    );
  }

  PendingResolutionResult tryResolvePending({
    required AiConversationContext context,
    required String message,
    required DateTime now,
  }) {
    debugPrint('[AiConversationContext] pending_before=${context.toMap()}');
    if (context.hasPendingBulkCreateBolos) {
      return _resolvePendingBulk(context: context, message: message, now: now);
    }
    if (!context.hasPendingCreateBolo) {
      return PendingResolutionResult(action: null, context: context);
    }
    final text = message.trim();
    final partial = <String, dynamic>{...context.partialData};
    final before = <String, dynamic>{...partial};
    final missingBefore = _missingFields(partial);

    final amount = _extractAmount(text);
    if (amount != null) {
      partial['importe'] = amount;
      _logContextFieldMatch(
        matchedField: 'importe',
        value: amount,
        partialDataBefore: before,
        partialDataAfter: partial,
      );
    } else {
      final facturable = _extractFacturable(text);
      if (facturable != null) {
        partial['facturable'] = facturable;
        _logContextFieldMatch(
          matchedField: 'facturable',
          value: facturable,
          partialDataBefore: before,
          partialDataAfter: partial,
        );
      } else {
        final dateToken = DateResolverService.instance.extractRelativeDateTokens(
          text,
        );
        if (dateToken.isNotEmpty) {
          final date = DateResolverService.instance.resolveExpression(
            dateToken.first,
            now: now,
          );
          if (date != null) {
            final resolved = _iso(date);
            partial['fecha'] = resolved;
            _logContextFieldMatch(
              matchedField: 'fecha',
              value: resolved,
              partialDataBefore: before,
              partialDataAfter: partial,
            );
          }
        } else if (missingBefore.contains('cliente_o_nombre') &&
            _looksLikeName(text)) {
          partial['cliente_o_nombre'] = text;
          _logContextFieldMatch(
            matchedField: 'cliente_o_nombre',
            value: text,
            partialDataBefore: before,
            partialDataAfter: partial,
          );
        }
      }
    }

    final missing = _missingFields(partial);
    final canExecute = canExecuteCreateGig(partial);
    debugPrint('[AiConversationContext] canExecuteCreateGig=$canExecute');

    if (!canExecute) {
      final updated = AiConversationContext(
        pendingAction: context.pendingAction,
        pendingBulkEntities: const [],
        missingFields: missing,
        partialData: partial,
        lastCreatedActionId: context.lastCreatedActionId,
        lastPreviewAction: context.lastPreviewAction,
        lastReferencedEntity: context.lastReferencedEntity,
      );
      debugPrint('[AiConversationContext] pending_after=${updated.toMap()}');
      return PendingResolutionResult(
        action: null,
        context: updated,
        assistantMessage: _questionForMissing(missing.first),
      );
    }

    final action = _singleActionFromPartial(partial, sourceMessage: message);
    final nextContext = AiConversationContext(
      pendingAction: null,
      pendingBulkEntities: const [],
      missingFields: const [],
      partialData: const {},
      lastCreatedActionId: context.lastCreatedActionId,
      lastPreviewAction: 'crear_bolos',
      lastReferencedEntity: context.lastReferencedEntity,
    );
    debugPrint('[AiConversationContext] pending_after=${nextContext.toMap()}');
    return PendingResolutionResult(action: action, context: nextContext);
  }

  PendingResolutionResult _resolvePendingBulk({
    required AiConversationContext context,
    required String message,
    required DateTime now,
  }) {
    final text = message.trim();
    final lower = text.toLowerCase();
    final entities = context.pendingBulkEntities
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final amount = _extractAmount(text);
    final facturable = _extractFacturable(text);
    final dateToken = DateResolverService.instance.extractRelativeDateTokens(text);
    final global = lower.startsWith('todos') || lower.startsWith('todas');

    void apply(Map<String, dynamic> entity) {
      if (amount != null) {
        entity['importe'] = amount;
      }
      if (facturable != null) {
        entity['facturable'] = facturable;
      }
      if (dateToken.isNotEmpty) {
        final date = DateResolverService.instance.resolveExpression(
          dateToken.first,
          now: now,
        );
        if (date != null) {
          entity['fecha'] = _iso(date);
        }
      }
      final missing = _missingFieldsFromEntity(entity);
      entity['missing_fields'] = missing;
      entity['ready_to_create'] = missing.isEmpty;
      _logBulkUpdate(
        target: entity['cliente']?.toString() ?? 'desconocido',
        field: amount != null
            ? 'importe'
            : facturable != null
            ? 'facturable'
            : dateToken.isNotEmpty
            ? 'fecha'
            : 'none',
        value: amount ?? facturable ?? entity['fecha'],
        remainingMissing: missing,
      );
    }

    if (global) {
      for (final entity in entities) {
        apply(entity);
      }
    } else {
      var matchedAny = false;
      for (final entity in entities) {
        final name = (entity['cliente']?.toString() ?? '').toLowerCase();
        if (name.isNotEmpty && lower.contains(name)) {
          matchedAny = true;
          apply(entity);
        }
      }
      if (!matchedAny) {
        final unresolved = entities
            .where(
              (entity) =>
                  (entity['missing_fields'] as List<String>).isNotEmpty,
            )
            .toList();
        if (unresolved.length == 1 || amount != null || facturable != null) {
          for (final entity in unresolved) {
            apply(entity);
          }
        }
      }
    }

    final action = _bulkActionFromEntities(entities, sourceMessage: message);
    final allReady = entities.every(
      (entity) => (entity['missing_fields'] as List<String>).isEmpty,
    );
    final nextContext = AiConversationContext(
      pendingAction: null,
      pendingBulkEntities: allReady ? const [] : entities,
      missingFields: const [],
      partialData: const {},
      lastCreatedActionId: context.lastCreatedActionId,
      lastPreviewAction: 'crear_bolos',
      lastReferencedEntity: context.lastReferencedEntity,
    );
    return PendingResolutionResult(
      action: action,
      context: nextContext,
      assistantMessage: allReady
          ? null
          : 'He actualizado los bolos pendientes. Completa los campos que faltan para confirmar.',
    );
  }

  bool canExecuteCreateGig(Map<String, dynamic> partial) {
    return _missingFields(partial).isEmpty;
  }

  String _questionForMissing(String field) {
    switch (field) {
      case 'importe':
        return '¿Qué importe tendrá el bolo?';
      case 'fecha':
        return '¿Qué fecha tendrá el bolo?';
      case 'facturable':
        return '¿Será facturable o no facturable?';
      default:
        return '¿Para qué cliente o nombre quieres crear el bolo?';
    }
  }

  bool? _extractFacturable(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('no facturable') ||
        lower.contains(' en b') ||
        lower.contains('sin factura')) {
      return false;
    }
    if (lower == 'facturable' ||
        lower == 'sí facturable' ||
        lower == 'si facturable' ||
        lower.contains('con factura') ||
        lower.contains('oficial') ||
        lower.contains('facturable') ||
        lower == 'si' ||
        lower == 'sí') {
      return true;
    }
    if (lower == 'no') return false;
    return null;
  }

  double? _extractAmount(String text) {
    final m = RegExp(r'(\d+(?:[.,]\d+)?)[ ]*€').firstMatch(text);
    if (m == null) return null;
    return double.tryParse(m.group(1)!.replaceAll(',', '.'));
  }

  bool _looksLikeName(String text) {
    final lower = text.toLowerCase().trim();
    if (lower.isEmpty) return false;
    if (RegExp(r'^\d').hasMatch(lower)) return false;
    if (lower.length < 2) return false;
    if (lower.contains('€')) return false;
    if (lower == 'si' || lower == 'sí' || lower == 'no') return false;
    return true;
  }

  String _iso(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  List<String> _missingFields(Map<String, dynamic> partial) {
    return <String>[
      if ((partial['cliente_o_nombre']?.toString().trim() ?? '').isEmpty)
        'cliente_o_nombre',
      if ((partial['fecha']?.toString().trim() ?? '').isEmpty) 'fecha',
      if (partial['importe'] == null) 'importe',
      if (partial['facturable'] == null) 'facturable',
    ];
  }

  List<String> _missingFieldsFromEntity(Map<String, dynamic> entity) {
    return <String>[
      if ((entity['cliente']?.toString().trim() ?? '').isEmpty) 'cliente',
      if ((entity['fecha']?.toString().trim() ?? '').isEmpty) 'fecha',
      if (entity['importe'] == null) 'importe',
      if (entity['facturable'] == null) 'facturable',
    ];
  }

  AiAssistantAction _singleActionFromPartial(
    Map<String, dynamic> partial, {
    required String sourceMessage,
  }) {
    final raw = <String, dynamic>{
      'accion': 'crear_bolos',
      'requiere_confirmacion': true,
      'confianza': 0.95,
      'bolos': [
        {
          'fecha': partial['fecha'],
          'nombre': partial['cliente_o_nombre'],
          'importe': partial['importe'],
          'facturable': partial['facturable'],
          'estado': 'pendiente_gestion',
          'notas': null,
        },
      ],
      'filtros': const <String, dynamic>{},
      'objetivo': const <String, dynamic>{},
      'updates': const <String, dynamic>{},
      'cliente': const <String, dynamic>{},
      'clientes': const <dynamic>[],
      'factura': const <String, dynamic>{},
      'email': const <String, dynamic>{},
      'advertencias': const <dynamic>[],
      '_source_message': sourceMessage,
    };
    return AiAssistantAction.fromJson(raw);
  }

  AiAssistantAction _bulkActionFromEntities(
    List<Map<String, dynamic>> entities, {
    required String sourceMessage,
  }) {
    final bolos = entities
        .map(
          (entity) => {
            'fecha': entity['fecha'],
            'nombre': entity['cliente'],
            'importe': entity['importe'],
            'facturable': entity['facturable'],
            'estado': 'pendiente_gestion',
            'notas': null,
          },
        )
        .toList();
    final raw = <String, dynamic>{
      'accion': 'crear_bolos',
      'requiere_confirmacion': true,
      'confianza': 0.95,
      'bolos': bolos,
      'filtros': const <String, dynamic>{},
      'objetivo': const <String, dynamic>{},
      'updates': const <String, dynamic>{},
      'cliente': const <String, dynamic>{},
      'clientes': const <dynamic>[],
      'factura': const <String, dynamic>{},
      'email': const <String, dynamic>{},
      'advertencias': const <dynamic>[],
      '_source_message': sourceMessage,
    };
    return AiAssistantAction.fromJson(raw);
  }

  void _logContextFieldMatch({
    required String matchedField,
    required Object? value,
    required Map<String, dynamic> partialDataBefore,
    required Map<String, dynamic> partialDataAfter,
  }) {
    debugPrint(
      '[CONTEXT_FIELD_MATCH] matchedField=$matchedField value=$value partialDataBefore=$partialDataBefore partialDataAfter=$partialDataAfter',
    );
  }

  void _logBulkUpdate({
    required String target,
    required String field,
    required Object? value,
    required List<String> remainingMissing,
  }) {
    debugPrint(
      '[BULK_PENDING_UPDATE] target=$target field=$field value=$value remainingMissing=$remainingMissing',
    );
  }
}
