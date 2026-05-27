import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/expense.dart';
import '../repositories/expense_repository.dart';
import '../core/services/drive_document_sync_service.dart';
import '../core/services/google_drive_service.dart';
import '../services/supabase_service.dart';
import '../services/ai_attachment_service.dart';
import '../repositories/settings_repository.dart';

final expenseRepositoryProvider = Provider((ref) => ExpenseRepository.instance);

final expensesProvider = AsyncNotifierProvider<ExpensesNotifier, List<Expense>>(
  ExpensesNotifier.new,
);

class ExpensesNotifier extends AsyncNotifier<List<Expense>> {
  RealtimeChannel? _expensesChannel;
  StreamSubscription<AuthState>? _authSubscription;
  bool _realtimeStarted = false;
  bool _initialPullDone = false;
  bool _isPulling = false;
  bool _isApplyingRemoteChange = false;

  @override
  Future<List<Expense>> build() async {
    _startRealtimeIfNeeded();
    await pullInitialFromCloud(updateState: false);
    return ref.read(expenseRepositoryProvider).getAll();
  }

  Future<void> enterScreen() async {
    await pullInitialFromCloud();
    _startRealtimeIfNeeded();
  }

  void leaveScreen() {
    // Mantener realtime activo aunque salgas de la pantalla para reflejar
    // borrados/altas desde otros dispositivos sin sync manual.
  }

  Future<void> pullInitialFromCloud({
    bool force = false,
    bool updateState = true,
  }) async {
    final supabase = SupabaseService.instance;
    if (!supabase.isAuthenticated) return;
    if (!force && _initialPullDone) return;
    if (_isPulling) return;

    _isPulling = true;
    try {
      debugPrint('[ExpensesSync] Pull inicial expenses (Supabase -> SQLite)');
      final remote = await supabase.downloadExpenses();
      _isApplyingRemoteChange = true;
      try {
        for (final expense in remote) {
          await ref.read(expenseRepositoryProvider).upsertByCloudId(expense);
        }
      } finally {
        _isApplyingRemoteChange = false;
      }
      _initialPullDone = true;
      if (updateState) {
        await reloadLocal();
      }
    } catch (e) {
      debugPrint('[ExpensesSync] Pull inicial error: $e');
    } finally {
      _isPulling = false;
    }
  }

  void _startRealtimeIfNeeded() {
    if (_realtimeStarted) return;
    _realtimeStarted = true;

    final supabase = SupabaseService.instance;
    if (!supabase.isAuthenticated || supabase.userId == null) {
      debugPrint('[ExpensesSync] Realtime no iniciado: sin sesión');
      return;
    }

    _authSubscription?.cancel();
    _authSubscription = supabase.authStateChanges?.listen((event) {
      if (event.event == AuthChangeEvent.signedOut) {
        _disposeRealtime();
      }
    });

    final client = Supabase.instance.client;
    _expensesChannel = client
        .channel('public:expenses:user:${supabase.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'expenses',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: supabase.userId!,
          ),
          callback: _handleRealtimeEvent,
        )
        .subscribe();

    debugPrint('[ExpensesSync] Realtime suscrito (expenses)');
  }

  void _disposeRealtime() {
    final channel = _expensesChannel;
    _expensesChannel = null;
    _realtimeStarted = false;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
      debugPrint('[ExpensesSync] Realtime desuscrito (expenses)');
    }
    _authSubscription?.cancel();
    _authSubscription = null;
  }

  Expense? _expenseFromRealtimeRecord(Map<String, dynamic> m) {
    final cloudId = m['id']?.toString();
    final userId = m['user_id']?.toString();
    final fechaRaw = m['fecha']?.toString();
    final concepto = m['concepto']?.toString();
    final importeBaseRaw = m['importe_base'];
    final ivaRateRaw = m['iva_rate'];
    final ivaAmountRaw = m['iva_amount'];
    final totalRaw = m['total'];
    final categoriaRaw = m['categoria']?.toString();
    final createdAtRaw = m['created_at']?.toString();
    if (cloudId == null ||
        userId == null ||
        fechaRaw == null ||
        concepto == null ||
        importeBaseRaw == null ||
        ivaRateRaw == null ||
        ivaAmountRaw == null ||
        totalRaw == null ||
        categoriaRaw == null ||
        createdAtRaw == null) {
      return null;
    }

    try {
      return Expense(
        cloudId: cloudId,
        userId: userId,
        fecha: DateTime.parse(fechaRaw),
        concepto: concepto,
        proveedor: m['proveedor']?.toString(),
        importeBase: (importeBaseRaw as num).toDouble(),
        ivaRate: (ivaRateRaw as num).toDouble(),
        ivaAmount: (ivaAmountRaw as num).toDouble(),
        total: (totalRaw as num).toDouble(),
        categoria: ExpenseCategoryExtension.fromDb(categoriaRaw),
        esDeducible: m['es_deducible'] as bool? ?? true,
        porcentajeDeduccion:
            (m['porcentaje_deduccion'] as num?)?.toDouble() ?? 100.0,
        driveFileId: m['drive_file_id']?.toString(),
        driveFileUrl: m['drive_file_url']?.toString(),
        driveSyncedAt: m['drive_synced_at'] != null
            ? DateTime.tryParse(m['drive_synced_at'].toString())
            : null,
        documentoPath: m['documento_path']?.toString(),
        notas: m['notas']?.toString(),
        synced: true,
        createdAt: DateTime.parse(createdAtRaw),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleRealtimeEvent(PostgresChangePayload payload) async {
    if (_isPulling || _isApplyingRemoteChange) return;

    final event = payload.eventType;
    final id =
        (payload.newRecord['id'] ?? payload.oldRecord['id'])?.toString() ??
        'unknown';

    try {
      _isApplyingRemoteChange = true;
      if (event == PostgresChangeEvent.delete ||
          (event == PostgresChangeEvent.update &&
              payload.newRecord['deleted_at'] != null)) {
        final cloudId = payload.oldRecord['id']?.toString();
        final resolvedCloudId = cloudId ?? payload.newRecord['id']?.toString();
        if (resolvedCloudId != null) {
          await ref
              .read(expenseRepositoryProvider)
              .deleteByCloudId(resolvedCloudId);
        }
      } else {
        final expense = _expenseFromRealtimeRecord(payload.newRecord);
        if (expense == null) return;
        await ref.read(expenseRepositoryProvider).upsertByCloudId(expense);
      }
      await reloadLocal();
      debugPrint(
        '[ExpensesSync] Realtime ${event.name.toUpperCase()} expense_id=$id',
      );
    } catch (e) {
      debugPrint('[ExpensesSync] Realtime error expense_id=$id: $e');
    } finally {
      _isApplyingRemoteChange = false;
    }
  }

  Future<void> reloadLocal() async {
    final expenses = await ref.read(expenseRepositoryProvider).getAll();
    state = AsyncData(expenses);
  }

  Future<void> add(Expense expense) async {
    final repo = ref.read(expenseRepositoryProvider);
    final localId = await repo.insert(
      expense.copyWith(
        synced: false,
        attachmentStatus: expense.documentoPath == null
            ? 'pending_upload'
            : 'pending_upload',
      ),
    );
    final saved = await repo.getById(localId);
    if (saved != null && saved.documentoPath != null) {
      try {
        final stablePath = await AiAttachmentService.instance
            .persistAttachmentForEntity(
              sourcePath: saved.documentoPath!,
              entityType: 'expense',
              entityId: saved.id.toString(),
            );
        await repo.update(
          saved.copyWith(
            documentoPath: stablePath,
            attachmentStatus: 'pending_upload',
            attachmentError: null,
            attachmentOriginalPath: saved.documentoPath,
            attachmentOriginalName: AiAttachmentService.instance
                .normalizeOriginalFileName(saved.documentoPath!),
            attachmentStoredName: p.basename(stablePath),
            attachmentMimeType: _mimeTypeFor(stablePath),
            synced: false,
          ),
        );
      } catch (e) {
        await repo.update(
          saved.copyWith(
            attachmentStatus: 'broken',
            attachmentError: e.toString(),
            attachmentOriginalPath: saved.documentoPath,
            synced: false,
          ),
        );
      }
    }
    ref.invalidateSelf();
    await _tryUploadExpense(localId);
    await _tryAutoSyncExpenseToDrive(localId);
  }

  Future<void> updateExpense(Expense expense) async {
    final repo = ref.read(expenseRepositoryProvider);
    var updated = expense.copyWith(synced: false);
    if (updated.documentoPath != null && updated.id != null) {
      try {
        final stablePath = await AiAttachmentService.instance
            .persistAttachmentForEntity(
              sourcePath: updated.documentoPath!,
              entityType: 'expense',
              entityId: updated.id.toString(),
            );
        updated = updated.copyWith(
          documentoPath: stablePath,
          attachmentStatus: 'pending_upload',
          attachmentError: null,
          attachmentOriginalPath: expense.documentoPath,
          attachmentOriginalName:
              expense.attachmentOriginalName ??
              AiAttachmentService.instance.normalizeOriginalFileName(
                expense.documentoPath!,
              ),
          attachmentStoredName: p.basename(stablePath),
          attachmentMimeType: _mimeTypeFor(stablePath),
        );
      } catch (e) {
        updated = updated.copyWith(
          attachmentStatus: 'broken',
          attachmentError: e.toString(),
          attachmentOriginalPath: expense.documentoPath,
        );
      }
    }
    await repo.update(updated);
    ref.invalidateSelf();
    if (expense.id != null) {
      await _tryUploadExpense(expense.id!);
      await _tryAutoSyncExpenseToDrive(expense.id!);
    }
  }

  String _mimeTypeFor(String path) {
    final ext = p.extension(path).toLowerCase();
    switch (ext) {
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

  Future<void> remove(int id, {bool deleteFromDrive = false}) async {
    final repo = ref.read(expenseRepositoryProvider);
    final existing = await repo.getById(id);
    if (deleteFromDrive && existing?.driveFileId?.trim().isNotEmpty == true) {
      try {
        await GoogleDriveService.instance.trashFile(existing!.driveFileId!);
      } catch (e) {
        debugPrint('[ExpensesSync] No se pudo enviar a papelera en Drive: $e');
      }
    }
    if (existing?.cloudId != null) {
      await DatabaseHelper.instance.addPendingDeletion(
        'expenses',
        existing!.cloudId!,
      );
      try {
        await SupabaseService.instance.deleteExpense(existing.cloudId!);
      } catch (e) {
        debugPrint('[ExpensesSync] deleteExpense directo falló: $e');
      }
    }
    final localDocPath = existing?.documentoPath;
    await repo.delete(id);
    if (localDocPath != null && localDocPath.trim().isNotEmpty) {
      try {
        final file = File(localDocPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('[ExpensesSync] No se pudo borrar adjunto local: $e');
      }
    }
    await DriveDocumentSyncService.instance.removeQueueForEntity(
      entityType: 'expense',
      entityId: id.toString(),
    );
    ref.invalidateSelf();
  }

  Future<void> _tryUploadExpense(int localId) async {
    final supabase = SupabaseService.instance;
    if (!supabase.isAuthenticated) return;
    final repo = ref.read(expenseRepositoryProvider);
    final expense = await repo.getById(localId);
    if (expense == null) return;

    var updated = expense;
    if (updated.cloudId == null) {
      final cloudId = const Uuid().v4();
      await repo.saveCloudId(localId, cloudId);
      updated = updated.copyWith(cloudId: cloudId);
    }

    try {
      await supabase.uploadExpenses([updated.copyWith(synced: true)]);
      await repo.update(
        updated.copyWith(
          synced: true,
          attachmentStatus: updated.documentoPath == null
              ? updated.attachmentStatus
              : 'pending_upload',
        ),
      );
      await reloadLocal();
    } catch (e) {
      debugPrint('[ExpensesSync] Upload directo error: $e');
    }
  }

  Future<void> _tryAutoSyncExpenseToDrive(int localId) async {
    final settings = await SettingsRepository().get();
    final ready =
        settings.driveConnected &&
        (settings.driveRootFolderId?.trim().isNotEmpty ?? false);
    if (!ready) return;
    try {
      await DriveDocumentSyncService.instance.syncExpenseById(localId);
    } catch (e) {
      debugPrint(
        '[ExpensesSync] Auto Drive sync error expense_id=$localId: $e',
      );
    }
  }
}

final expenseByIdProvider = FutureProvider.family<Expense?, int>((ref, id) {
  return ref.read(expenseRepositoryProvider).getById(id);
});

final expensesByCategoriaProvider =
    FutureProvider.family<List<Expense>, ExpenseCategory>((ref, categoria) {
      return ref.read(expenseRepositoryProvider).getByCategoria(categoria);
    });

final expensesByQuarterProvider =
    FutureProvider.family<List<Expense>, ({int year, int quarter})>((
      ref,
      params,
    ) {
      final repo = ref.read(expenseRepositoryProvider);
      final startMonth = (params.quarter - 1) * 3 + 1;
      final from = DateTime(params.year, startMonth, 1);
      final to = DateTime(params.year, startMonth + 3, 0, 23, 59, 59);
      return repo.getByDateRange(from, to);
    });

final gastosTrimestralProvider =
    FutureProvider.family<Map<String, double>, ({int year, int quarter})>((
      ref,
      params,
    ) {
      return ref
          .read(expenseRepositoryProvider)
          .getTotalesPorCategoria(params.year, params.quarter);
    });

final ivaDeducibleTrimestralProvider =
    FutureProvider.family<double, ({int year, int quarter})>((ref, params) {
      return ref
          .read(expenseRepositoryProvider)
          .getTotalIvaSoportadoTrimestre(params.year, params.quarter);
    });
