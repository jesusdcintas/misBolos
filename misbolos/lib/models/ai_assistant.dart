import 'dart:convert';

import 'package:uuid/uuid.dart';

enum AiAssistantMessageRole {
  user,
  assistant,
  system;

  static AiAssistantMessageRole fromDb(String value) {
    return AiAssistantMessageRole.values.firstWhere(
      (role) => role.name == value,
      orElse: () => AiAssistantMessageRole.assistant,
    );
  }
}

enum AiActionStatus {
  pendingConfirmation,
  executing,
  completed,
  failed;

  static AiActionStatus fromValue(String? value) {
    switch (value) {
      case 'executing':
        return AiActionStatus.executing;
      case 'completed':
        return AiActionStatus.completed;
      case 'failed':
        return AiActionStatus.failed;
      default:
        return AiActionStatus.pendingConfirmation;
    }
  }

  String get value {
    switch (this) {
      case AiActionStatus.pendingConfirmation:
        return 'pending_confirmation';
      case AiActionStatus.executing:
        return 'executing';
      case AiActionStatus.completed:
        return 'completed';
      case AiActionStatus.failed:
        return 'failed';
    }
  }
}

class AiChat {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;

  AiChat({
    String? id,
    required this.title,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isActive = false,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'is_active': isActive ? 1 : 0,
  };

  factory AiChat.fromMap(Map<String, dynamic> map) => AiChat(
    id: map['id'] as String,
    title: map['title'] as String,
    createdAt: DateTime.parse(map['created_at'] as String),
    updatedAt: DateTime.parse(map['updated_at'] as String),
    isActive: (map['is_active'] as int? ?? 0) == 1,
  );
}

class AiAssistantMessage {
  final String id;
  final AiAssistantMessageRole role;
  final String text;
  final AiAssistantAction? action;
  final AiActionPreview? preview;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;

  AiAssistantMessage({
    String? id,
    required this.role,
    required this.text,
    this.action,
    this.preview,
    this.metadata,
    DateTime? createdAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  String? get actionId => _string(metadata?['action_id']);

  AiActionStatus? get actionStatus {
    final value = _string(metadata?['action_status']);
    if (value == null) return null;
    return AiActionStatus.fromValue(value);
  }

  Map<String, dynamic> toMap({required String chatId}) => {
    'id': id,
    'chat_id': chatId,
    'role': role.name,
    'content': text,
    'created_at': createdAt.toIso8601String(),
    'metadata_json': metadata == null || metadata!.isEmpty
        ? null
        : jsonEncode(metadata),
  };
}

class AiAssistantIntent {
  final String name;
  final double confidence;
  final bool requiresConfirmation;

  const AiAssistantIntent({
    required this.name,
    required this.confidence,
    required this.requiresConfirmation,
  });
}

class AiAssistantAction {
  final String accion;
  final bool requiereConfirmacion;
  final double confianza;
  final String? resolvedEntityId;
  final String? resolvedEntityType;
  final String? pregunta;
  final String? respuesta;
  final List<AiBoloDraft> bolos;
  final Map<String, dynamic> filtros;
  final Map<String, dynamic> objetivo;
  final Map<String, dynamic> cambios;
  final Map<String, dynamic> cliente;
  final List<AiClientDraft> clientes;
  final Map<String, dynamic> factura;
  final Map<String, dynamic> email;
  final List<String> advertencias;
  final Map<String, dynamic> raw;

  const AiAssistantAction({
    required this.accion,
    required this.requiereConfirmacion,
    required this.confianza,
    this.resolvedEntityId,
    this.resolvedEntityType,
    this.pregunta,
    this.respuesta,
    this.bolos = const [],
    this.filtros = const {},
    this.objetivo = const {},
    this.cambios = const {},
    this.cliente = const {},
    this.clientes = const [],
    this.factura = const {},
    this.email = const {},
    this.advertencias = const [],
    this.raw = const {},
  });

  AiAssistantIntent get intent => AiAssistantIntent(
    name: accion,
    confidence: confianza,
    requiresConfirmation: requiereConfirmacion,
  );

  factory AiAssistantAction.fromJson(Map<String, dynamic> json) {
    final parsedCambios = _map(json['cambios']);
    final parsedUpdates = _map(json['updates']);
    return AiAssistantAction(
      accion: _string(json['accion']) ?? 'pregunta_aclaratoria',
      requiereConfirmacion: json['requiere_confirmacion'] == true,
      confianza: _number(json['confianza']) ?? 0.7,
      resolvedEntityId: _string(json['resolved_entity_id']),
      resolvedEntityType: _string(json['resolved_entity_type']),
      pregunta: _string(json['pregunta']),
      respuesta: _string(json['respuesta']),
      bolos: _list(json['bolos'])
          .whereType<Map>()
          .map((item) => AiBoloDraft.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      filtros: _map(json['filtros']),
      objetivo: _map(json['objetivo']),
      cambios: parsedCambios.isNotEmpty ? parsedCambios : parsedUpdates,
      cliente: _map(json['cliente']),
      clientes: _list(json['clientes'])
          .whereType<Map>()
          .map(
            (item) => AiClientDraft.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      factura: _map(json['factura']),
      email: _map(json['email']),
      advertencias: _list(json['advertencias'])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(),
      raw: json,
    );
  }
}

class AiAssistantActionResult {
  final String message;
  final AiActionPreview? preview;
  final Map<String, String>? referencedEntity;

  const AiAssistantActionResult({
    required this.message,
    this.preview,
    this.referencedEntity,
  });
}

class AiClientDraft {
  final String nombre;
  final String aliasPrincipal;
  final List<String> nombresAlternativos;
  final String cifNif;
  final String direccion;
  final String ciudad;
  final String codigoPostal;
  final String provincia;
  final String email;
  final String telefono;
  final String telefonoWhatsapp;
  final String notas;

  const AiClientDraft({
    required this.nombre,
    required this.aliasPrincipal,
    required this.nombresAlternativos,
    required this.cifNif,
    required this.direccion,
    required this.ciudad,
    required this.codigoPostal,
    required this.provincia,
    required this.email,
    required this.telefono,
    required this.telefonoWhatsapp,
    required this.notas,
  });

  bool get hasName => nombre.trim().isNotEmpty;

  factory AiClientDraft.fromJson(Map<String, dynamic> json) {
    return AiClientDraft(
      nombre: _string(json['nombre']) ?? '',
      aliasPrincipal: _string(json['alias_principal']) ?? '',
      nombresAlternativos: _list(json['nombres_alternativos'])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(),
      cifNif: _string(json['cif_nif']) ?? '',
      direccion: _string(json['direccion']) ?? '',
      ciudad: _string(json['ciudad']) ?? '',
      codigoPostal: _string(json['codigo_postal']) ?? '',
      provincia: _string(json['provincia']) ?? '',
      email: _string(json['email']) ?? '',
      telefono: _string(json['telefono']) ?? '',
      telefonoWhatsapp: _string(json['telefono_whatsapp']) ?? '',
      notas: _string(json['notas']) ?? '',
    );
  }
}

class AiBoloDraft {
  final String? fecha;
  final String nombre;
  final double? importe;
  final bool? facturable;
  final String estado;
  final String? notas;

  const AiBoloDraft({
    required this.fecha,
    required this.nombre,
    required this.importe,
    required this.facturable,
    required this.estado,
    this.notas,
  });

  factory AiBoloDraft.fromJson(Map<String, dynamic> json) {
    return AiBoloDraft(
      fecha: _string(json['fecha']),
      nombre:
          _string(json['nombre']) ?? _string(json['cliente']) ?? 'Sin nombre',
      importe: _number(json['importe']),
      facturable: json['facturable'] is bool ? json['facturable'] as bool : null,
      estado: _string(json['estado']) ?? 'pendiente_gestion',
      notas: _string(json['notas']),
    );
  }
}

class AiActionPreview {
  final String title;
  final String description;
  final List<String> items;
  final bool requiresConfirmation;
  final bool executable;

  const AiActionPreview({
    required this.title,
    required this.description,
    this.items = const [],
    required this.requiresConfirmation,
    required this.executable,
  });
}

Map<String, dynamic> aiActionMetadata({
  AiAssistantAction? action,
  AiActionPreview? preview,
  String? actionId,
  AiActionStatus? actionStatus,
}) {
  return {
    if (action != null) 'action': action.raw,
    if (actionId != null && actionId.trim().isNotEmpty) 'action_id': actionId,
    if (actionStatus != null) 'action_status': actionStatus.value,
    if (preview != null)
      'preview': {
        'title': preview.title,
        'description': preview.description,
        'items': preview.items,
        'requires_confirmation': preview.requiresConfirmation,
        'executable': preview.executable,
      },
  };
}

AiAssistantAction? aiActionFromMetadata(Map<String, dynamic>? metadata) {
  final rawAction = metadata?['action'];
  if (rawAction is Map) {
    return AiAssistantAction.fromJson(Map<String, dynamic>.from(rawAction));
  }
  return null;
}

AiActionPreview? aiPreviewFromMetadata(Map<String, dynamic>? metadata) {
  final rawPreview = metadata?['preview'];
  if (rawPreview is! Map) return null;
  final map = Map<String, dynamic>.from(rawPreview);
  return AiActionPreview(
    title: _string(map['title']) ?? 'Vista previa',
    description: _string(map['description']) ?? '',
    items: _list(map['items']).map((item) => item.toString()).toList(),
    requiresConfirmation: map['requires_confirmation'] == true,
    executable: map['executable'] == true,
  );
}

String? _string(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.replaceAll(',', '.'));
  return null;
}

List<dynamic> _list(Object? value) => value is List ? value : const [];

Map<String, dynamic> _map(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}
