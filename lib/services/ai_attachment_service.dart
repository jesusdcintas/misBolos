import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

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
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      return result?.files.single.path;
    } on PlatformException catch (e) {
      throw Exception(_friendlyPickerError(e));
    }
  }

  Future<String?> pickImageFromGallery() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1800,
        imageQuality: 85,
      );
      return image?.path;
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
      return image?.path;
    } on PlatformException catch (e) {
      throw Exception(_friendlyPickerError(e));
    }
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
