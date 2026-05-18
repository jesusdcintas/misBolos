import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../database/database_helper.dart';
import '../../core/utils/invoice_file_name.dart';
import '../../models/asset.dart';
import '../../models/client.dart';
import '../../models/expense.dart';
import '../../models/invoice.dart';
import '../../repositories/asset_repository.dart';
import '../../repositories/client_repository.dart';
import '../../repositories/expense_repository.dart';
import '../../repositories/invoice_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/pdf_service.dart';
import '../../services/ai_attachment_service.dart';
import '../../services/supabase_service.dart';
import 'google_drive_service.dart';

class DriveDocumentSyncResult {
  final int invoicesUploaded;
  final int expensesUploaded;
  final int assetsUploaded;
  final int skipped;
  final int failed;

  const DriveDocumentSyncResult({
    this.invoicesUploaded = 0,
    this.expensesUploaded = 0,
    this.assetsUploaded = 0,
    this.skipped = 0,
    this.failed = 0,
  });

  int get uploaded => invoicesUploaded + expensesUploaded + assetsUploaded;

  DriveDocumentSyncResult copyWith({
    int? invoicesUploaded,
    int? expensesUploaded,
    int? assetsUploaded,
    int? skipped,
    int? failed,
  }) {
    return DriveDocumentSyncResult(
      invoicesUploaded: invoicesUploaded ?? this.invoicesUploaded,
      expensesUploaded: expensesUploaded ?? this.expensesUploaded,
      assetsUploaded: assetsUploaded ?? this.assetsUploaded,
      skipped: skipped ?? this.skipped,
      failed: failed ?? this.failed,
    );
  }
}

class DriveReuploadResult {
  final int uploaded;
  final int alreadyExists;
  final int missingLocal;
  final int errors;

  const DriveReuploadResult({
    this.uploaded = 0,
    this.alreadyExists = 0,
    this.missingLocal = 0,
    this.errors = 0,
  });
}

class DriveStructureResult {
  final List<int> years;
  final int foldersEnsured;

  const DriveStructureResult({this.years = const [], this.foldersEnsured = 0});
}

class DriveRetryResult {
  final int retried;
  final int succeeded;
  final int failed;
  final int skippedByMaxAttempts;
  final List<String> recentErrors;

  const DriveRetryResult({
    this.retried = 0,
    this.succeeded = 0,
    this.failed = 0,
    this.skippedByMaxAttempts = 0,
    this.recentErrors = const [],
  });
}

class DriveQueueSummary {
  final int totalPending;
  final int invoicePending;
  final int expensePending;
  final int assetPending;
  final int backupPending;
  final int invalidMissingFile;
  final int invalidDevicePath;
  final int retryable;
  final String? lastError;

  const DriveQueueSummary({
    this.totalPending = 0,
    this.invoicePending = 0,
    this.expensePending = 0,
    this.assetPending = 0,
    this.backupPending = 0,
    this.invalidMissingFile = 0,
    this.invalidDevicePath = 0,
    this.retryable = 0,
    this.lastError,
  });
}

class AttachmentRepairResult {
  final int checked;
  final int repaired;
  final int missing;
  final int unavailable;
  final int failed;

  const AttachmentRepairResult({
    this.checked = 0,
    this.repaired = 0,
    this.missing = 0,
    this.unavailable = 0,
    this.failed = 0,
  });
}

class BrokenAttachmentItem {
  final String entityType;
  final String entityId;
  final String? fileName;
  final String reason;
  final String? path;

  const BrokenAttachmentItem({
    required this.entityType,
    required this.entityId,
    required this.reason,
    this.fileName,
    this.path,
  });
}

class DriveDocumentSyncService {
  static final DriveDocumentSyncService instance = DriveDocumentSyncService._();
  DriveDocumentSyncService._();

  final GoogleDriveService _drive = GoogleDriveService.instance;
  final InvoiceRepository _invoiceRepository = InvoiceRepository.instance;
  final ExpenseRepository _expenseRepository = ExpenseRepository.instance;
  final AssetRepository _assetRepository = AssetRepository.instance;
  final ClientRepository _clientRepository = ClientRepository.instance;
  final SettingsRepository _settingsRepository = SettingsRepository();
  static const int maxRetryAttempts = 5;
  static const String errorMissingFile = 'failed_file_missing';
  static const String errorDevicePath = 'device_path_unavailable';
  static const String errorBadFileDescriptor = 'bad_file_descriptor';
  static const String errorHandshake = 'handshake_exception';
  static const String errorNetwork = 'network_exception';
  static const String errorInternalBug =
      'internal_bug_bad_descriptor_googleapi';
  static const String statusPending = 'pending';
  static const String statusRetryable = 'retryable';
  static const String statusInvalidLocalFile = 'invalid_local_file';
  static const String statusInternalBug = 'internal_bug';
  static Future<DriveDocumentSyncResult>? _documentSyncInFlight;
  int _driveListMs = 0;
  int _driveUploadMs = 0;
  int _driveDownloadMs = 0;

  Future<DriveDocumentSyncResult> syncExistingDocuments({
    String reason = 'drive_sync',
  }) async {
    final totalWatch = Stopwatch()..start();
    debugPrint('[SYNC] start reason=$reason');
    if (_documentSyncInFlight != null) {
      debugPrint(
        '[SYNC] acquire lock: ${totalWatch.elapsedMilliseconds} ms (reused in-flight)',
      );
      return _documentSyncInFlight!;
    }
    debugPrint('[SYNC] acquire lock: ${totalWatch.elapsedMilliseconds} ms');
    _documentSyncInFlight = _syncExistingDocumentsInternal(reason: reason);
    try {
      return await _documentSyncInFlight!;
    } finally {
      debugPrint('[SYNC] total: ${totalWatch.elapsedMilliseconds} ms');
      _documentSyncInFlight = null;
    }
  }

  Future<DriveDocumentSyncResult> _syncExistingDocumentsInternal({
    required String reason,
  }) async {
    final attachmentsWatch = Stopwatch()..start();
    _driveListMs = 0;
    _driveUploadMs = 0;
    _driveDownloadMs = 0;
    debugPrint('[SYNC][ATTACHMENTS] start reason=$reason');
    final rootWatch = Stopwatch()..start();
    await _drive.ensureRootFolder();
    rootWatch.stop();
    _driveListMs += rootWatch.elapsedMilliseconds;

    var result = const DriveDocumentSyncResult();
    var pendingUpload = 0;
    var pendingDownload = 0;
    var broken = 0;

    final invoices = await _invoiceRepository.getAll();
    for (final baseInvoice in invoices) {
      final invoice = await _invoiceRepository.getById(baseInvoice.id);
      if (invoice == null) {
        result = result.copyWith(skipped: result.skipped + 1);
        continue;
      }
      if (_invoiceDriveAlreadySynced(invoice)) {
        result = result.copyWith(skipped: result.skipped + 1);
        continue;
      }
      pendingUpload++;
      try {
        await _syncInvoice(invoice);
        result = result.copyWith(invoicesUploaded: result.invoicesUploaded + 1);
      } catch (e) {
        await _queueFailedSync(
          entityType: 'invoice',
          entityId: invoice.id,
          action: invoice.driveFileId == null ? 'upload' : 'update',
          targetFolderType: 'FACTURAS',
          lastError: e.toString(),
          documentType: 'invoice_pdf',
          mimeType: 'application/pdf',
          driveFileId: invoice.driveFileId,
          logicalPath: 'FACTURAS/${invoice.id}',
        );
        result = result.copyWith(failed: result.failed + 1);
      }
    }

    final expenses = await _expenseRepository.getAll();
    for (final expense in expenses) {
      if (expense.id == null) {
        debugPrint(
          '[DRIVE][UPLOAD] skipped_reason=missing_entity_id entity_type=expense',
        );
        result = result.copyWith(skipped: result.skipped + 1);
        continue;
      }
      final hasLocalPath = expense.documentoPath?.trim().isNotEmpty == true;
      final hasDriveFile = expense.driveFileId?.trim().isNotEmpty == true;
      if (!hasLocalPath && !hasDriveFile) {
        debugPrint(
          '[DRIVE][UPLOAD] skipped_reason=no_local_and_no_remote entity_type=expense entity_id=${expense.id}',
        );
        result = result.copyWith(skipped: result.skipped + 1);
        continue;
      }
      if (_expenseDriveAlreadySynced(expense) ||
          _shouldSkipBrokenAttachment(expense.attachmentStatus)) {
        if (_shouldSkipBrokenAttachment(expense.attachmentStatus)) broken++;
        if (_expenseDriveAlreadySynced(expense)) {
          debugPrint(
            '[DRIVE][UPLOAD] skipped because already uploaded entity=expense/${expense.id}',
          );
        } else {
          debugPrint(
            '[DRIVE][UPLOAD] skipped_reason=broken_status entity_type=expense entity_id=${expense.id} status=${expense.attachmentStatus}',
          );
        }
        result = result.copyWith(skipped: result.skipped + 1);
        continue;
      }
      if ((expense.documentoPath == null || expense.documentoPath!.isEmpty) &&
          expense.driveFileId?.isNotEmpty == true) {
        pendingDownload++;
      } else {
        pendingUpload++;
      }
      try {
        await _syncExpense(expense);
        result = result.copyWith(expensesUploaded: result.expensesUploaded + 1);
      } catch (e) {
        await _queueFailedSync(
          entityType: 'expense',
          entityId: expense.id!.toString(),
          action: expense.driveFileId == null ? 'upload' : 'update',
          localFilePath: expense.documentoPath,
          targetFolderType: 'GASTOS',
          lastError: e.toString(),
          documentType: 'expense_attachment',
          fileName: expense.attachmentDisplayName,
          mimeType: expense.attachmentMimeType,
          driveFileId: expense.driveFileId,
          logicalPath: 'GASTOS/${expense.id}',
        );
        result = result.copyWith(failed: result.failed + 1);
      }
    }

    final assets = await _assetRepository.getAll();
    for (final asset in assets) {
      if (asset.id == null) {
        debugPrint(
          '[DRIVE][UPLOAD] skipped_reason=missing_entity_id entity_type=asset',
        );
        result = result.copyWith(skipped: result.skipped + 1);
        continue;
      }
      final hasLocalPath = asset.documentoPath?.trim().isNotEmpty == true;
      final hasDriveFile = asset.driveFileId?.trim().isNotEmpty == true;
      if (!hasLocalPath && !hasDriveFile) {
        debugPrint(
          '[DRIVE][UPLOAD] skipped_reason=no_local_and_no_remote entity_type=asset entity_id=${asset.id}',
        );
        result = result.copyWith(skipped: result.skipped + 1);
        continue;
      }
      if (_assetDriveAlreadySynced(asset) ||
          _shouldSkipBrokenAttachment(asset.attachmentStatus)) {
        if (_shouldSkipBrokenAttachment(asset.attachmentStatus)) broken++;
        if (_assetDriveAlreadySynced(asset)) {
          debugPrint(
            '[DRIVE][UPLOAD] skipped because already uploaded entity=asset/${asset.id}',
          );
        } else {
          debugPrint(
            '[DRIVE][UPLOAD] skipped_reason=broken_status entity_type=asset entity_id=${asset.id} status=${asset.attachmentStatus}',
          );
        }
        result = result.copyWith(skipped: result.skipped + 1);
        continue;
      }
      if ((asset.documentoPath == null || asset.documentoPath!.isEmpty) &&
          asset.driveFileId?.isNotEmpty == true) {
        pendingDownload++;
      } else {
        pendingUpload++;
      }
      try {
        await _syncAsset(asset);
        result = result.copyWith(assetsUploaded: result.assetsUploaded + 1);
      } catch (e) {
        await _queueFailedSync(
          entityType: 'asset',
          entityId: asset.id!.toString(),
          action: asset.driveFileId == null ? 'upload' : 'update',
          localFilePath: asset.documentoPath,
          targetFolderType: 'INVERSIONES',
          lastError: e.toString(),
          documentType: 'asset_attachment',
          fileName: asset.attachmentDisplayName,
          mimeType: asset.attachmentMimeType,
          driveFileId: asset.driveFileId,
          logicalPath: 'INVERSIONES/${asset.id}',
        );
        result = result.copyWith(failed: result.failed + 1);
      }
    }

    final settings = await _settingsRepository.get();
    await _settingsRepository.save(
      settings.copyWith(lastDriveSyncAt: DateTime.now()),
    );
    attachmentsWatch.stop();
    debugPrint(
      '[SYNC][ATTACHMENTS] pending_upload=$pendingUpload, pending_download=$pendingDownload, '
      'broken=$broken, skipped=${result.skipped}',
    );
    debugPrint(
      '[SYNC][ATTACHMENTS] processed=${result.uploaded}, failed=${result.failed}, '
      'time=${attachmentsWatch.elapsedMilliseconds} ms',
    );
    debugPrint('[SYNC][DRIVE] list folders/files: $_driveListMs ms');
    debugPrint('[SYNC][DRIVE] upload: $_driveUploadMs ms');
    debugPrint('[SYNC][DRIVE] download: $_driveDownloadMs ms');
    debugPrint(
      '[SYNC][DRIVE] total: ${_driveListMs + _driveUploadMs + _driveDownloadMs} ms',
    );
    return result;
  }

  Future<void> _syncInvoice(Invoice invoice) async {
    final client = await _clientRepository.getById(invoice.clientId);
    final settings = await _settingsRepository.get();
    final file = await PdfService().generateInvoicePdf(
      invoice: invoice,
      client: client ?? _fallbackClient(),
      settings: settings,
    );
    final listWatch = Stopwatch()..start();
    final monthFolders = await _drive.ensureMonthStructure(invoice.fecha);
    listWatch.stop();
    _driveListMs += listWatch.elapsedMilliseconds;
    final fileName = _invoiceFileName(
      invoice: invoice,
      clientName: client?.nombre,
    );
    final stableFile = await _persistStableUploadCopy(
      source: file,
      entityType: 'invoice',
      entityId: invoice.id,
      fileName: fileName,
    );
    final uploaded = await _uploadOrUpdate(
      existingFileId: invoice.driveFileId,
      file: stableFile,
      fileName: fileName,
      parentFolderId: monthFolders.facturasFolderId,
      mimeType: 'application/pdf',
    );
    await _invoiceRepository.updateDriveMetadata(
      id: invoice.id,
      driveFileId: uploaded.fileId,
      driveFileUrl: uploaded.fileUrl,
      driveSyncedAt: DateTime.now(),
    );
    final refreshed = await _invoiceRepository.getById(invoice.id);
    if (refreshed != null && SupabaseService.instance.isAuthenticated) {
      try {
        await SupabaseService.instance.uploadInvoices([refreshed]);
      } catch (e) {
        debugPrint(
          '[DRIVE][CLOUD] invoice/${invoice.id} metadata upload failed: $e',
        );
      }
    }
  }

  Future<void> syncInvoiceById(String invoiceId) async {
    await _drive.ensureRootFolder();
    final invoice = await _invoiceRepository.getById(invoiceId);
    if (invoice == null) {
      throw Exception('Factura no encontrada para sincronizar.');
    }
    try {
      await _syncInvoice(invoice);
      final settings = await _settingsRepository.get();
      await _settingsRepository.save(
        settings.copyWith(lastDriveSyncAt: DateTime.now()),
      );
    } catch (e) {
      await _queueFailedSync(
        entityType: 'invoice',
        entityId: invoice.id,
        action: invoice.driveFileId == null ? 'upload' : 'update',
        targetFolderType: 'FACTURAS',
        lastError: e.toString(),
        documentType: 'invoice_pdf',
        mimeType: 'application/pdf',
        driveFileId: invoice.driveFileId,
        logicalPath: 'FACTURAS/${invoice.id}',
      );
      rethrow;
    }
  }

  Future<void> syncExpenseById(int expenseId) async {
    await _drive.ensureRootFolder();
    final expense = await _expenseRepository.getById(expenseId);
    if (expense == null) {
      throw Exception('Gasto no encontrado para sincronizar.');
    }
    try {
      await _syncExpense(expense);
      final settings = await _settingsRepository.get();
      await _settingsRepository.save(
        settings.copyWith(lastDriveSyncAt: DateTime.now()),
      );
    } catch (e) {
      await _queueFailedSync(
        entityType: 'expense',
        entityId: expenseId.toString(),
        action: expense.driveFileId == null ? 'upload' : 'update',
        localFilePath: expense.documentoPath,
        targetFolderType: 'GASTOS',
        lastError: e.toString(),
        documentType: 'expense_attachment',
        fileName: expense.attachmentDisplayName,
        mimeType: expense.attachmentMimeType,
        driveFileId: expense.driveFileId,
        logicalPath: 'GASTOS/${expense.id}',
      );
      rethrow;
    }
  }

  Future<void> syncAssetById(int assetId) async {
    await _drive.ensureRootFolder();
    final asset = await _assetRepository.getById(assetId);
    if (asset == null) {
      throw Exception('Inversión no encontrada para sincronizar.');
    }
    try {
      await _syncAsset(asset);
      final settings = await _settingsRepository.get();
      await _settingsRepository.save(
        settings.copyWith(lastDriveSyncAt: DateTime.now()),
      );
    } catch (e) {
      await _queueFailedSync(
        entityType: 'asset',
        entityId: assetId.toString(),
        action: asset.driveFileId == null ? 'upload' : 'update',
        localFilePath: asset.documentoPath,
        targetFolderType: 'INVERSIONES',
        lastError: e.toString(),
        documentType: 'asset_attachment',
        fileName: asset.attachmentDisplayName,
        mimeType: asset.attachmentMimeType,
        driveFileId: asset.driveFileId,
        logicalPath: 'INVERSIONES/${asset.id}',
      );
      rethrow;
    }
  }

  Future<DriveReuploadResult> uploadAllDocumentsToDrive({
    String reason = 'drive_reupload',
  }) async {
    final totalWatch = Stopwatch()..start();
    debugPrint('[DRIVE][REUPLOAD] start reason=$reason');
    await _drive.ensureRootFolder();
    var uploaded = 0;
    var alreadyExists = 0;
    var missingLocal = 0;
    var errors = 0;
    var foldersEnsured = 0;

    final settings = await _settingsRepository.get();
    final selectedRootFolderId = settings.driveRootFolderId?.trim() ?? '';

    final invoices = await _invoiceRepository.getAll();
    final invoiceYears = invoices.map((e) => e.fecha.year).toSet().toList()
      ..sort();
    debugPrint(
      '[DRIVE][REUPLOAD] invoices found=${invoices.length} years=$invoiceYears',
    );
    final expenses = await _expenseRepository.getAll();
    final expenseYears = expenses.map((e) => e.fecha.year).toSet().toList()
      ..sort();
    debugPrint(
      '[DRIVE][REUPLOAD] expenses found=${expenses.length} years=$expenseYears',
    );
    final assets = await _assetRepository.getAll();
    final assetYears = assets.map((e) => e.fechaCompra.year).toSet().toList()
      ..sort();
    debugPrint(
      '[DRIVE][REUPLOAD] assets found=${assets.length} years=$assetYears',
    );

    final allYears = <int>{
      ...invoiceYears,
      ...expenseYears,
      ...assetYears,
    }.toList()..sort();
    for (final year in allYears) {
      try {
        await _drive.createFullYearStructure(year);
        foldersEnsured++;
      } catch (e, st) {
        debugPrint(
          '[DRIVE][REUPLOAD][ERROR] year_structure/$year exception=$e',
        );
        debugPrint('[DRIVE][REUPLOAD][ERROR] year_structure/$year stack=$st');
        errors++;
      }
    }

    for (final invoice in invoices) {
      try {
        var candidate = invoice;
        final existingId = invoice.driveFileId?.trim();
        if (existingId?.isNotEmpty == true) {
          final existsInSelectedRoot = selectedRootFolderId.isNotEmpty
              ? await _drive.fileExistsUnderRoot(
                  fileId: existingId!,
                  rootFolderId: selectedRootFolderId,
                )
              : await _drive.fileExists(existingId!);
          if (existsInSelectedRoot) {
            alreadyExists++;
            continue;
          }
          debugPrint(
            '[DRIVE][REUPLOAD] invoice/${invoice.id} exists_outside_selected_root -> reupload',
          );
          await _invoiceRepository.clearDriveMetadata(invoice.id);
          candidate = invoice.copyWith(clearDriveFile: true);
        }
        final client = await _clientRepository.getById(candidate.clientId);
        if (client == null) {
          errors++;
          continue;
        }
        final file = await PdfService().generateInvoicePdf(
          invoice: candidate,
          client: client,
          settings: settings,
        );
        final monthFolders = await _drive.ensureMonthStructure(candidate.fecha);
        final uploadedResult = await _uploadOrUpdate(
          existingFileId: null,
          file: file,
          fileName: _invoiceFileName(
            invoice: candidate,
            clientName: client.nombre,
          ),
          parentFolderId: monthFolders.facturasFolderId,
          mimeType: 'application/pdf',
        );
        await _invoiceRepository.updateDriveMetadata(
          id: candidate.id,
          driveFileId: uploadedResult.fileId,
          driveFileUrl: uploadedResult.fileUrl,
          driveSyncedAt: DateTime.now(),
        );
        uploaded++;
      } catch (e, st) {
        debugPrint(
          '[DRIVE][REUPLOAD][ERROR] invoice/${invoice.id} exception=$e',
        );
        debugPrint('[DRIVE][REUPLOAD][ERROR] invoice/${invoice.id} stack=$st');
        errors++;
      }
    }

    for (final expense in expenses) {
      if (expense.id == null) continue;
      try {
        var candidate = expense;
        final existingId = candidate.driveFileId?.trim();
        if (existingId?.isNotEmpty == true) {
          final existsInSelectedRoot = selectedRootFolderId.isNotEmpty
              ? await _drive.fileExistsUnderRoot(
                  fileId: existingId!,
                  rootFolderId: selectedRootFolderId,
                )
              : await _drive.fileExists(existingId!);
          if (existsInSelectedRoot) {
            alreadyExists++;
            continue;
          }
          debugPrint(
            '[DRIVE][REUPLOAD] expense/${expense.id} exists_outside_selected_root -> reupload',
          );
          final path = candidate.documentoPath?.trim();
          final hasLocal =
              path != null && path.isNotEmpty && File(path).existsSync();
          if (!hasLocal) {
            try {
              final listWatch = Stopwatch()..start();
              final monthFolders = await _drive.ensureMonthStructure(
                candidate.fecha,
              );
              listWatch.stop();
              _driveListMs += listWatch.elapsedMilliseconds;
              final copied = await _drive.copyFileToFolder(
                sourceFileId: existingId,
                fileName: _expenseFileName(
                  candidate,
                  File(path ?? 'adjunto.pdf'),
                ),
                parentFolderId: monthFolders.gastosFolderId,
              );
              await _expenseRepository.updateDriveMetadata(
                id: candidate.id!,
                driveFileId: copied.fileId,
                driveFileUrl: copied.fileUrl,
                driveSyncedAt: DateTime.now(),
              );
              uploaded++;
              debugPrint(
                '[DRIVE][REUPLOAD] expense/${expense.id} copied_from_existing_drive_file',
              );
              continue;
            } catch (e, st) {
              debugPrint(
                '[DRIVE][REUPLOAD][ERROR] expense/${expense.id} copy_from_existing exception=$e',
              );
              debugPrint(
                '[DRIVE][REUPLOAD][ERROR] expense/${expense.id} copy_from_existing stack=$st',
              );
            }
          }
          await _expenseRepository.clearDriveMetadata(candidate.id!);
          candidate = candidate.copyWith(clearDriveFile: true);
        }
        final path = _bestAttachmentPath(
          candidate.documentoPath,
          candidate.attachmentOriginalPath,
        );
        if (path == null || path.isEmpty || !File(path).existsSync()) {
          debugPrint(
            '[DRIVE][REUPLOAD] expense/${expense.id} missing_local path=${path ?? '-'} original_path=${candidate.attachmentOriginalPath ?? '-'} drive_file_id=${candidate.driveFileId ?? '-'}',
          );
          await _expenseRepository.update(
            candidate.copyWith(
              attachmentStatus: 'missing_local',
              attachmentError: 'No existe el archivo local del adjunto.',
            ),
          );
          missingLocal++;
          continue;
        }
        await _syncExpense(candidate);
        uploaded++;
      } catch (e, st) {
        debugPrint(
          '[DRIVE][REUPLOAD][ERROR] expense/${expense.id} exception=$e',
        );
        debugPrint('[DRIVE][REUPLOAD][ERROR] expense/${expense.id} stack=$st');
        errors++;
      }
    }

    for (final asset in assets) {
      if (asset.id == null) continue;
      try {
        var candidate = asset;
        final existingId = candidate.driveFileId?.trim();
        if (existingId?.isNotEmpty == true) {
          final existsInSelectedRoot = selectedRootFolderId.isNotEmpty
              ? await _drive.fileExistsUnderRoot(
                  fileId: existingId!,
                  rootFolderId: selectedRootFolderId,
                )
              : await _drive.fileExists(existingId!);
          if (existsInSelectedRoot) {
            alreadyExists++;
            continue;
          }
          debugPrint(
            '[DRIVE][REUPLOAD] asset/${asset.id} exists_outside_selected_root -> reupload',
          );
          final path = candidate.documentoPath?.trim();
          final hasLocal =
              path != null && path.isNotEmpty && File(path).existsSync();
          if (!hasLocal) {
            try {
              final listWatch = Stopwatch()..start();
              final monthFolders = await _drive.ensureMonthStructure(
                candidate.fechaCompra,
              );
              listWatch.stop();
              _driveListMs += listWatch.elapsedMilliseconds;
              final copied = await _drive.copyFileToFolder(
                sourceFileId: existingId,
                fileName: _assetFileName(
                  candidate,
                  File(path ?? 'adjunto.pdf'),
                ),
                parentFolderId: monthFolders.inversionesFolderId,
              );
              await _assetRepository.updateDriveMetadata(
                id: candidate.id!,
                driveFileId: copied.fileId,
                driveFileUrl: copied.fileUrl,
                driveSyncedAt: DateTime.now(),
              );
              uploaded++;
              debugPrint(
                '[DRIVE][REUPLOAD] asset/${asset.id} copied_from_existing_drive_file',
              );
              continue;
            } catch (e, st) {
              debugPrint(
                '[DRIVE][REUPLOAD][ERROR] asset/${asset.id} copy_from_existing exception=$e',
              );
              debugPrint(
                '[DRIVE][REUPLOAD][ERROR] asset/${asset.id} copy_from_existing stack=$st',
              );
            }
          }
          await _assetRepository.clearDriveMetadata(candidate.id!);
          candidate = candidate.copyWith(clearDriveFile: true);
        }
        final path = _bestAttachmentPath(
          candidate.documentoPath,
          candidate.attachmentOriginalPath,
        );
        if (path == null || path.isEmpty || !File(path).existsSync()) {
          debugPrint(
            '[DRIVE][REUPLOAD] asset/${asset.id} missing_local path=${path ?? '-'} original_path=${candidate.attachmentOriginalPath ?? '-'} drive_file_id=${candidate.driveFileId ?? '-'}',
          );
          await _assetRepository.update(
            candidate.copyWith(
              attachmentStatus: 'missing_local',
              attachmentError: 'No existe el archivo local del adjunto.',
            ),
          );
          missingLocal++;
          continue;
        }
        await _syncAsset(candidate);
        uploaded++;
      } catch (e, st) {
        debugPrint('[DRIVE][REUPLOAD][ERROR] asset/${asset.id} exception=$e');
        debugPrint('[DRIVE][REUPLOAD][ERROR] asset/${asset.id} stack=$st');
        errors++;
      }
    }

    await _settingsRepository.save(
      settings.copyWith(lastDriveSyncAt: DateTime.now()),
    );

    totalWatch.stop();
    debugPrint('[DRIVE][REUPLOAD] folders created=$foldersEnsured');
    debugPrint('[DRIVE][REUPLOAD] uploaded=$uploaded');
    debugPrint('[DRIVE][REUPLOAD] already_exists=$alreadyExists');
    debugPrint('[DRIVE][REUPLOAD] missing_local=$missingLocal');
    debugPrint('[DRIVE][REUPLOAD] errors=$errors');
    debugPrint(
      '[DRIVE][REUPLOAD] done time=${totalWatch.elapsedMilliseconds} ms',
    );

    return DriveReuploadResult(
      uploaded: uploaded,
      alreadyExists: alreadyExists,
      missingLocal: missingLocal,
      errors: errors,
    );
  }

  Future<DriveStructureResult> createStructureForExistingDocuments({
    String reason = 'drive_create_structure',
  }) async {
    final watch = Stopwatch()..start();
    debugPrint('[DRIVE][STRUCTURE] start reason=$reason');
    await _drive.ensureRootFolder();

    final invoices = await _invoiceRepository.getAll();
    final expenses = await _expenseRepository.getAll();
    final assets = await _assetRepository.getAll();

    final years = <int>{
      ...invoices.map((e) => e.fecha.year),
      ...expenses.map((e) => e.fecha.year),
      ...assets.map((e) => e.fechaCompra.year),
    }.toList()..sort();

    if (years.isEmpty) {
      years.add(DateTime.now().year);
    }

    debugPrint('[DRIVE][STRUCTURE] years=$years');
    var foldersEnsured = 0;
    for (final year in years) {
      try {
        await _drive.createFullYearStructure(year);
        foldersEnsured++;
      } catch (e, st) {
        debugPrint('[DRIVE][STRUCTURE][ERROR] year=$year exception=$e');
        debugPrint('[DRIVE][STRUCTURE][ERROR] year=$year stack=$st');
        rethrow;
      }
    }

    watch.stop();
    debugPrint(
      '[DRIVE][STRUCTURE] done years=$years folders_created=$foldersEnsured time=${watch.elapsedMilliseconds} ms',
    );
    return DriveStructureResult(years: years, foldersEnsured: foldersEnsured);
  }

  Future<int> getPendingQueueCount() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM drive_sync_queue
      WHERE attempts < ?
      ''',
      [maxRetryAttempts],
    );
    return (rows.first['total'] as int?) ?? 0;
  }

  Future<DriveQueueSummary> getQueueSummary() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('drive_sync_queue');
    var invoice = 0;
    var expense = 0;
    var asset = 0;
    var backup = 0;
    var invalidMissing = 0;
    var invalidDevice = 0;
    var retryable = 0;
    String? lastError;

    for (final row in rows) {
      final type = _canonicalEntityType((row['entity_type'] as String?) ?? '');
      final entityId = (row['entity_id'] as String?) ?? '';
      if (!await _driveQueueParentExists(type, entityId)) {
        continue;
      }
      final error = (row['last_error'] as String?) ?? '';
      final status = (row['sync_status'] as String?) ?? statusPending;
      final isInvalidMissing =
          error.startsWith(errorMissingFile) ||
          error.contains('$errorMissingFile:');
      final isInvalidDevice =
          error.startsWith(errorDevicePath) ||
          error.contains('$errorDevicePath:');
      if (status == statusRetryable) retryable++;
      if (lastError == null && error.isNotEmpty) {
        lastError = error;
      }
      if (isInvalidMissing) invalidMissing++;
      if (isInvalidDevice) invalidDevice++;
      if (isInvalidMissing || isInvalidDevice) continue;
      switch (type) {
        case 'invoice':
          invoice++;
          break;
        case 'expense':
          expense++;
          break;
        case 'asset':
          asset++;
          break;
        case 'backup':
          backup++;
          break;
      }
    }

    // También contamos pendientes locales (aunque aún no hayan entrado en la cola)
    // para que el indicador refleje facturas/gastos/inversiones reales por subir.
    final queuedInvoiceIds = <String>{};
    final queuedExpenseIds = <String>{};
    final queuedAssetIds = <String>{};
    for (final row in rows) {
      final type = _canonicalEntityType((row['entity_type'] as String?) ?? '');
      final entityId = (row['entity_id'] as String?) ?? '';
      if (entityId.isEmpty) continue;
      if (type == 'invoice') queuedInvoiceIds.add(entityId);
      if (type == 'expense') queuedExpenseIds.add(entityId);
      if (type == 'asset') queuedAssetIds.add(entityId);
    }

    final invoices = await _invoiceRepository.getAll();
    for (final inv in invoices) {
      if (queuedInvoiceIds.contains(inv.id)) continue;
      if (_invoiceDriveAlreadySynced(inv)) continue;
      invoice++;
    }

    final expenses = await _expenseRepository.getAll();
    for (final exp in expenses) {
      final id = exp.id?.toString();
      if (id == null || queuedExpenseIds.contains(id)) continue;
      if (_expenseDriveAlreadySynced(exp)) continue;
      if (_shouldSkipBrokenAttachment(exp.attachmentStatus)) continue;
      final hasLocal = exp.documentoPath?.trim().isNotEmpty == true;
      final hasRemote = exp.driveFileId?.trim().isNotEmpty == true;
      if (!hasLocal && !hasRemote) continue;
      expense++;
    }

    final assets = await _assetRepository.getAll();
    for (final ast in assets) {
      final id = ast.id?.toString();
      if (id == null || queuedAssetIds.contains(id)) continue;
      if (_assetDriveAlreadySynced(ast)) continue;
      if (_shouldSkipBrokenAttachment(ast.attachmentStatus)) continue;
      final hasLocal = ast.documentoPath?.trim().isNotEmpty == true;
      final hasRemote = ast.driveFileId?.trim().isNotEmpty == true;
      if (!hasLocal && !hasRemote) continue;
      asset++;
    }

    return DriveQueueSummary(
      totalPending: invoice + expense + asset + backup,
      invoicePending: invoice,
      expensePending: expense,
      assetPending: asset,
      backupPending: backup,
      invalidMissingFile: invalidMissing,
      invalidDevicePath: invalidDevice,
      retryable: retryable,
      lastError: lastError,
    );
  }

  Future<List<Map<String, Object?>>> getRecentQueueErrors({
    int limit = 5,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'drive_sync_queue',
      columns: ['entity_type', 'entity_id', 'attempts', 'last_error'],
      where:
          'last_error IS NULL OR (last_error NOT LIKE ? AND last_error NOT LIKE ? AND last_error NOT LIKE ? AND last_error NOT LIKE ?)',
      whereArgs: [
        '$errorMissingFile:%',
        '$errorDevicePath:%',
        '%$errorMissingFile:%',
        '%$errorDevicePath:%',
      ],
      orderBy: 'updated_at DESC',
    );
    final validRows = <Map<String, Object?>>[];
    for (final row in rows) {
      final type = (row['entity_type'] as String?) ?? '';
      final id = (row['entity_id'] as String?) ?? '';
      if (await _driveQueueParentExists(type, id)) {
        validRows.add(row);
        if (validRows.length >= limit) break;
      }
    }
    return validRows;
  }

  Future<DriveRetryResult> retryPendingDriveSync() async {
    await _drive.ensureRootFolder();
    final db = await DatabaseHelper.instance.database;
    final queue = await db.query(
      'drive_sync_queue',
      where:
          "attempts < ? AND sync_status != ? AND sync_status != ? AND (next_retry_at IS NULL OR next_retry_at <= ?) AND (last_error IS NULL OR (last_error NOT LIKE ? AND last_error NOT LIKE ?))",
      whereArgs: [
        maxRetryAttempts,
        statusInvalidLocalFile,
        statusInternalBug,
        DateTime.now().toIso8601String(),
        '$errorMissingFile:%',
        '$errorDevicePath:%',
      ],
      orderBy: 'created_at ASC',
      limit: 200,
    );
    if (queue.isEmpty) {
      return const DriveRetryResult();
    }

    var retried = 0;
    var succeeded = 0;
    var failed = 0;
    var skippedByMaxAttempts = 0;
    final errors = <String>[];

    for (final item in queue) {
      retried++;
      final id = item['id'] as String;
      final entityType = _canonicalEntityType(
        (item['entity_type'] as String?) ?? '',
      );
      final entityId = (item['entity_id'] as String?) ?? '';
      final attempts = (item['attempts'] as int?) ?? 0;
      final queuedLocalPath = (item['local_file_path'] as String?)?.trim();
      if (queuedLocalPath != null &&
          queuedLocalPath.isNotEmpty &&
          (queuedLocalPath.startsWith('http://') ||
              queuedLocalPath.startsWith('https://'))) {
        await db.update(
          'drive_sync_queue',
          {
            'sync_status': statusInternalBug,
            'last_error_code': errorInternalBug,
            'last_error':
                'internal_bug_bad_descriptor_googleapi: local_file_path contiene URL remota en vez de ruta local',
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        failed++;
        continue;
      }

      try {
        if (entityType == 'invoice') {
          final invoice = await _invoiceRepository.getById(entityId);
          if (invoice == null) {
            throw Exception('Factura $entityId no encontrada.');
          }
          await _syncInvoice(invoice);
        } else if (entityType == 'expense') {
          final expenseId = int.tryParse(entityId);
          if (expenseId == null) {
            throw Exception('Expense id inválido.');
          }
          final expense = await _expenseRepository.getById(expenseId);
          if (expense == null) {
            throw Exception('Gasto $entityId no encontrado.');
          }
          await _syncExpense(expense);
        } else if (entityType == 'asset') {
          final assetId = int.tryParse(entityId);
          if (assetId == null) {
            throw Exception('Asset id inválido.');
          }
          final asset = await _assetRepository.getById(assetId);
          if (asset == null) {
            throw Exception('Inversión $entityId no encontrada.');
          }
          await _syncAsset(asset);
        } else if (entityType == 'backup') {
          throw Exception(
            'Los backups pendientes se recrean desde "Crear backup ahora".',
          );
        } else {
          throw Exception('Tipo de entidad no soportado: $entityType');
        }

        await db.delete('drive_sync_queue', where: 'id = ?', whereArgs: [id]);
        succeeded++;
      } catch (error) {
        final nextAttempts = attempts + 1;
        final classification = _classifyDriveError(error.toString());
        await db.update(
          'drive_sync_queue',
          {
            'attempts': nextAttempts,
            'last_error': error.toString(),
            'last_error_code': classification.code,
            'sync_status': classification.status,
            'next_retry_at': classification.retryable
                ? _nextRetryAt(attempts: nextAttempts).toIso8601String()
                : null,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        failed++;
        if (errors.length < 5) {
          errors.add('$entityType/$entityId: $error');
        }
        if (nextAttempts >= maxRetryAttempts) {
          skippedByMaxAttempts++;
        }
      }
    }

    if (succeeded > 0) {
      final settings = await _settingsRepository.get();
      await _settingsRepository.save(
        settings.copyWith(lastDriveSyncAt: DateTime.now()),
      );
    }

    return DriveRetryResult(
      retried: retried,
      succeeded: succeeded,
      failed: failed,
      skippedByMaxAttempts: skippedByMaxAttempts,
      recentErrors: errors,
    );
  }

  Future<int> repairPendingInvoicePdfs() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'drive_sync_queue',
      where: 'entity_type = ? AND attempts < ?',
      whereArgs: ['invoice', maxRetryAttempts],
      orderBy: 'created_at ASC',
    );
    if (rows.isEmpty) return 0;
    var repaired = 0;
    for (final row in rows) {
      final entityId = (row['entity_id'] as String?) ?? '';
      if (entityId.isEmpty) continue;
      try {
        final invoice = await _invoiceRepository.getById(entityId);
        if (invoice == null) continue;
        final client = await _clientRepository.getById(invoice.clientId);
        final settings = await _settingsRepository.get();
        final pdf = await PdfService().generateInvoicePdf(
          invoice: invoice,
          client: client ?? _fallbackClient(),
          settings: settings,
        );
        final name = _invoiceFileName(
          invoice: invoice,
          clientName: client?.nombre,
        );
        final stable = await _persistStableUploadCopy(
          source: pdf,
          entityType: 'invoice',
          entityId: invoice.id,
          fileName: name,
        );
        await db.update(
          'drive_sync_queue',
          {
            'local_file_path': stable.path,
            'file_name': name,
            'mime_type': 'application/pdf',
            'file_size_bytes': await stable.length(),
            'sync_status': statusPending,
            'last_error': null,
            'last_error_code': null,
            'next_retry_at': null,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        repaired++;
      } catch (e) {
        debugPrint('[DRIVE][REPAIR][INVOICE] invoice_id=$entityId error=$e');
      }
    }
    return repaired;
  }

  Future<int> clearInvalidQueueEntries() async {
    final db = await DatabaseHelper.instance.database;
    var removed = await db.delete(
      'drive_sync_queue',
      where:
          'sync_status = ? OR last_error LIKE ? OR last_error LIKE ? OR last_error LIKE ? OR last_error LIKE ?',
      whereArgs: [
        statusInvalidLocalFile,
        '$errorMissingFile:%',
        '$errorDevicePath:%',
        '%$errorMissingFile:%',
        '%$errorDevicePath:%',
      ],
    );
    removed += await cleanupOrphanDriveQueueEntries();
    debugPrint('[DriveSync] Limpieza inválidos/huérfanos removed=$removed');
    return removed;
  }

  Future<int> cleanupOrphanDriveQueueEntries() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'drive_sync_queue',
      columns: ['id', 'entity_type', 'entity_id'],
    );
    var removed = 0;
    for (final row in rows) {
      final queueId = row['id'] as String;
      final type = (row['entity_type'] as String?) ?? '';
      final entityId = (row['entity_id'] as String?) ?? '';
      if (await _driveQueueParentExists(type, entityId)) continue;
      await db.delete(
        'drive_sync_queue',
        where: 'id = ?',
        whereArgs: [queueId],
      );
      removed++;
      debugPrint('[DriveSync] Cola Drive huérfana eliminada: $type/$entityId');
    }
    if (removed > 0) {
      debugPrint('[DriveSync] Entradas huérfanas eliminadas: $removed');
    }
    return removed;
  }

  Future<int> removeQueueForEntity({
    required String entityType,
    required String entityId,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final removed = await db.delete(
      'drive_sync_queue',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType, entityId],
    );
    if (removed > 0) {
      debugPrint(
        '[DriveSync] Cola Drive eliminada para $entityType/$entityId: $removed',
      );
    }
    return removed;
  }

  Future<AttachmentRepairResult> repairLegacyAttachmentPaths() async {
    final attachmentService = AiAttachmentService.instance;
    var checked = 0;
    var repaired = 0;
    var missing = 0;
    var unavailable = 0;
    var failed = 0;

    final expenses = await _expenseRepository.getAll();
    for (final expense in expenses) {
      final path = expense.documentoPath;
      if (path == null || path.trim().isEmpty || expense.id == null) continue;
      checked++;
      try {
        final normalized = path.trim();
        if (attachmentService.isCrossDeviceAbsolutePath(normalized)) {
          unavailable++;
          await _expenseRepository.update(
            expense.copyWith(
              attachmentStatus: 'missing_remote',
              attachmentError:
                  'Este adjunto fue añadido desde otro dispositivo y no está disponible aquí.',
            ),
          );
          await _queueFailedSync(
            entityType: 'expense',
            entityId: expense.id!.toString(),
            action: 'upload',
            localFilePath: normalized,
            targetFolderType: 'GASTOS',
            lastError:
                '$errorDevicePath: Este adjunto fue añadido desde otro dispositivo y no está disponible aquí. Reasígnalo en este dispositivo o sincronízalo desde el dispositivo original.',
          );
          continue;
        }
        final file = File(normalized);
        if (!await file.exists()) {
          if (expense.driveFileId != null &&
              expense.driveFileId!.trim().isNotEmpty) {
            try {
              final recovered = await _recoverFromDrive(
                entityType: 'expense',
                entityId: expense.id!.toString(),
                driveFileId: expense.driveFileId!,
                extensionHint: p.extension(normalized),
              );
              await _expenseRepository.update(
                expense.copyWith(
                  documentoPath: recovered.path,
                  attachmentStatus: 'pending_upload',
                  attachmentError: null,
                ),
              );
              repaired++;
              continue;
            } catch (_) {}
          }
          missing++;
          await _expenseRepository.update(
            expense.copyWith(
              attachmentStatus: 'broken',
              attachmentError:
                  'No existe el archivo local. Reasigna el adjunto.',
            ),
          );
          await _queueFailedSync(
            entityType: 'expense',
            entityId: expense.id!.toString(),
            action: 'upload',
            localFilePath: normalized,
            targetFolderType: 'GASTOS',
            lastError:
                '$errorMissingFile: No existe el archivo local. Reasigna el adjunto.',
          );
          continue;
        }
        final persistent = await attachmentService.persistAttachment(
          normalized,
          folder: 'expenses',
        );
        if (persistent != normalized) {
          await _expenseRepository.update(
            expense.copyWith(
              documentoPath: persistent,
              attachmentStatus: 'pending_upload',
              attachmentError: null,
            ),
          );
          repaired++;
        }
      } catch (_) {
        failed++;
      }
    }

    final assets = await _assetRepository.getAll();
    for (final asset in assets) {
      final path = asset.documentoPath;
      if (path == null || path.trim().isEmpty || asset.id == null) continue;
      checked++;
      try {
        final normalized = path.trim();
        if (attachmentService.isCrossDeviceAbsolutePath(normalized)) {
          unavailable++;
          await _assetRepository.update(
            asset.copyWith(
              attachmentStatus: 'missing_remote',
              attachmentError:
                  'Este adjunto fue añadido desde otro dispositivo y no está disponible aquí.',
            ),
          );
          await _queueFailedSync(
            entityType: 'asset',
            entityId: asset.id!.toString(),
            action: 'upload',
            localFilePath: normalized,
            targetFolderType: 'INVERSIONES',
            lastError:
                '$errorDevicePath: Este adjunto fue añadido desde otro dispositivo y no está disponible aquí. Reasígnalo en este dispositivo o sincronízalo desde el dispositivo original.',
          );
          continue;
        }
        final file = File(normalized);
        if (!await file.exists()) {
          if (asset.driveFileId != null &&
              asset.driveFileId!.trim().isNotEmpty) {
            try {
              final recovered = await _recoverFromDrive(
                entityType: 'asset',
                entityId: asset.id!.toString(),
                driveFileId: asset.driveFileId!,
                extensionHint: p.extension(normalized),
              );
              await _assetRepository.update(
                asset.copyWith(
                  documentoPath: recovered.path,
                  attachmentStatus: 'pending_upload',
                  attachmentError: null,
                ),
              );
              repaired++;
              continue;
            } catch (_) {}
          }
          missing++;
          await _assetRepository.update(
            asset.copyWith(
              attachmentStatus: 'broken',
              attachmentError:
                  'No existe el archivo local. Reasigna el adjunto.',
            ),
          );
          await _queueFailedSync(
            entityType: 'asset',
            entityId: asset.id!.toString(),
            action: 'upload',
            localFilePath: normalized,
            targetFolderType: 'INVERSIONES',
            lastError:
                '$errorMissingFile: No existe el archivo local. Reasigna el adjunto.',
          );
          continue;
        }
        final persistent = await attachmentService.persistAttachment(
          normalized,
          folder: 'assets',
        );
        if (persistent != normalized) {
          await _assetRepository.update(
            asset.copyWith(
              documentoPath: persistent,
              attachmentStatus: 'pending_upload',
              attachmentError: null,
            ),
          );
          repaired++;
        }
      } catch (_) {
        failed++;
      }
    }

    return AttachmentRepairResult(
      checked: checked,
      repaired: repaired,
      missing: missing,
      unavailable: unavailable,
      failed: failed,
    );
  }

  Future<void> _syncExpense(Expense expense) async {
    debugPrint(
      '[DRIVE][UPLOAD] expense attachment found id=${expense.id} path=${expense.documentoPath ?? '-'}',
    );
    final bestPath = _bestAttachmentPath(
      expense.documentoPath,
      expense.attachmentOriginalPath,
    );
    if (bestPath == null || bestPath.isEmpty) {
      if (expense.driveFileId != null && expense.driveFileId!.isNotEmpty) {
        final recovered = await _recoverFromDrive(
          entityType: 'expense',
          entityId: expense.id!.toString(),
          driveFileId: expense.driveFileId!,
          extensionHint: '.pdf',
        );
        await _expenseRepository.update(
          expense.copyWith(
            documentoPath: recovered.path,
            attachmentStatus: 'pending_download',
            attachmentError: null,
          ),
        );
        return;
      }
      debugPrint(
        '[DRIVE][UPLOAD] skipped because missing local file expense=${expense.id}',
      );
      throw Exception('$errorMissingFile: No existe ruta local del adjunto.');
    }
    String? folderId;
    try {
      File file;
      try {
        file = await _existingFile(bestPath);
      } catch (e) {
        final canRecover =
            expense.driveFileId != null && expense.driveFileId!.isNotEmpty;
        if (!canRecover) rethrow;
        final message = e.toString();
        final isMissingLocal =
            message.contains(errorMissingFile) ||
            message.contains(errorDevicePath);
        if (!isMissingLocal) rethrow;
        final recovered = await _recoverFromDrive(
          entityType: 'expense',
          entityId: expense.id!.toString(),
          driveFileId: expense.driveFileId!,
          extensionHint: p.extension(bestPath).isEmpty
              ? '.pdf'
              : p.extension(bestPath),
        );
        await _expenseRepository.update(
          expense.copyWith(
            documentoPath: recovered.path,
            attachmentStatus: 'pending_download',
            attachmentError: null,
          ),
        );
        return;
      }
      final length = await file.length();
      if (length <= 0) {
        throw Exception('failed_file_empty: El archivo adjunto está vacío.');
      }
      final stableFile = await _persistStableUploadCopy(
        source: file,
        entityType: 'expense',
        entityId: expense.id!.toString(),
        fileName: _expenseFileName(expense, file),
      );
      final listWatch = Stopwatch()..start();
      final monthFolders = await _drive.ensureMonthStructure(expense.fecha);
      listWatch.stop();
      _driveListMs += listWatch.elapsedMilliseconds;
      folderId = monthFolders.gastosFolderId;
      final uploaded = await _uploadOrUpdate(
        existingFileId: expense.driveFileId,
        file: stableFile,
        fileName: _expenseFileName(expense, stableFile),
        parentFolderId: monthFolders.gastosFolderId,
        mimeType: _mimeTypeFor(stableFile.path),
      );
      await _expenseRepository.update(
        expense.copyWith(
          driveFileId: uploaded.fileId,
          driveFileUrl: uploaded.fileUrl,
          driveSyncedAt: DateTime.now(),
          attachmentStatus: 'uploaded',
          attachmentError: null,
        ),
      );
      final refreshed = await _expenseRepository.getById(expense.id!);
      if (refreshed != null &&
          refreshed.cloudId?.trim().isNotEmpty == true &&
          SupabaseService.instance.isAuthenticated) {
        try {
          await SupabaseService.instance.uploadExpenses([refreshed]);
          await _expenseRepository.update(refreshed.copyWith(synced: true));
        } catch (e) {
          debugPrint(
            '[DRIVE][CLOUD] expense/${expense.id} metadata upload failed: $e',
          );
        }
      }
      debugPrint(
        '[DRIVE][UPLOAD] uploaded file_id=${uploaded.fileId} entity=expense/${expense.id}',
      );
    } catch (e, st) {
      _logUploadError(
        entityType: 'expense',
        entityId: expense.id!.toString(),
        localPath: bestPath,
        targetFolder: 'Gastos',
        folderId: folderId,
        exception: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  Future<void> _syncAsset(Asset asset) async {
    debugPrint(
      '[DRIVE][UPLOAD] asset attachment found id=${asset.id} path=${asset.documentoPath ?? '-'}',
    );
    final bestPath = _bestAttachmentPath(
      asset.documentoPath,
      asset.attachmentOriginalPath,
    );
    if (bestPath == null || bestPath.isEmpty) {
      if (asset.driveFileId != null && asset.driveFileId!.isNotEmpty) {
        final recovered = await _recoverFromDrive(
          entityType: 'asset',
          entityId: asset.id!.toString(),
          driveFileId: asset.driveFileId!,
          extensionHint: '.pdf',
        );
        await _assetRepository.update(
          asset.copyWith(
            documentoPath: recovered.path,
            attachmentStatus: 'pending_download',
            attachmentError: null,
          ),
        );
        return;
      }
      debugPrint(
        '[DRIVE][UPLOAD] skipped because missing local file asset=${asset.id}',
      );
      throw Exception('$errorMissingFile: No existe ruta local del adjunto.');
    }
    String? folderId;
    try {
      File file;
      try {
        file = await _existingFile(bestPath);
      } catch (e) {
        final canRecover =
            asset.driveFileId != null && asset.driveFileId!.isNotEmpty;
        if (!canRecover) rethrow;
        final message = e.toString();
        final isMissingLocal =
            message.contains(errorMissingFile) ||
            message.contains(errorDevicePath);
        if (!isMissingLocal) rethrow;
        final recovered = await _recoverFromDrive(
          entityType: 'asset',
          entityId: asset.id!.toString(),
          driveFileId: asset.driveFileId!,
          extensionHint: p.extension(bestPath).isEmpty
              ? '.pdf'
              : p.extension(bestPath),
        );
        await _assetRepository.update(
          asset.copyWith(
            documentoPath: recovered.path,
            attachmentStatus: 'pending_download',
            attachmentError: null,
          ),
        );
        return;
      }
      final length = await file.length();
      if (length <= 0) {
        throw Exception('failed_file_empty: El archivo adjunto está vacío.');
      }
      final stableFile = await _persistStableUploadCopy(
        source: file,
        entityType: 'asset',
        entityId: asset.id!.toString(),
        fileName: _assetFileName(asset, file),
      );
      final listWatch = Stopwatch()..start();
      final monthFolders = await _drive.ensureMonthStructure(asset.fechaCompra);
      listWatch.stop();
      _driveListMs += listWatch.elapsedMilliseconds;
      folderId = monthFolders.inversionesFolderId;
      final uploaded = await _uploadOrUpdate(
        existingFileId: asset.driveFileId,
        file: stableFile,
        fileName: _assetFileName(asset, stableFile),
        parentFolderId: monthFolders.inversionesFolderId,
        mimeType: _mimeTypeFor(stableFile.path),
      );
      await _assetRepository.update(
        asset.copyWith(
          driveFileId: uploaded.fileId,
          driveFileUrl: uploaded.fileUrl,
          driveSyncedAt: DateTime.now(),
          attachmentStatus: 'uploaded',
          attachmentError: null,
        ),
      );
      final refreshed = await _assetRepository.getById(asset.id!);
      if (refreshed != null &&
          refreshed.cloudId?.trim().isNotEmpty == true &&
          SupabaseService.instance.isAuthenticated) {
        try {
          await SupabaseService.instance.uploadAssets([refreshed]);
          await _assetRepository.update(refreshed.copyWith(synced: true));
        } catch (e) {
          debugPrint(
            '[DRIVE][CLOUD] asset/${asset.id} metadata upload failed: $e',
          );
        }
      }
      debugPrint(
        '[DRIVE][UPLOAD] uploaded file_id=${uploaded.fileId} entity=asset/${asset.id}',
      );
    } catch (e, st) {
      _logUploadError(
        entityType: 'asset',
        entityId: asset.id!.toString(),
        localPath: bestPath,
        targetFolder: 'Inversiones',
        folderId: folderId,
        exception: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  Future<File> _recoverFromDrive({
    required String entityType,
    required String entityId,
    required String driveFileId,
    String extensionHint = '',
  }) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final ext = extensionHint.isEmpty ? '.bin' : extensionHint;
    final targetPath = p.join(
      docsDir.path,
      'attachments',
      '${entityType}_${entityId}_recovered$ext',
    );
    final watch = Stopwatch()..start();
    try {
      return await _drive.downloadFileTo(
        fileId: driveFileId,
        targetPath: targetPath,
      );
    } finally {
      watch.stop();
      _driveDownloadMs += watch.elapsedMilliseconds;
    }
  }

  Future<List<BrokenAttachmentItem>> getBrokenAttachments() async {
    final expenses = await _expenseRepository.getAll();
    final assets = await _assetRepository.getAll();
    final out = <BrokenAttachmentItem>[];
    for (final expense in expenses) {
      if (expense.documentoPath == null) continue;
      if (expense.attachmentStatus == 'uploaded' &&
          (expense.attachmentError == null ||
              expense.attachmentError!.isEmpty)) {
        continue;
      }
      final invalid = _isBrokenPath(expense.documentoPath!);
      if (invalid || expense.attachmentStatus == 'broken') {
        out.add(
          BrokenAttachmentItem(
            entityType: 'expense',
            entityId: (expense.id ?? 0).toString(),
            fileName: p.basename(expense.documentoPath!),
            reason: expense.attachmentError ?? 'Adjunto no disponible',
            path: expense.documentoPath,
          ),
        );
      }
    }
    for (final asset in assets) {
      if (asset.documentoPath == null) continue;
      if (asset.attachmentStatus == 'uploaded' &&
          (asset.attachmentError == null || asset.attachmentError!.isEmpty)) {
        continue;
      }
      final invalid = _isBrokenPath(asset.documentoPath!);
      if (invalid || asset.attachmentStatus == 'broken') {
        out.add(
          BrokenAttachmentItem(
            entityType: 'asset',
            entityId: (asset.id ?? 0).toString(),
            fileName: p.basename(asset.documentoPath!),
            reason: asset.attachmentError ?? 'Adjunto no disponible',
            path: asset.documentoPath,
          ),
        );
      }
    }
    return out;
  }

  bool _isBrokenPath(String path) {
    final normalized = path.trim();
    if (AiAttachmentService.instance.isTemporaryPath(normalized)) return true;
    if (AiAttachmentService.instance.isCrossDeviceAbsolutePath(normalized)) {
      return true;
    }
    return !File(normalized).existsSync();
  }

  Future<DriveUploadResult> _uploadOrUpdate({
    required String? existingFileId,
    required File file,
    required String fileName,
    required String parentFolderId,
    required String mimeType,
  }) async {
    final watch = Stopwatch()..start();
    try {
      if (existingFileId != null && existingFileId.isNotEmpty) {
        debugPrint(
          '[DRIVE][OP] operation=update drive_file_id=$existingFileId local_path=${file.path} mime=$mimeType',
        );
        return await _drive.updateFile(
          fileId: existingFileId,
          file: file,
          mimeType: mimeType,
        );
      }
      final existingByName = await _drive.findFileInFolderByName(
        parentFolderId: parentFolderId,
        fileName: fileName,
      );
      if (existingByName != null) {
        debugPrint(
          '[DRIVE][OP] operation=query_by_name_and_update folder_id=$parentFolderId file_name=$fileName drive_file_id=${existingByName.fileId} local_path=${file.path}',
        );
        return await _drive.updateFile(
          fileId: existingByName.fileId,
          file: file,
          mimeType: mimeType,
        );
      }
      debugPrint(
        '[DRIVE][OP] operation=create_upload folder_id=$parentFolderId file_name=$fileName local_path=${file.path} mime=$mimeType',
      );
      return await _drive.uploadFile(
        file: file,
        fileName: fileName,
        parentFolderId: parentFolderId,
        mimeType: mimeType,
      );
    } finally {
      watch.stop();
      _driveUploadMs += watch.elapsedMilliseconds;
    }
  }

  Future<File> _persistStableUploadCopy({
    required File source,
    required String entityType,
    required String entityId,
    required String fileName,
  }) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final ext = p.extension(fileName).isEmpty
        ? p.extension(source.path)
        : p.extension(fileName);
    final safeExt = ext.isEmpty ? '.bin' : ext;
    final base = sanitizeDriveFileName(p.basenameWithoutExtension(fileName));
    final target = p.join(
      docsDir.path,
      'drive_upload_cache',
      entityType,
      '${entityId}_$base$safeExt',
    );
    final targetFile = File(target);
    await targetFile.parent.create(recursive: true);
    if (source.path != target) {
      await source.copy(target);
    }
    return targetFile;
  }

  bool _invoiceDriveAlreadySynced(Invoice invoice) {
    final syncedAt = invoice.driveSyncedAt;
    if (invoice.driveFileId?.isNotEmpty != true || syncedAt == null) {
      return false;
    }
    final updatedAfterSync = invoice.updatedAt.difference(syncedAt);
    return updatedAfterSync <= Duration.zero ||
        updatedAfterSync < const Duration(seconds: 5);
  }

  bool _expenseDriveAlreadySynced(Expense expense) {
    return expense.driveFileId?.isNotEmpty == true &&
        expense.driveSyncedAt != null &&
        expense.attachmentStatus == 'uploaded';
  }

  bool _assetDriveAlreadySynced(Asset asset) {
    return asset.driveFileId?.isNotEmpty == true &&
        asset.driveSyncedAt != null &&
        asset.attachmentStatus == 'uploaded';
  }

  bool _shouldSkipBrokenAttachment(String status) {
    return status == 'broken' ||
        status == 'missing_local' ||
        status == 'missing_remote';
  }

  Future<bool> _driveQueueParentExists(
    String entityType,
    String entityId,
  ) async {
    final normalizedType = _canonicalEntityType(entityType);
    if (normalizedType == 'backup') return true;
    if (normalizedType == 'invoice') {
      return _invoiceRepository
          .getById(entityId)
          .then((value) => value != null);
    }
    if (normalizedType == 'expense') {
      final id = int.tryParse(entityId);
      if (id == null) return false;
      return _expenseRepository.getById(id).then((value) => value != null);
    }
    if (normalizedType == 'asset') {
      final id = int.tryParse(entityId);
      if (id == null) return false;
      return _assetRepository.getById(id).then((value) => value != null);
    }
    return false;
  }

  String _canonicalEntityType(String raw) {
    final value = raw.trim().toLowerCase();
    if (value == 'investment') return 'asset';
    return value;
  }

  Future<File> _existingFile(String path) async {
    final normalized = path.replaceAll('\\', '/');
    if (AiAttachmentService.instance.isCrossDeviceAbsolutePath(normalized)) {
      throw Exception(
        '$errorDevicePath: Este adjunto fue añadido desde otro dispositivo y no está disponible aquí. Reasígnalo en este dispositivo o sincronízalo desde el dispositivo original.',
      );
    }
    try {
      final file = File(path);
      if (!await file.exists()) {
        throw Exception('$errorMissingFile: No existe el archivo local: $path');
      }
      return file;
    } on PathAccessException {
      throw Exception(
        '$errorDevicePath: Este adjunto fue añadido desde otro dispositivo y no está disponible aquí. Reasígnalo en este dispositivo o sincronízalo desde el dispositivo original.',
      );
    } on FileSystemException {
      throw Exception('$errorMissingFile: No existe el archivo local: $path');
    }
  }

  Future<void> _logUploadError({
    required String entityType,
    required String entityId,
    required Object exception,
    required StackTrace stackTrace,
    required String targetFolder,
    String? localPath,
    String? folderId,
  }) async {
    final normalizedPath = localPath?.trim();
    final hasLocalPath = normalizedPath != null && normalizedPath.isNotEmpty;
    final exists = hasLocalPath ? File(normalizedPath).existsSync() : false;
    int? size;
    if (exists && hasLocalPath) {
      try {
        size = await File(normalizedPath).length();
      } catch (_) {}
    }
    final connected = await _drive.isConnected();
    String? rootFolderId;
    try {
      rootFolderId = await _drive.ensureRootFolder();
    } catch (_) {}
    debugPrint('[DRIVE][UPLOAD][ERROR] attachment_id=$entityId');
    debugPrint('[DRIVE][UPLOAD][ERROR] entity_type=$entityType');
    debugPrint('[DRIVE][UPLOAD][ERROR] local_path=${normalizedPath ?? '-'}');
    debugPrint('[DRIVE][UPLOAD][ERROR] file_exists=$exists');
    debugPrint('[DRIVE][UPLOAD][ERROR] file_size=${size ?? 0}');
    debugPrint('[DRIVE][UPLOAD][ERROR] drive_connected=$connected');
    debugPrint('[DRIVE][UPLOAD][ERROR] root_folder_id=${rootFolderId ?? '-'}');
    debugPrint('[DRIVE][UPLOAD][ERROR] folder_id=${folderId ?? '-'}');
    debugPrint('[DRIVE][UPLOAD][ERROR] target_folder=$targetFolder');
    debugPrint('[DRIVE][UPLOAD][ERROR] exception=$exception');
    debugPrint('[DRIVE][UPLOAD][ERROR] stacktrace=$stackTrace');
  }

  String _invoiceFileName({
    required Invoice invoice,
    required String? clientName,
  }) {
    return buildInvoicePdfFileName(invoice: invoice, clientName: clientName);
  }

  String _expenseFileName(Expense expense, File file) {
    final original = expense.attachmentOriginalName?.trim();
    if (original != null && original.isNotEmpty) {
      return sanitizeDriveFileName(original);
    }
    final date = _dateFormat.format(expense.fecha);
    final provider = expense.proveedor?.trim().isNotEmpty == true
        ? expense.proveedor!.trim()
        : 'Sin proveedor';
    final amount = _moneyFormat.format(expense.total);
    return sanitizeDriveFileName(
      '$date - ${expense.concepto} - $provider - $amount${_extension(file)}',
    );
  }

  String _assetFileName(Asset asset, File file) {
    final original = asset.attachmentOriginalName?.trim();
    if (original != null && original.isNotEmpty) {
      final ext = p.extension(original).isNotEmpty
          ? p.extension(original)
          : _extension(file);
      final base = p.basenameWithoutExtension(original).trim();
      final desc = asset.descripcion.trim();
      final composed = desc.isEmpty ? '$base$ext' : '$base - $desc$ext';
      return sanitizeDriveFileName(composed);
    }
    final date = _dateFormat.format(asset.fechaCompra);
    final amount = _moneyFormat.format(
      asset.importeConIva > 0 ? asset.importeConIva : asset.importeTotal,
    );
    return sanitizeDriveFileName(
      '$date - ${asset.descripcion} - $amount${_extension(file)}',
    );
  }

  String _extension(File file) {
    final ext = p.extension(file.path).toLowerCase();
    return ext.isEmpty ? '' : ext;
  }

  String? _bestAttachmentPath(String? primary, String? fallback) {
    final p1 = primary?.trim();
    if (p1 != null && p1.isNotEmpty) return p1;
    final p2 = fallback?.trim();
    if (p2 != null && p2.isNotEmpty) return p2;
    return null;
  }

  String _mimeTypeFor(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.pdf':
        return 'application/pdf';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.heic':
        return 'image/heic';
      default:
        return 'application/octet-stream';
    }
  }

  ({String code, String status, bool retryable}) _classifyDriveError(
    String message,
  ) {
    final m = message.toLowerCase();
    final badDescriptorOnGoogleApi =
        m.contains('bad file descriptor') &&
        m.contains('googleapis.com/drive/v3');
    if (badDescriptorOnGoogleApi) {
      return (
        code: errorInternalBug,
        status: statusInternalBug,
        retryable: false,
      );
    }
    if (m.contains(errorMissingFile) ||
        m.contains(errorDevicePath) ||
        m.contains('bad file descriptor')) {
      return (
        code: m.contains('bad file descriptor')
            ? errorBadFileDescriptor
            : (m.contains(errorDevicePath)
                  ? errorDevicePath
                  : errorMissingFile),
        status: statusInvalidLocalFile,
        retryable: false,
      );
    }
    if (m.contains('handshakeexception') ||
        m.contains('connection terminated') ||
        m.contains('socketexception') ||
        m.contains('timeout')) {
      return (
        code: m.contains('handshakeexception') ? errorHandshake : errorNetwork,
        status: statusRetryable,
        retryable: true,
      );
    }
    return (code: 'unknown_error', status: statusRetryable, retryable: true);
  }

  DateTime _nextRetryAt({required int attempts}) {
    final sec = (1 << attempts).clamp(30, 1800);
    return DateTime.now().add(Duration(seconds: sec));
  }

  Future<void> _queueFailedSync({
    required String entityType,
    required String entityId,
    required String action,
    required String targetFolderType,
    required String lastError,
    String? localFilePath,
    String? documentType,
    String? fileName,
    String? mimeType,
    int? fileSizeBytes,
    String? driveFileId,
    String? remoteFolderId,
    String? logicalPath,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final normalizedLocalPath = (() {
      final raw = localFilePath?.trim();
      if (raw == null || raw.isEmpty) return null;
      if (raw.startsWith('http://') || raw.startsWith('https://')) {
        return null;
      }
      return raw;
    })();
    final existing = await db.query(
      'drive_sync_queue',
      where: 'entity_type = ? AND entity_id = ? AND action = ?',
      whereArgs: [entityType, entityId, action],
      limit: 1,
    );
    final now = DateTime.now().toIso8601String();
    final classification = _classifyDriveError(lastError);
    if (existing.isEmpty) {
      await db.insert('drive_sync_queue', {
        'id': const Uuid().v4(),
        'entity_type': entityType,
        'entity_id': entityId,
        'action': action,
        'local_file_path': normalizedLocalPath,
        'target_folder_type': targetFolderType,
        'attempts': 1,
        'last_error': lastError,
        'last_error_code': classification.code,
        'sync_status': classification.status,
        'next_retry_at': classification.retryable
            ? _nextRetryAt(attempts: 1).toIso8601String()
            : null,
        'document_type': documentType,
        'file_name': fileName,
        'mime_type': mimeType,
        'file_size_bytes': fileSizeBytes,
        'drive_file_id': driveFileId,
        'remote_folder_id': remoteFolderId,
        'logical_path': logicalPath,
        'created_at': now,
        'updated_at': now,
      });
      return;
    }
    final current = existing.first;
    final currentAttempts = (current['attempts'] as int?) ?? 0;
    final nextAttempts = currentAttempts + 1;
    await db.update(
      'drive_sync_queue',
      {
        'local_file_path': normalizedLocalPath ?? current['local_file_path'],
        'target_folder_type': targetFolderType,
        'attempts': nextAttempts,
        'last_error': lastError,
        'last_error_code': classification.code,
        'sync_status': classification.status,
        'next_retry_at': classification.retryable
            ? _nextRetryAt(attempts: nextAttempts).toIso8601String()
            : null,
        'document_type': documentType ?? current['document_type'],
        'file_name': fileName ?? current['file_name'],
        'mime_type': mimeType ?? current['mime_type'],
        'file_size_bytes': fileSizeBytes ?? current['file_size_bytes'],
        'drive_file_id': driveFileId ?? current['drive_file_id'],
        'remote_folder_id': remoteFolderId ?? current['remote_folder_id'],
        'logical_path': logicalPath ?? current['logical_path'],
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [current['id']],
    );
  }

  Client _fallbackClient() => Client(nombre: 'Sin cliente');

  static final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');
  static final NumberFormat _moneyFormat = NumberFormat('#,##0.00', 'es_ES');
}
