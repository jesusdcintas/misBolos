import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_settings.dart';
import '../models/client.dart';
import '../models/expense.dart';
import '../models/asset.dart';
import '../models/gig.dart';
import '../models/invoice.dart';
import '../models/sync_queue_item.dart';

class SupabaseService {
  static final SupabaseService instance = SupabaseService._();
  SupabaseService._();

  SupabaseClient? _client;
  bool _initialized = false;

  bool get isInitialized => _initialized && _client != null;
  bool get isAuthenticated => _client?.auth.currentUser != null;
  String? get userId => _client?.auth.currentUser?.id;
  String? get userEmail => _client?.auth.currentUser?.email;
  String? get providerAccessToken =>
      _client?.auth.currentSession?.providerToken;
  String? get providerRefreshToken =>
      _client?.auth.currentSession?.providerRefreshToken;
  User? get currentUser => _client?.auth.currentUser;

  /// Stream de cambios de estado de autenticación
  Stream<AuthState>? get authStateChanges => _client?.auth.onAuthStateChange;

  Future<void> initialize({
    required String url,
    required String anonKey,
  }) async {
    if (_initialized) return;

    await Supabase.initialize(url: url, anonKey: anonKey);
    _client = Supabase.instance.client;
    _initialized = true;
    debugPrint('[Supabase] Initialized');

    // Escuchar cambios de auth para debug
    _client?.auth.onAuthStateChange.listen(
      (data) {
        debugPrint(
          '[Supabase] Auth state changed: ${data.event} - ${data.session?.user.email}',
        );
      },
      onError: (Object error) {
        debugPrint('[Supabase] Auth state warning: $error');
      },
    );
  }

  /// Autenticar con Google ID token (para iOS/Android)
  Future<bool> signInWithGoogle(String idToken, String accessToken) async {
    if (_client == null) return false;

    try {
      final response = await _client!.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      debugPrint('[Supabase] Signed in as ${response.user?.email}');
      return response.user != null;
    } catch (e) {
      debugPrint('[Supabase] Sign in error: $e');
      return false;
    }
  }

  /// Autenticar con OAuth (para macOS/Desktop)
  /// Abre el navegador y espera el callback
  Future<bool> signInWithOAuth() async {
    if (_client == null) return false;

    try {
      debugPrint('[Supabase] Starting OAuth flow...');

      final response = await _client!.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: Platform.isMacOS ? 'misbolos://login-callback' : null,
        scopes:
            'openid email profile https://www.googleapis.com/auth/drive https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/calendar.events',
        queryParams: const {
          'access_type': 'offline',
          'include_granted_scopes': 'true',
        },
        authScreenLaunchMode: LaunchMode.externalApplication,
      );

      debugPrint('[Supabase] OAuth response: $response');

      // En desktop, el usuario completa el flujo en el navegador
      // y Supabase maneja el callback automáticamente
      return response;
    } catch (e) {
      debugPrint('[Supabase] OAuth error: $e');
      return false;
    }
  }

  Future<void> signOut() async {
    await _client?.auth.signOut();
    debugPrint('[Supabase] Signed out');
  }

  Future<AuthResponse> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    if (_client == null) {
      throw StateError('Supabase no está inicializado');
    }
    return _client!.auth.signInWithPassword(email: email, password: password);
  }

  Future<AuthResponse> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {
    if (_client == null) {
      throw StateError('Supabase no está inicializado');
    }
    return _client!.auth.signUp(email: email, password: password);
  }

  Future<void> sendPasswordResetEmail({
    required String email,
    String? redirectTo,
  }) async {
    if (_client == null) {
      throw StateError('Supabase no está inicializado');
    }
    final effectiveRedirect =
        redirectTo ??
        (Platform.isIOS || Platform.isAndroid || Platform.isMacOS
            ? 'misbolos://reset-password'
            : null);
    await _client!.auth.resetPasswordForEmail(
      email,
      redirectTo: effectiveRedirect,
    );
  }

  Future<UserResponse> updatePassword(String newPassword) async {
    if (_client == null) {
      throw StateError('Supabase no está inicializado');
    }
    return _client!.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<dynamic> invokeFunction(
    String functionName, {
    required Map<String, dynamic> body,
  }) async {
    if (!isAuthenticated) {
      throw Exception('Supabase no está autenticado');
    }
    final response = await _client!.functions.invoke(functionName, body: body);
    return response.data;
  }

  Future<void> requestCreateOrResetPassword() async {
    final email = userEmail;
    if (email == null || email.trim().isEmpty) {
      throw StateError('No hay email de usuario autenticado.');
    }
    await sendPasswordResetEmail(email: email);
  }

  Future<void> deleteCurrentAccount() async {
    if (!isAuthenticated) {
      throw StateError('No hay sesión autenticada.');
    }
    await invokeFunction('delete-user-account', body: const {});
  }

  Future<bool?> checkAccountExistsByEmail(String email) async {
    if (!isInitialized) return null;
    try {
      final response = await _client!.functions.invoke(
        'check-account-exists',
        body: {'email': email.trim().toLowerCase()},
      );
      final data = response.data;
      if (data is Map && data['ok'] == true) {
        return data['exists'] == true;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ================== UPLOAD (Local → Cloud) ==================

  Future<void> uploadClients(List<Client> clients) async {
    if (!isAuthenticated) return;

    for (final client in clients) {
      final map = _clientToSupabase(client);
      await _client!.from('clients').upsert(map, onConflict: 'id');
    }
    debugPrint('[Supabase] Uploaded ${clients.length} clients');
  }

  /// IDs de invoices válidos (se establecen antes de subir gigs)
  Set<String> _validInvoiceIds = {};

  /// Sincroniza todos los bolos (incluidos los "en B")
  Future<void> uploadGigs(List<Gig> gigs) async {
    if (!isAuthenticated) return;

    for (final gig in gigs) {
      final map = _gigToSupabase(gig);
      // Si el invoice_id no existe en las facturas válidas, lo ponemos a null
      if (gig.invoiceId != null && !_validInvoiceIds.contains(gig.invoiceId)) {
        map['invoice_id'] = null;
      }
      await _client!.from('gigs').upsert(map, onConflict: 'id');
    }
    debugPrint('[Supabase] Uploaded ${gigs.length} gigs');
  }

  Future<void> uploadGigDirect(Gig gig) async {
    if (!isAuthenticated) return;
    await _client!.from('gigs').upsert(_gigToSupabase(gig), onConflict: 'id');
    debugPrint('[Supabase] Uploaded gig ${gig.id}');
  }

  Future<void> processQueuedItem(SyncQueueItem item) async {
    if (!isAuthenticated) return;

    debugPrint(
      '[SupabaseQueue] ${item.operation.dbValue} ${item.entityType.dbValue}/${item.entityId}',
    );

    if (item.entityType == SyncEntityType.gig) {
      if (item.operation == SyncOperation.delete) {
        await softDeleteGig(
          item.entityId,
          deletedAt: _readPayloadDate(item.payload, 'deleted_at'),
        );
        return;
      }
      await uploadGigDirect(Gig.fromMap(item.payload));
      return;
    }

    if (item.operation == SyncOperation.delete) {
      await softDeleteInvoice(
        item.entityId,
        deletedAt: _readPayloadDate(item.payload, 'deleted_at'),
      );
      return;
    }
    final includeNumber = item.operation == SyncOperation.create;
    await uploadInvoices([
      Invoice.fromMap(item.payload),
    ], includeNumberForExisting: includeNumber);
  }

  Future<void> uploadInvoices(
    List<Invoice> invoices, {
    bool includeNumberForExisting = false,
  }) async {
    if (!isAuthenticated) return;

    for (final invoice in invoices) {
      final exists = await _remoteInvoiceExists(invoice.id);
      await _uploadInvoiceWithFallback(
        invoice,
        includeNumber: !exists || includeNumberForExisting,
      );
    }
    debugPrint('[Supabase] Uploaded ${invoices.length} invoices');
  }

  Future<bool> _remoteInvoiceExists(String invoiceId) async {
    final rows = await _client!
        .from('invoices')
        .select('id')
        .eq('user_id', userId!)
        .eq('id', invoiceId)
        .limit(1);
    return (rows as List).isNotEmpty;
  }

  Future<void> _uploadInvoiceWithFallback(
    Invoice invoice, {
    required bool includeNumber,
  }) async {
    if (includeNumber && invoice.numero <= 0) {
      throw StateError('No se pueden subir números temporales a Supabase.');
    }

    final map = _invoiceToSupabaseEs(invoice, includeNumber: includeNumber);
    if (includeNumber) {
      await _upsertInvoiceWithSchemaFallback(invoice, map);
    } else {
      await _updateInvoiceWithSchemaFallback(invoice, map);
    }
  }

  Future<void> renumberInvoices(
    List<Invoice> invoices, {
    String? reason,
  }) async {
    if (!isAuthenticated || invoices.isEmpty) return;
    if (invoices.any((invoice) => invoice.numero <= 0)) {
      throw StateError('Supabase no puede recibir números temporales.');
    }

    final fiscalYears = invoices.map((invoice) => invoice.fecha.year).toSet();
    if (fiscalYears.length != 1) {
      throw StateError('Solo se puede reenumerar un año fiscal cada vez.');
    }

    final changes = invoices
        .map((invoice) => {'id': invoice.id, 'numero': invoice.numero})
        .toList(growable: false);
    await _client!.rpc(
      'renumber_invoices_manually',
      params: {
        'p_fiscal_year': fiscalYears.single,
        'p_changes': changes,
        'p_reason': reason ?? 'manual_renumber_from_flutter',
      },
    );

    debugPrint(
      '[Supabase] Manual renumbered ${invoices.length} invoices for year ${fiscalYears.single}',
    );
  }

  Future<bool> hasAuthorizedInvoiceNumberChange({
    required String invoiceId,
    required int newNumber,
  }) async {
    if (!isAuthenticated) return false;
    try {
      final rows = await _client!
          .from('invoice_number_changes')
          .select('id')
          .eq('user_id', userId!)
          .eq('invoice_id', invoiceId)
          .eq('new_number', newNumber)
          .eq('source', 'manual_renumber')
          .limit(1);
      return (rows as List).isNotEmpty;
    } catch (error) {
      debugPrint(
        '[Supabase] No se pudo verificar auditoría de número invoice_id=$invoiceId: $error',
      );
      return false;
    }
  }

  Future<void> _upsertInvoiceWithSchemaFallback(
    Invoice invoice,
    Map<String, dynamic> initialMap,
  ) async {
    Map<String, dynamic> map = Map<String, dynamic>.from(initialMap);

    // Esquemas posibles detectados en proyectos antiguos:
    // - Campos en castellano (iva_porcentaje/irpf_importe/fecha_emision)
    // - Campos en ingles (iva_rate/irpf_amount/fecha)
    //
    // En vez de adivinar, reintentamos cambiando solo el campo que falte.
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        await _client!.from('invoices').upsert(map, onConflict: 'id');
        return;
      } on PostgrestException catch (e) {
        final missing = _extractMissingColumn(e);
        if (missing == null) rethrow;

        final updated = _applyInvoiceColumnFallback(invoice, map, missing);
        if (!updated) rethrow;
      }
    }

    // Si seguimos aqui, re-lanzar para que quede registrado en logs.
    await _client!.from('invoices').upsert(map, onConflict: 'id');
  }

  Future<void> _updateInvoiceWithSchemaFallback(
    Invoice invoice,
    Map<String, dynamic> initialMap,
  ) async {
    Map<String, dynamic> map = Map<String, dynamic>.from(initialMap);

    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        await _client!
            .from('invoices')
            .update(map)
            .eq('user_id', userId!)
            .eq('id', invoice.id);
        return;
      } on PostgrestException catch (e) {
        final missing = _extractMissingColumn(e);
        if (missing == null) rethrow;

        final updated = _applyInvoiceColumnFallback(invoice, map, missing);
        if (!updated) rethrow;
      }
    }

    await _client!
        .from('invoices')
        .update(map)
        .eq('user_id', userId!)
        .eq('id', invoice.id);
  }

  String? _extractMissingColumn(PostgrestException e) {
    final msg = e.message;
    final isMissingColumn =
        e.code == 'PGRST204' ||
        msg.toLowerCase().contains('could not find the') ||
        (msg.toLowerCase().contains('schema cache') &&
            msg.toLowerCase().contains('column'));
    if (!isMissingColumn) return null;

    final match = RegExp(
      r"Could not find the '([^']+)' column of",
    ).firstMatch(msg);
    return match?.group(1);
  }

  bool _applyInvoiceColumnFallback(
    Invoice invoice,
    Map<String, dynamic> map,
    String missingColumn,
  ) {
    switch (missingColumn) {
      case 'irpf_importe':
        map.remove('irpf_importe');
        map['irpf_amount'] = invoice.irpfAmount;
        return true;
      case 'irpf_amount':
        map.remove('irpf_amount');
        map['irpf_importe'] = invoice.irpfAmount;
        return true;
      case 'irpf_porcentaje':
        map.remove('irpf_porcentaje');
        map['irpf_rate'] = invoice.irpfRate;
        return true;
      case 'irpf_rate':
        map.remove('irpf_rate');
        map['irpf_porcentaje'] = invoice.irpfRate * 100;
        return true;
      case 'iva_importe':
        map.remove('iva_importe');
        map['iva_amount'] = invoice.ivaAmount;
        return true;
      case 'iva_amount':
        map.remove('iva_amount');
        map['iva_importe'] = invoice.ivaAmount;
        return true;
      case 'iva_porcentaje':
        map.remove('iva_porcentaje');
        map['iva_rate'] = invoice.ivaRate;
        return true;
      case 'iva_rate':
        map.remove('iva_rate');
        map['iva_porcentaje'] = invoice.ivaRate * 100;
        return true;
      case 'fecha_emision':
        map.remove('fecha_emision');
        map['fecha'] = invoice.fecha.toIso8601String().split('T').first;
        return true;
      case 'fecha':
        map.remove('fecha');
        map['fecha_emision'] = invoice.fecha.toIso8601String().split('T').first;
        return true;
      default:
        return false;
    }
  }

  Future<void> uploadAll({
    required List<Client> clients,
    required List<Gig> gigs,
    required List<Invoice> invoices,
  }) async {
    // Hay dependencia circular: gigs.invoice_id → invoices, invoices.gig_id → gigs
    // Solución: subir en 3 fases

    // Fase 1: Subir clientes
    await uploadClients(clients);

    // Fase 2: asegurar gigs sin tocar invoice_id existente.
    for (final gig in gigs) {
      final map = _gigToSupabase(gig);
      map.remove('invoice_id');
      await _client!.from('gigs').upsert(map, onConflict: 'id');
    }
    debugPrint(
      '[Supabase] Uploaded ${gigs.length} gigs (phase 1, preserving invoice_id)',
    );

    // Fase 3: Subir invoices (ahora gigs existen)
    await uploadInvoices(invoices);

    // Fase 4: Actualizar gigs con invoice_id correcto
    _validInvoiceIds = invoices.map((i) => i.id).toSet();
    for (final gig in gigs) {
      if (gig.invoiceId != null && _validInvoiceIds.contains(gig.invoiceId)) {
        await _client!
            .from('gigs')
            .update({'invoice_id': gig.invoiceId})
            .eq('id', gig.id);
      }
    }
    debugPrint('[Supabase] Updated gigs with invoice_id (phase 2)');
  }

  // ================== SETTINGS (Datos de facturación) ==================

  Future<void> uploadSettings(AppSettings settings) async {
    if (!isAuthenticated) return;

    if (_billingFieldsAreEmpty(settings)) {
      debugPrint('[Supabase] Skipping empty local settings upload');
      return;
    }

    final signature = settingsSyncSignature(settings);
    if (settings.cloudSettingsSignature == signature) {
      debugPrint('[Supabase] Settings unchanged, skipping upload');
      return;
    }

    // Subir logo si existe
    String? logoUrl;
    if (settings.logoPath.isNotEmpty) {
      final exists = File(settings.logoPath).existsSync();
      if (exists) {
        logoUrl = await uploadLogo(settings.logoPath);
      }
    }

    final map = {
      'user_id': userId,
      'emisor_nombre': settings.emisorNombre,
      'emisor_nif': settings.emisorNIF,
      'emisor_direccion': settings.emisorDireccion,
      'emisor_ciudad': settings.emisorCiudad,
      'emisor_provincia': settings.emisorProvincia,
      'emisor_codigo_postal': settings.emisorCodigoPostal,
      'emisor_email': settings.emisorEmail,
      'emisor_telefono': settings.emisorTelefono,
      'iban': settings.iban,
      'iva_default': settings.ivaDefault,
      if (logoUrl != null) 'logo_url': logoUrl,
    };

    debugPrint('[Supabase] Uploading settings: $map');
    await _client!.from('user_settings').upsert(map, onConflict: 'user_id');
    debugPrint('[Supabase] Uploaded settings');
  }

  String settingsSyncSignature(AppSettings settings) {
    final logoSignature = _logoFileSignature(settings.logoPath);
    return [
      settings.emisorNombre.trim(),
      settings.emisorNIF.trim(),
      settings.emisorDireccion.trim(),
      settings.emisorCiudad.trim(),
      settings.emisorProvincia.trim(),
      settings.emisorCodigoPostal.trim(),
      settings.emisorEmail.trim(),
      settings.emisorTelefono.trim(),
      settings.iban.trim(),
      settings.ivaDefault.toStringAsFixed(4),
      logoSignature,
    ].join('|');
  }

  bool _billingFieldsAreEmpty(AppSettings settings) {
    return settings.emisorNombre.trim().isEmpty &&
        settings.emisorNIF.trim().isEmpty &&
        settings.emisorDireccion.trim().isEmpty &&
        settings.emisorCiudad.trim().isEmpty &&
        settings.emisorProvincia.trim().isEmpty &&
        settings.emisorCodigoPostal.trim().isEmpty &&
        settings.emisorEmail.trim().isEmpty &&
        settings.emisorTelefono.trim().isEmpty &&
        settings.iban.trim().isEmpty;
  }

  Future<AppSettings?> downloadSettings({DateTime? changedAfter}) async {
    if (!isAuthenticated) return null;

    try {
      var query = _client!
          .from('user_settings')
          .select()
          .eq('user_id', userId!);
      if (changedAfter != null) {
        query = query.gt('updated_at', changedAfter.toUtc().toIso8601String());
      }
      final data = await query.maybeSingle();

      if (data == null) {
        debugPrint('[Supabase] No settings changes since=$changedAfter');
        return null;
      }

      // Descargar logo si existe en la nube
      String localLogoPath = '';
      final cloudLogoUrl = data['logo_url'] as String?;
      if (cloudLogoUrl != null && cloudLogoUrl.isNotEmpty) {
        localLogoPath = await downloadLogo(cloudLogoUrl) ?? '';
      }

      final settings = AppSettings(
        emisorNombre: data['emisor_nombre'] ?? '',
        emisorNIF: data['emisor_nif'] ?? '',
        emisorDireccion: data['emisor_direccion'] ?? '',
        emisorCiudad: data['emisor_ciudad'] ?? '',
        emisorProvincia: data['emisor_provincia'] ?? '',
        emisorCodigoPostal: data['emisor_codigo_postal'] ?? '',
        emisorEmail: data['emisor_email'] ?? '',
        emisorTelefono: data['emisor_telefono'] ?? '',
        iban: data['iban'] ?? '',
        ivaDefault: (data['iva_default'] as num?)?.toDouble() ?? 0.21,
        logoPath: localLogoPath,
      );
      debugPrint('[Supabase] Downloaded settings');
      return settings;
    } catch (e) {
      debugPrint('[Supabase] Download settings error: $e');
      return null;
    }
  }

  // ================== LOGO (Storage) ==================

  Future<String?> uploadLogo(String localPath) async {
    if (!isAuthenticated) return null;

    try {
      final file = File(localPath);
      if (!file.existsSync()) return null;

      final ext = p.extension(localPath);
      final fileName = '$userId/logo$ext';

      await _client!.storage
          .from('logos')
          .upload(fileName, file, fileOptions: const FileOptions(upsert: true));

      debugPrint('[Supabase] Uploaded logo: $fileName');
      return fileName;
    } catch (e) {
      debugPrint('[Supabase] Upload logo error: $e');
      return null;
    }
  }

  Future<String?> downloadLogo(String cloudPath) async {
    if (!isAuthenticated) return null;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final ext = p.extension(cloudPath);
      final localPath = '${dir.path}/logo$ext';
      final file = File(localPath);
      if (await file.exists()) {
        debugPrint('[Supabase] Logo already local: $localPath');
        return localPath;
      }

      final bytes = await _client!.storage.from('logos').download(cloudPath);
      await file.writeAsBytes(bytes);

      debugPrint('[Supabase] Downloaded logo to: $localPath');
      return localPath;
    } catch (e) {
      debugPrint('[Supabase] Download logo error: $e');
      return null;
    }
  }

  String _logoFileSignature(String path) {
    if (path.trim().isEmpty) return 'logo:none';
    try {
      final file = File(path);
      if (!file.existsSync()) return 'logo:missing:$path';
      final stat = file.statSync();
      return 'logo:$path:${stat.size}:${stat.modified.toUtc().toIso8601String()}';
    } catch (_) {
      return 'logo:unreadable:$path';
    }
  }

  // ================== DELETE (Local → Cloud) ==================

  Future<void> deleteGig(String id) async {
    if (!isAuthenticated) return;
    try {
      await softDeleteGig(id);
      debugPrint('[Supabase] Deleted gig $id from cloud');
    } catch (e) {
      debugPrint('[Supabase] Delete gig error: $e');
    }
  }

  Future<void> deleteClient(String id) async {
    if (!isAuthenticated) return;
    try {
      await _client!
          .from('clients')
          .delete()
          .eq('user_id', userId!)
          .eq('id', id);
      debugPrint('[Supabase] Deleted client $id from cloud');
    } catch (e) {
      debugPrint('[Supabase] Delete client error: $e');
    }
  }

  Future<void> deleteInvoice(String id) async {
    if (!isAuthenticated) return;
    try {
      await softDeleteInvoice(id);
      debugPrint('[Supabase] Deleted invoice $id from cloud');
    } catch (e) {
      debugPrint('[Supabase] Delete invoice error: $e');
    }
  }

  Future<void> softDeleteGig(String id, {DateTime? deletedAt}) async {
    if (!isAuthenticated) return;
    final at = (deletedAt ?? DateTime.now()).toUtc().toIso8601String();
    await _client!
        .from('gigs')
        .update({'deleted_at': at, 'updated_at': at})
        .eq('user_id', userId!)
        .eq('id', id);
    debugPrint('[Supabase] Soft-deleted gig $id');
  }

  Future<void> softDeleteInvoice(String id, {DateTime? deletedAt}) async {
    if (!isAuthenticated) return;
    final at = (deletedAt ?? DateTime.now()).toUtc().toIso8601String();
    await _client!
        .from('invoices')
        .update({'deleted_at': at, 'updated_at': at})
        .eq('user_id', userId!)
        .eq('id', id);
    debugPrint('[Supabase] Soft-deleted invoice $id');
  }

  Future<void> deleteGigsBatch({
    required Set<String> gigIds,
    required Set<String> invoiceIds,
  }) async {
    if (!isAuthenticated) return;
    if (gigIds.isEmpty && invoiceIds.isEmpty) return;

    final gigs = gigIds.toList();
    final invoices = invoiceIds.toList();
    final now = DateTime.now().toUtc().toIso8601String();

    try {
      if (invoices.isNotEmpty) {
        await _client!
            .from('invoices')
            .update({'deleted_at': now, 'updated_at': now})
            .eq('user_id', userId!)
            .inFilter('id', invoices);
      }
      if (gigs.isNotEmpty) {
        await _client!
            .from('gigs')
            .update({'deleted_at': now, 'updated_at': now})
            .eq('user_id', userId!)
            .inFilter('id', gigs);
      }
      debugPrint(
        '[Supabase] Deleted batch gigs=${gigs.length} invoices=${invoices.length}',
      );
    } catch (e) {
      debugPrint('[Supabase] Delete batch gigs error: $e');
      rethrow;
    }
  }

  /// Borra un registro de cualquier tabla por nombre (para pending deletions)
  Future<void> deleteByTable(String tableName, String recordId) async {
    if (!isAuthenticated) return;
    final now = DateTime.now().toUtc().toIso8601String();
    // Todas las tablas core usan soft-delete para que realtime/incremental
    // propaguen borrados de forma consistente entre dispositivos.
    if (tableName == 'clients' ||
        tableName == 'gigs' ||
        tableName == 'invoices' ||
        tableName == 'expenses' ||
        tableName == 'assets') {
      await _client!
          .from(tableName)
          .update({'deleted_at': now, 'updated_at': now})
          .eq('user_id', userId!)
          .eq('id', recordId);
    } else {
      await _client!
          .from(tableName)
          .delete()
          .eq('user_id', userId!)
          .eq('id', recordId);
    }
    debugPrint('[Supabase] Deleted $tableName/$recordId from cloud');
  }

  // ================== DOWNLOAD (Cloud → Local) ==================

  Future<List<Client>> downloadClients() async {
    if (!isAuthenticated) return [];

    final data = await _selectChangedRows(
      table: 'clients',
      changedAfter: null,
      includeDeletedAt: false,
    );
    final clients = data
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((row) => _isOwnedByCurrentUser(row, 'clients'))
        .map(_clientFromSupabase)
        .toList();
    debugPrint('[Supabase] Downloaded ${clients.length} clients');
    return clients;
  }

  Future<List<Client>> downloadClientsChangesSince(
    DateTime? changedAfter,
  ) async {
    if (!isAuthenticated) return [];
    final data = await _selectChangedRows(
      table: 'clients',
      changedAfter: changedAfter,
      includeDeletedAt: false,
    );
    final clients = data
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((row) => _isOwnedByCurrentUser(row, 'clients'))
        .map(_clientFromSupabase)
        .toList();
    debugPrint(
      '[Supabase] Downloaded clients changes=${clients.length} since=$changedAfter',
    );
    return clients;
  }

  Future<List<Gig>> downloadGigs({DateTime? changedAfter}) async {
    if (!isAuthenticated) return [];

    final data = await _selectChangedRows(
      table: 'gigs',
      changedAfter: changedAfter,
    );
    final gigs = data
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((row) => _isOwnedByCurrentUser(row, 'gigs'))
        .map(_gigFromSupabase)
        .toList();
    debugPrint('[Supabase] Downloaded ${gigs.length} gigs since=$changedAfter');
    return gigs;
  }

  Future<List<Invoice>> downloadInvoices({DateTime? changedAfter}) async {
    if (!isAuthenticated) return [];

    final data = await _selectChangedRows(
      table: 'invoices',
      changedAfter: changedAfter,
    );
    final invoices = data
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((row) => _isOwnedByCurrentUser(row, 'invoices'))
        .map((e) => _invoiceFromSupabase(e))
        .where((invoice) => invoice.numero > 0)
        .toList();
    debugPrint(
      '[Supabase] Downloaded ${invoices.length} invoices since=$changedAfter',
    );
    return invoices;
  }

  // ================== CONVERSIONES ==================

  Map<String, dynamic> _clientToSupabase(Client c) => {
    'id': c.id,
    'user_id': userId,
    'nombre': c.nombre,
    'alias': c.alias,
    // aliases se mantiene solo local hasta añadir columna en Supabase
    'cif_nif': c.cifNif,
    'direccion': c.direccion,
    'ciudad': c.ciudad,
    'provincia': c.provincia,
    'codigo_postal': c.codigoPostal,
    'email': c.email,
    'telefono': c.telefono,
    'whatsapp_phone': c.whatsappPhone,
    'created_at': c.createdAt.toUtc().toIso8601String(),
    'updated_at': c.updatedAt.toUtc().toIso8601String(),
  };

  Client _clientFromSupabase(Map<String, dynamic> m) => Client(
    id: m['id'],
    nombre: m['nombre'] ?? '',
    alias: m['alias'] ?? '',
    // aliases se mantiene solo local hasta añadir columna en Supabase
    cifNif: m['cif_nif'] ?? '',
    direccion: m['direccion'] ?? '',
    ciudad: m['ciudad'] ?? '',
    provincia: m['provincia'] ?? '',
    codigoPostal: m['codigo_postal'] ?? '',
    email: m['email'],
    telefono: m['telefono'],
    whatsappPhone: m['whatsapp_phone'],
    createdAt: DateTime.parse(m['created_at']),
    updatedAt: DateTime.parse(m['updated_at']),
  );

  Map<String, dynamic> _gigToSupabase(Gig g) => {
    'id': g.id,
    'user_id': userId,
    'fecha': g.fecha.toIso8601String().split('T').first,
    'client_id': g.clientId,
    'notas': g.notas,
    'cachet': g.cachet,
    'facturable': g.facturable,
    'status': g.status.dbValue,
    'invoice_id': g.invoiceId,
    'created_at': g.createdAt.toUtc().toIso8601String(),
    'updated_at': g.updatedAt.toUtc().toIso8601String(),
    if (g.deletedAt != null)
      'deleted_at': g.deletedAt!.toUtc().toIso8601String(),
  };

  Gig _gigFromSupabase(Map<String, dynamic> m) => Gig(
    id: m['id'],
    fecha: DateTime.parse(m['fecha']),
    clientId: m['client_id'] ?? '',
    notas: m['notas'],
    cachet: m['cachet'] != null ? (m['cachet'] as num).toDouble() : null,
    facturable: m['facturable'] ?? true,
    status: GigStatusExtension.fromDb(m['status'] ?? 'confirmado'),
    invoiceId: m['invoice_id'],
    createdAt: DateTime.parse(m['created_at']),
    updatedAt: DateTime.parse((m['updated_at'] ?? m['created_at']).toString()),
    deletedAt: m['deleted_at'] != null
        ? DateTime.parse(m['deleted_at'].toString())
        : null,
  );

  Map<String, dynamic> _invoiceToSupabaseEs(
    Invoice i, {
    bool includeNumber = true,
  }) => {
    'id': i.id,
    'user_id': userId,
    if (includeNumber) 'numero': i.numero.toString(),
    'fecha_emision': i.fecha.toIso8601String().split('T').first,
    'client_id': i.clientId,
    'gig_id': i.gigId,
    'items': i.items.map((e) => e.toMap()).toList(),
    'subtotal': i.subtotal,
    'iva_porcentaje': i.ivaRate * 100,
    'iva_importe': i.ivaAmount,
    'irpf_porcentaje': i.irpfRate * 100,
    'irpf_importe': i.irpfAmount,
    'total': i.total,
    'status': i.status.dbValue,
    'created_at': i.createdAt.toUtc().toIso8601String(),
    'updated_at': i.updatedAt.toUtc().toIso8601String(),
    'drive_file_id': i.driveFileId,
    'drive_file_url': i.driveFileUrl,
    'drive_synced_at': i.driveSyncedAt?.toUtc().toIso8601String(),
    if (i.deletedAt != null)
      'deleted_at': i.deletedAt!.toUtc().toIso8601String(),
  };

  Invoice _invoiceFromSupabase(Map<String, dynamic> m) {
    final itemsRaw = m['items'];
    List<InvoiceLineItem> items = [];
    if (itemsRaw is List) {
      items = itemsRaw
          .map((e) => InvoiceLineItem.fromMap(e as Map<String, dynamic>))
          .toList();
    } else if (itemsRaw is String) {
      final decoded = jsonDecode(itemsRaw) as List;
      items = decoded
          .map((e) => InvoiceLineItem.fromMap(e as Map<String, dynamic>))
          .toList();
    }

    final fechaEmisionRaw = m['fecha_emision'] ?? m['fecha'] ?? m['created_at'];
    final parsedFecha = DateTime.tryParse(fechaEmisionRaw?.toString() ?? '');
    final ivaRate = _readRate(
      porcentaje: m['iva_porcentaje'],
      rate: m['iva_rate'],
      defaultRate: 0.21,
    );
    final irpfRate = _readRate(
      porcentaje: m['irpf_porcentaje'],
      rate: m['irpf_rate'],
      defaultRate: 0.0,
    );

    return Invoice(
      id: m['id'],
      numero: int.tryParse(m['numero']?.toString() ?? '0') ?? 0,
      fecha: parsedFecha ?? DateTime.now(),
      clientId: m['client_id'] ?? '',
      gigId: m['gig_id'] ?? '',
      items: items,
      subtotal: (m['subtotal'] as num?)?.toDouble() ?? 0,
      ivaRate: ivaRate,
      ivaAmount:
          (m['iva_importe'] as num?)?.toDouble() ??
          (m['iva_amount'] as num?)?.toDouble() ??
          0,
      irpfRate: irpfRate,
      irpfAmount:
          (m['irpf_importe'] as num?)?.toDouble() ??
          (m['irpf_amount'] as num?)?.toDouble() ??
          0,
      total: (m['total'] as num?)?.toDouble() ?? 0,
      driveFileId: m['drive_file_id'] as String?,
      driveFileUrl: m['drive_file_url'] as String?,
      driveSyncedAt: m['drive_synced_at'] != null
          ? DateTime.tryParse(m['drive_synced_at'].toString())
          : null,
      status: InvoiceStatusExtension.fromDb(m['status'] ?? 'borrador'),
      createdAt: DateTime.parse(m['created_at']),
      updatedAt: DateTime.parse(
        (m['updated_at'] ?? m['created_at']).toString(),
      ),
      deletedAt: m['deleted_at'] != null
          ? DateTime.parse(m['deleted_at'].toString())
          : null,
    );
  }

  DateTime? _readPayloadDate(Map<String, dynamic> payload, String key) {
    final raw = payload[key];
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  double _readRate({
    required dynamic porcentaje,
    required dynamic rate,
    required double defaultRate,
  }) {
    // En algunos esquemas se guarda en porcentaje (21) y en otros como ratio (0.21).
    if (porcentaje is num) return porcentaje.toDouble() / 100;
    if (rate is num) return rate.toDouble();
    return defaultRate;
  }

  // ================== EXPENSES ==================

  Future<void> uploadExpenses(List<Expense> expenses) async {
    if (!isAuthenticated) return;
    for (final expense in expenses) {
      final cloudId = expense.cloudId!;
      await _client!
          .from('expenses')
          .upsert(_expenseToSupabase(expense, cloudId), onConflict: 'id');
    }
    debugPrint('[Supabase] Uploaded ${expenses.length} expenses');
  }

  Future<List<Expense>> downloadExpenses({DateTime? changedAfter}) async {
    if (!isAuthenticated) return [];
    final data = await _selectChangedRows(
      table: 'expenses',
      changedAfter: changedAfter,
      includeDeletedAt: false,
    );
    final result = data
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .where((row) => _isOwnedByCurrentUser(row, 'expenses'))
        .where((row) => row['deleted_at'] == null)
        .map(expenseFromCloudRow)
        .toList();
    debugPrint(
      '[Supabase] Downloaded ${result.length} expenses since=$changedAfter',
    );
    return result;
  }

  Future<List<Map<String, dynamic>>> downloadExpenseChangesRaw({
    DateTime? changedAfter,
  }) async {
    if (!isAuthenticated) return [];
    final data = await _selectChangedRows(
      table: 'expenses',
      changedAfter: changedAfter,
      includeDeletedAt: true,
    );
    return data
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .where((row) => _isOwnedByCurrentUser(row, 'expenses'))
        .toList();
  }

  Future<void> deleteExpense(String cloudId) async {
    if (!isAuthenticated) return;
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await _client!
          .from('expenses')
          .update({'deleted_at': now, 'updated_at': now})
          .eq('user_id', userId!)
          .eq('id', cloudId);
      debugPrint('[Supabase] Deleted expense $cloudId');
    } catch (e) {
      debugPrint('[Supabase] Delete expense error: $e');
    }
  }

  Map<String, dynamic> _expenseToSupabase(Expense e, String cloudId) => {
    'id': cloudId,
    'user_id': userId,
    'fecha': e.fecha.toIso8601String().split('T').first,
    'concepto': e.concepto,
    'proveedor': e.proveedor,
    'importe_base': e.importeBase,
    'iva_rate': e.ivaRate,
    'iva_amount': e.ivaAmount,
    'total': e.total,
    'categoria': e.categoria.dbValue,
    'es_deducible': e.esDeducible,
    'porcentaje_deduccion': e.porcentajeDeduccion,
    // No sincronizar rutas locales entre dispositivos.
    'documento_path': null,
    'notas': e.notas,
    'drive_file_id': e.driveFileId,
    'drive_file_url': e.driveFileUrl,
    'drive_synced_at': e.driveSyncedAt?.toUtc().toIso8601String(),
    'created_at': e.createdAt.toUtc().toIso8601String(),
  };

  Expense expenseFromCloudRow(Map<String, dynamic> m) => Expense(
    cloudId: m['id'] as String?,
    userId: m['user_id'] as String?,
    fecha: DateTime.parse(m['fecha'] as String),
    concepto: m['concepto'] as String,
    proveedor: m['proveedor'] as String?,
    importeBase: (m['importe_base'] as num).toDouble(),
    ivaRate: (m['iva_rate'] as num).toDouble(),
    ivaAmount: (m['iva_amount'] as num).toDouble(),
    total: (m['total'] as num).toDouble(),
    categoria: ExpenseCategoryExtension.fromDb(
      m['categoria'] as String? ?? 'otros',
    ),
    esDeducible: m['es_deducible'] as bool? ?? true,
    porcentajeDeduccion:
        (m['porcentaje_deduccion'] as num?)?.toDouble() ?? 100.0,
    driveFileId: m['drive_file_id'] as String?,
    driveFileUrl: m['drive_file_url'] as String?,
    driveSyncedAt: m['drive_synced_at'] != null
        ? DateTime.tryParse(m['drive_synced_at'].toString())
        : null,
    documentoPath: m['documento_path'] as String?,
    notas: m['notas'] as String?,
    synced: true,
    createdAt: DateTime.parse(m['created_at'] as String),
  );

  // ================== ASSETS ==================

  Future<void> uploadAssets(List<Asset> assets) async {
    if (!isAuthenticated) return;
    for (final asset in assets) {
      final cloudId = asset.cloudId!;
      await _client!
          .from('assets')
          .upsert(_assetToSupabase(asset, cloudId), onConflict: 'id');
    }
    debugPrint('[Supabase] Uploaded ${assets.length} assets');
  }

  Future<List<Asset>> downloadAssets({DateTime? changedAfter}) async {
    if (!isAuthenticated) return [];
    final data = await _selectChangedRows(
      table: 'assets',
      changedAfter: changedAfter,
      includeDeletedAt: false,
    );
    final result = data
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .where((row) => _isOwnedByCurrentUser(row, 'assets'))
        .where((row) => row['deleted_at'] == null)
        .map(assetFromCloudRow)
        .toList();
    debugPrint(
      '[Supabase] Downloaded ${result.length} assets since=$changedAfter',
    );
    return result;
  }

  Future<List<Map<String, dynamic>>> downloadAssetChangesRaw({
    DateTime? changedAfter,
  }) async {
    if (!isAuthenticated) return [];
    final data = await _selectChangedRows(
      table: 'assets',
      changedAfter: changedAfter,
      includeDeletedAt: true,
    );
    return data
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .where((row) => _isOwnedByCurrentUser(row, 'assets'))
        .toList();
  }

  Future<void> deleteAsset(String cloudId) async {
    if (!isAuthenticated) return;
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await _client!
          .from('assets')
          .update({'deleted_at': now, 'updated_at': now})
          .eq('user_id', userId!)
          .eq('id', cloudId);
      debugPrint('[Supabase] Deleted asset $cloudId');
    } catch (e) {
      debugPrint('[Supabase] Delete asset error: $e');
    }
  }

  Map<String, dynamic> _assetToSupabase(Asset a, String cloudId) => {
    'id': cloudId,
    'user_id': userId,
    'descripcion': a.descripcion,
    'fecha_compra': a.fechaCompra.toIso8601String().split('T').first,
    'importe_total': a.importeTotal,
    'importe_con_iva': a.importeConIva,
    'iva_rate': a.ivaRate,
    'iva_amount': a.ivaAmount,
    'valor_residual': a.valorResidual,
    'vida_util_anos': a.vidaUtilAnos,
    'metodo_amortizacion': a.metodoAmortizacion,
    'categoria': a.categoria.dbValue,
    // No sincronizar rutas locales entre dispositivos.
    'documento_path': null,
    'notas': a.notas,
    'drive_file_id': a.driveFileId,
    'drive_file_url': a.driveFileUrl,
    'drive_synced_at': a.driveSyncedAt?.toUtc().toIso8601String(),
    'activo': a.activo,
    'created_at': a.createdAt.toUtc().toIso8601String(),
  };

  Asset assetFromCloudRow(Map<String, dynamic> m) => Asset(
    cloudId: m['id'] as String?,
    userId: m['user_id'] as String?,
    descripcion: m['descripcion'] as String,
    fechaCompra: DateTime.parse(m['fecha_compra'] as String),
    importeTotal: (m['importe_total'] as num).toDouble(),
    importeConIva: (m['importe_con_iva'] as num? ?? 0).toDouble(),
    ivaRate: (m['iva_rate'] as num? ?? 21.0).toDouble(),
    ivaAmount: (m['iva_amount'] as num? ?? 0).toDouble(),
    valorResidual: (m['valor_residual'] as num? ?? 0).toDouble(),
    vidaUtilAnos: m['vida_util_anos'] as int,
    metodoAmortizacion: m['metodo_amortizacion'] as String? ?? 'lineal',
    categoria: AssetCategory.fromDb(m['categoria'] as String? ?? 'otros'),
    driveFileId: m['drive_file_id'] as String?,
    driveFileUrl: m['drive_file_url'] as String?,
    driveSyncedAt: m['drive_synced_at'] != null
        ? DateTime.tryParse(m['drive_synced_at'].toString())
        : null,
    documentoPath: m['documento_path'] as String?,
    notas: m['notas'] as String?,
    activo: m['activo'] as bool? ?? true,
    synced: true,
    createdAt: DateTime.parse(m['created_at'] as String),
  );

  Future<List<dynamic>> _selectChangedRows({
    required String table,
    required DateTime? changedAfter,
    bool includeDeletedAt = true,
  }) async {
    final uid = userId;
    if (uid == null) return const [];

    var query = _client!.from(table).select().eq('user_id', uid);
    if (changedAfter != null) {
      // Margen anti-desfase entre relojes de dispositivos (clock skew).
      // En la práctica hemos visto diferencias de varios minutos entre
      // equipos que pueden ocultar soft-deletes en incremental.
      final safeSince = changedAfter.toUtc().subtract(
        const Duration(minutes: 15),
      );
      final iso = safeSince.toIso8601String();
      if (includeDeletedAt) {
        try {
          query = query.or('updated_at.gt.$iso,deleted_at.gt.$iso');
          return query;
        } catch (e) {
          final msg = e.toString().toLowerCase();
          if (msg.contains('deleted_at') && msg.contains('does not exist')) {
            // Fallback defensivo si alguna tabla remota aún no tiene deleted_at.
            return _client!
                .from(table)
                .select()
                .eq('user_id', uid)
                .gt('updated_at', iso);
          }
          rethrow;
        }
      } else {
        query = query.gt('updated_at', iso);
      }
    }
    return query;
  }

  bool _isOwnedByCurrentUser(Map<String, dynamic> row, String table) {
    final uid = userId;
    if (uid == null) return false;
    final rowUserId = row['user_id']?.toString();
    if (rowUserId == null || rowUserId == uid) return true;
    debugPrint(
      '[SECURITY][CRITICAL] Fila bloqueada por user_id distinto. '
      'table=$table expected=$uid got=$rowUserId row_id=${row['id']}',
    );
    return false;
  }
}
