import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

const int _maxGroqBase64Chars = 4 * 1024 * 1024;

class AiPreparedImage {
  const AiPreparedImage({
    required this.base64Data,
    required this.mimeType,
  });

  final String base64Data;
  final String mimeType;
}

class AiAttachmentService {
  AiAttachmentService._();

  static final AiAttachmentService instance = AiAttachmentService._();

  final ImagePicker _imagePicker = ImagePicker();

  Future<String?> pickPdf() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      final path = result?.files.single.path;
      if (path == null) return null;
      return persistAttachment(path, folder: 'docs');
    } on PlatformException catch (e) {
      throw Exception(_friendlyPickerError(e));
    }
  }

  String normalizeOriginalFileName(String fileNameOrPath) {
    final raw = p.basename(fileNameOrPath).trim();
    if (raw.isEmpty) return raw;
    final ext = p.extension(raw);
    final stem = ext.isEmpty ? raw : raw.substring(0, raw.length - ext.length);
    // Quita sufijo técnico tipo "_a1b2c3d4" si existe.
    final normalizedStem = stem.replaceFirst(RegExp(r'_[a-f0-9]{8}$', caseSensitive: false), '');
    return normalizedStem + ext;
  }

  Future<String?> pickImageFromGallery() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1800,
        imageQuality: 85,
      );
      final path = image?.path;
      if (path == null) return null;
      return persistAttachment(path, folder: 'images');
    } on PlatformException catch (e) {
      throw Exception(_friendlyPickerError(e));
    }
  }

  Future<String?> takePhotoWithCamera() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1800,
        imageQuality: 85,
      );
      final path = image?.path;
      if (path == null) return null;
      return persistAttachment(path, folder: 'images');
    } on PlatformException catch (e) {
      throw Exception(_friendlyPickerError(e));
    }
  }

  bool isTemporaryPath(String path) {
    final normalized = path.replaceAll('\\', '/').toLowerCase();
    return normalized.contains('/tmp/') ||
        normalized.contains('/private/var/mobile/') &&
            normalized.contains('/tmp/');
  }

  bool isCrossDeviceAbsolutePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    // En macOS un adjunto local puede vivir bajo /Users y es válido si existe.
    if (!kIsWeb && Platform.isMacOS && normalized.startsWith('/Users/')) {
      return !File(path).existsSync();
    }

    // Rutas de iOS (otro dispositivo) no son válidas en macOS/otros entornos.
    if (normalized.startsWith('/private/var/mobile/')) {
      return true;
    }

    // Volúmenes externos u otras rutas de sistema se tratan como potencialmente
    // no disponibles para evitar bucles de reintento cuando el archivo no está.
    if (normalized.startsWith('/Volumes/')) {
      return !File(path).existsSync();
    }

    return false;
  }

  Future<bool> isPersistentAttachmentPath(String path) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final normalized = path.replaceAll('\\', '/');
    final root = docsDir.path.replaceAll('\\', '/');
    return normalized.startsWith('$root/misbolos_attachments/');
  }

  Future<String> persistAttachment(
    String path, {
    String folder = 'misc',
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('No existe el archivo seleccionado.');
    }
    if (await isPersistentAttachmentPath(path)) {
      return path;
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final targetDir = Directory(
      p.join(docsDir.path, 'misbolos_attachments', folder),
    );
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final ext = p.extension(path);
    final baseName = p.basenameWithoutExtension(path);
    final safeBase = baseName
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\-\s]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final fileName = '${safeBase.isEmpty ? 'adjunto' : safeBase}_${const Uuid().v4().substring(0, 8)}$ext';
    final targetPath = p.join(targetDir.path, fileName);
    final copied = await file.copy(targetPath);
    return copied.path;
  }

  Future<String> persistAttachmentForEntity({
    required String sourcePath,
    required String entityType,
    required String entityId,
    String? attachmentId,
  }) async {
    final file = File(sourcePath);
    if (!await file.exists()) {
      throw Exception('No existe el archivo seleccionado.');
    }
    final docsDir = await getApplicationDocumentsDirectory();
    final targetDir = Directory(p.join(docsDir.path, 'attachments'));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    final ext = p.extension(sourcePath).toLowerCase();
    final stableAttachmentId = (attachmentId ?? const Uuid().v4())
        .replaceAll('-', '')
        .substring(0, 12);
    final safeEntity = entityType
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')
        .toLowerCase();
    final safeEntityId = entityId
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')
        .toLowerCase();
    final fileName = '${safeEntity}_${safeEntityId}_$stableAttachmentId$ext';
    final targetPath = p.join(targetDir.path, fileName);
    final copied = await file.copy(targetPath);
    return copied.path;
  }

  Future<AiPreparedImage> imageToBase64(String path) async {
    final bytes = await compressImageIfNeeded(path);
    final encoded = base64Encode(bytes);
    _ensureVisionSize(encoded);
    return AiPreparedImage(
      base64Data: encoded,
      mimeType: _mimeTypeForEncoded(path, bytes),
    );
  }

  Future<List<int>> compressImageIfNeeded(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('No se encontró la imagen seleccionada.');
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw Exception('La imagen está vacía.');

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      _ensureVisionSize(base64Encode(bytes));
      return bytes;
    }

    var image = decoded;
    const maxSide = 1600;
    if (image.width > maxSide || image.height > maxSide) {
      image = img.copyResize(
        image,
        width: image.width >= image.height ? maxSide : null,
        height: image.height > image.width ? maxSide : null,
      );
    }

    var quality = 82;
    var jpg = img.encodeJpg(image, quality: quality);
    while (base64Encode(jpg).length > _maxGroqBase64Chars && quality > 45) {
      quality -= 10;
      jpg = img.encodeJpg(image, quality: quality);
    }

    _ensureVisionSize(base64Encode(jpg));
    return jpg;
  }

  bool isImagePath(String path) {
    final ext = path.split('.').last.toLowerCase();
    return ext == 'jpg' ||
        ext == 'jpeg' ||
        ext == 'png' ||
        ext == 'webp' ||
        ext == 'heic' ||
        ext == 'heif';
  }

  void _ensureVisionSize(String base64Data) {
    if (base64Data.length > _maxGroqBase64Chars) {
      throw Exception(
        'La imagen es demasiado grande para IA. Prueba con una foto más recortada.',
      );
    }
  }

  String _mimeTypeForEncoded(String path, List<int> bytes) {
    final ext = path.split('.').last.toLowerCase();
    if (_looksLikeJpeg(bytes)) return 'image/jpeg';
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  bool _looksLikeJpeg(List<int> bytes) {
    return bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff;
  }

  String _friendlyPickerError(PlatformException error) {
    final code = error.code.toLowerCase();
    if (code.contains('denied') ||
        code.contains('permission') ||
        code.contains('restricted')) {
      return 'Permiso denegado. Activa el acceso a cámara o fotos en Ajustes.';
    }
    return error.message?.trim().isNotEmpty == true
        ? error.message!
        : 'No se pudo abrir el selector.';
  }
}
