import 'package:flutter/foundation.dart';

import 'supabase_service.dart';

class AiService {
  AiService._();

  static final AiService instance = AiService._();

  static const int _maxMessageLength = 6000;
  static const int _maxContextLength = 8000;

  Future<Map<String, dynamic>> _invoke({
    required String taskType,
    required String message,
    Map<String, dynamic>? contextData,
    String? imageText,
    String? imageBase64,
    String? imageMimeType,
    String? inputType,
  }) async {
    if (!SupabaseService.instance.isAuthenticated) {
      throw Exception('Debes iniciar sesión para usar IA.');
    }

    final trimmedMessage = message.trim();
    if (trimmedMessage.isEmpty) {
      throw Exception('El mensaje no puede estar vacío.');
    }

    final payload = <String, dynamic>{
      'task_type': taskType,
      'message': _truncate(trimmedMessage, _maxMessageLength),
      if (inputType != null && inputType.trim().isNotEmpty)
        'input_type': inputType.trim(),
      if (contextData != null) 'context_data': _truncateMap(contextData),
      if (imageText != null && imageText.trim().isNotEmpty)
        'image_text': _truncate(imageText.trim(), _maxContextLength),
      if (imageBase64 != null && imageBase64.trim().isNotEmpty)
        'image_base64': imageBase64.trim(),
      if (imageMimeType != null && imageMimeType.trim().isNotEmpty)
        'image_mime_type': imageMimeType.trim(),
      if (imageMimeType != null && imageMimeType.trim().isNotEmpty)
        'mime_type': imageMimeType.trim(),
    };

    final data = await SupabaseService.instance.invokeFunction(
      'groq-assistant',
      body: payload,
    );
    if (data is! Map<String, dynamic>) {
      throw Exception('Respuesta IA inválida.');
    }

    if (data['ok'] != true) {
      final code = data['code']?.toString();
      if (code == 'rate_limit') {
        throw Exception(
          'Has alcanzado el límite gratuito temporal de IA. Inténtalo más tarde.',
        );
      }
      if (code == 'upstream_error') {
        final upstreamStatus = data['upstream_status']?.toString();
        final upstreamError = data['upstream_error']?.toString();
        final detail = [
          if (upstreamStatus != null && upstreamStatus.isNotEmpty)
            'Proveedor IA: $upstreamStatus',
          if (upstreamError != null && upstreamError.isNotEmpty)
            upstreamError,
        ].join(' · ');
        throw Exception(
          detail.isEmpty
              ? 'La IA no está disponible temporalmente.'
              : 'La IA no está disponible temporalmente. $detail',
        );
      }
      final error = data['error']?.toString().trim();
      throw Exception(error?.isNotEmpty == true ? error : 'Error de IA.');
    }

    return data;
  }

  Future<String> generateWhatsappMessage({
    required String message,
    Map<String, dynamic>? contextData,
  }) async {
    final data = await _invoke(
      taskType: 'whatsapp',
      message: message,
      contextData: contextData,
    );
    return (data['text']?.toString() ?? '').trim();
  }

  Future<String> generateEmail({
    required String message,
    Map<String, dynamic>? contextData,
  }) async {
    final data = await _invoke(
      taskType: 'email',
      message: message,
      contextData: contextData,
    );
    return (data['text']?.toString() ?? '').trim();
  }

  Future<String> summarizeClient({
    required String message,
    Map<String, dynamic>? contextData,
  }) async {
    final data = await _invoke(
      taskType: 'summarize',
      message: message,
      contextData: contextData,
    );
    return (data['text']?.toString() ?? '').trim();
  }

  Future<String> summarizeGig({
    required String message,
    Map<String, dynamic>? contextData,
  }) async {
    final data = await _invoke(
      taskType: 'summarize',
      message: message,
      contextData: contextData,
    );
    return (data['text']?.toString() ?? '').trim();
  }

  Future<Map<String, dynamic>> interpretAssistantAction({
    required String message,
    Map<String, dynamic>? contextData,
  }) async {
    final data = await _invoke(
      taskType: 'assistant_action',
      message: message,
      contextData: contextData,
    );
    final action = data['action'];
    if (action is! Map<String, dynamic>) {
      throw Exception('La IA no devolvió una acción válida.');
    }
    debugPrint('[AiService] assistant_action JSON: $action');
    return action;
  }

  Future<Map<String, dynamic>> extractExpenseFromText({
    required String message,
    Map<String, dynamic>? contextData,
  }) async {
    final data = await _invoke(
      taskType: 'extract_expense',
      message: message,
      contextData: contextData,
      inputType: 'text',
    );
    final extracted = data['extracted'];
    if (extracted is! Map<String, dynamic>) {
      throw Exception('La IA no devolvió JSON de extracción válido.');
    }
    return extracted;
  }

  Future<Map<String, dynamic>> extractExpenseFromReceiptText({
    required String message,
    required String imageText,
    Map<String, dynamic>? contextData,
  }) async {
    final data = await _invoke(
      taskType: 'extract_expense',
      message: message,
      contextData: contextData,
      imageText: imageText,
      inputType: 'text',
    );
    final extracted = data['extracted'];
    if (extracted is! Map<String, dynamic>) {
      throw Exception('La IA no devolvió JSON de extracción válido.');
    }
    return extracted;
  }

  Future<Map<String, dynamic>> extractExpenseFromImage({
    required String message,
    required String imageBase64,
    required String imageMimeType,
    Map<String, dynamic>? contextData,
  }) async {
    final data = await _invoke(
      taskType: 'extract_expense',
      message: message,
      contextData: contextData,
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
      inputType: 'image',
    );
    final extracted = data['extracted'];
    if (extracted is! Map<String, dynamic>) {
      throw Exception('La IA no devolvió JSON de extracción válido.');
    }
    return extracted;
  }

  Future<Map<String, dynamic>> extractInvestmentFromText({
    required String message,
    Map<String, dynamic>? contextData,
    String? imageText,
  }) async {
    final data = await _invoke(
      taskType: 'extract_investment',
      message: message,
      contextData: contextData,
      imageText: imageText,
      inputType: 'text',
    );
    final extracted = data['extracted'];
    if (extracted is! Map<String, dynamic>) {
      throw Exception('La IA no devolvió JSON de inversión válido.');
    }
    return extracted;
  }

  Future<Map<String, dynamic>> extractInvestmentFromImage({
    required String message,
    required String imageBase64,
    required String imageMimeType,
    Map<String, dynamic>? contextData,
  }) async {
    final data = await _invoke(
      taskType: 'extract_investment',
      message: message,
      contextData: contextData,
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
      inputType: 'image',
    );
    final extracted = data['extracted'];
    if (extracted is! Map<String, dynamic>) {
      throw Exception('La IA no devolvió JSON de inversión válido.');
    }
    return extracted;
  }

  Map<String, dynamic> _truncateMap(Map<String, dynamic> input) {
    final output = <String, dynamic>{};
    for (final entry in input.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value is String) {
        output[key] = _truncate(value, _maxContextLength);
      } else {
        output[key] = value;
      }
    }
    return output;
  }

  String _truncate(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    return value.substring(0, maxLength);
  }
}
