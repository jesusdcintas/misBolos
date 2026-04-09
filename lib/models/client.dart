import 'package:uuid/uuid.dart';

class Client {
  final String id;
  final String nombre;
  final String alias;
  final String cifNif;
  final String direccion;
  final String ciudad;
  final String provincia;
  final String codigoPostal;
  final String? email;
  final String? telefono;
  final DateTime createdAt;
  final DateTime updatedAt;

  Client({
    String? id,
    required this.nombre,
    this.alias = '',
    this.cifNif = '',
    this.direccion = '',
    this.ciudad = '',
    this.provincia = '',
    this.codigoPostal = '',
    this.email,
    this.telefono,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Client copyWith({
    String? nombre,
    String? alias,
    String? cifNif,
    String? direccion,
    String? ciudad,
    String? provincia,
    String? codigoPostal,
    String? email,
    String? telefono,
    DateTime? updatedAt,
  }) {
    return Client(
      id: id,
      nombre: nombre ?? this.nombre,
      alias: alias ?? this.alias,
      cifNif: cifNif ?? this.cifNif,
      direccion: direccion ?? this.direccion,
      ciudad: ciudad ?? this.ciudad,
      provincia: provincia ?? this.provincia,
      codigoPostal: codigoPostal ?? this.codigoPostal,
      email: email ?? this.email,
      telefono: telefono ?? this.telefono,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'alias': alias,
      'cif_nif': cifNif,
      'direccion': direccion,
      'ciudad': ciudad,
      'provincia': provincia,
      'codigo_postal': codigoPostal,
      'email': email,
      'telefono': telefono,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Client.fromMap(Map<String, dynamic> map) {
    return Client(
      id: map['id'] as String,
      nombre: map['nombre'] as String,
      alias: map['alias'] as String? ?? '',
      cifNif: map['cif_nif'] as String? ?? '',
      direccion: map['direccion'] as String? ?? '',
      ciudad: map['ciudad'] as String? ?? '',
      provincia: map['provincia'] as String? ?? '',
      codigoPostal: map['codigo_postal'] as String? ?? '',
      email: map['email'] as String?,
      telefono: map['telefono'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
