import 'dart:io';

import 'package:syncfusion_flutter_pdf/pdf.dart';

class DocumentTextExtractor {
  DocumentTextExtractor._();

  static final DocumentTextExtractor instance = DocumentTextExtractor._();

  Future<String?> tryExtractText(String documentPath) async {
    final file = File(documentPath);
    if (!await file.exists()) return null;

    final ext = _extension(documentPath);
    if (ext != 'pdf') return null;

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;

    final document = PdfDocument(inputBytes: bytes);
    try {
      final extractor = PdfTextExtractor(document);
      final text = extractor.extractText();
      final normalized = text.trim();
      return normalized.isEmpty ? null : normalized;
    } finally {
      document.dispose();
    }
  }

  String _extension(String path) {
    final fileName = path.split('/').last.toLowerCase();
    final idx = fileName.lastIndexOf('.');
    if (idx < 0 || idx == fileName.length - 1) return '';
    return fileName.substring(idx + 1);
  }
}
