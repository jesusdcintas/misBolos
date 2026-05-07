import 'dart:convert';
import 'dart:io';

import '../models/expense_extraction_result.dart';
import 'supabase_service.dart';

class ExpenseExtractionService {
  ExpenseExtractionService._();

  static final ExpenseExtractionService instance = ExpenseExtractionService._();

  Future<ExpenseExtractionResult> extractFromDocumentPath(String path) async {
    if (!SupabaseService.instance.isAuthenticated) {
      throw Exception('Debes iniciar sesión para usar extracción IA.');
    }

    final file = File(path);
    if (!await file.exists()) {
      throw Exception('No se encontró el documento seleccionado.');
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('El documento está vacío.');
    }
    if (bytes.length > 8 * 1024 * 1024) {
      throw Exception(
        'El archivo es demasiado grande para extracción rápida (máx. 8MB).',
      );
    }

    final extension = _extension(path);
    final mimeType = _mimeTypeFor(extension);
    final payload = <String, dynamic>{
      'file_name': file.uri.pathSegments.isNotEmpty
          ? file.uri.pathSegments.last
          : 'documento',
      'mime_type': mimeType,
      'base64_data': base64Encode(bytes),
    };

    final data = await SupabaseService.instance.invokeFunction(
      'extract-expense-data',
      body: payload,
    );

    if (data is! Map<String, dynamic>) {
      throw Exception('Respuesta inválida de extracción IA.');
    }
    if (data['ok'] != true) {
      final message = data['error']?.toString().trim();
      throw Exception(message?.isNotEmpty == true
          ? message
          : 'No se pudo extraer la factura.');
    }

    final extracted = data['extracted'];
    if (extracted is! Map<String, dynamic>) {
      throw Exception('No se recibieron datos de extracción.');
    }

    return ExpenseExtractionResult.fromMap(extracted);
  }

  String _extension(String path) {
    final fileName = path.split('/').last.toLowerCase();
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1);
  }

  String _mimeTypeFor(String extension) {
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }
}
