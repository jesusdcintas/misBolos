import 'dart:convert';
import 'package:uuid/uuid.dart';

class Client {
  final String id;
  final String nombre;
  final String alias;
  final List<String> aliases;
  final String cifNif;
  final String direccion;
  final String ciudad;
  final String provincia;
  final String codigoPostal;
  final String? email;
  final String? telefono;
  final String? whatsappPhone;
  final String notas;
  final DateTime createdAt;
  final DateTime updatedAt;

  Client({
    String? id,
    required this.nombre,
    this.alias = '',
    this.aliases = const [],
    this.cifNif = '',
    this.direccion = '',
    this.ciudad = '',
    this.provincia = '',
    this.codigoPostal = '',
    this.email,
    this.telefono,
    this.whatsappPhone,
    this.notas = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Client copyWith({
    String? nombre,
    String? alias,
    List<String>? aliases,
    String? cifNif,
    String? direccion,
    String? ciudad,
    String? provincia,
    String? codigoPostal,
    String? email,
    String? telefono,
    String? whatsappPhone,
    String? notas,
    DateTime? updatedAt,
  }) {
    return Client(
      id: id,
      nombre: nombre ?? this.nombre,
      alias: alias ?? this.alias,
      aliases: aliases ?? this.aliases,
      cifNif: cifNif ?? this.cifNif,
      direccion: direccion ?? this.direccion,
      ciudad: ciudad ?? this.ciudad,
      provincia: provincia ?? this.provincia,
      codigoPostal: codigoPostal ?? this.codigoPostal,
      email: email ?? this.email,
      telefono: telefono ?? this.telefono,
      whatsappPhone: whatsappPhone ?? this.whatsappPhone,
      notas: notas ?? this.notas,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'alias': alias,
      'aliases': jsonEncode(aliases),
      'cif_nif': cifNif,
      'direccion': direccion,
      'ciudad': ciudad,
      'provincia': provincia,
      'codigo_postal': codigoPostal,
      'email': email,
      'telefono': telefono,
      'whatsapp_phone': whatsappPhone,
      'notas': notas,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Client.fromMap(Map<String, dynamic> map) {
    return Client(
      id: map['id'] as String,
      nombre: map['nombre'] as String,
      alias: map['alias'] as String? ?? '',
      aliases: map['aliases'] != null
          ? List<String>.from(jsonDecode(map['aliases'] as String))
          : [],
      cifNif: map['cif_nif'] as String? ?? '',
      direccion: map['direccion'] as String? ?? '',
      ciudad: map['ciudad'] as String? ?? '',
      provincia: map['provincia'] as String? ?? '',
      codigoPostal: map['codigo_postal'] as String? ?? '',
      email: map['email'] as String?,
      telefono: map['telefono'] as String?,
      whatsappPhone: map['whatsapp_phone'] as String?,
      notas: map['notas'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
