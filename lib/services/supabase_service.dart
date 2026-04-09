import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_settings.dart';
import '../models/client.dart';
import '../models/gig.dart';
import '../models/invoice.dart';

class SupabaseService {
  static final SupabaseService instance = SupabaseService._();
  SupabaseService._();

  SupabaseClient? _client;
  bool _initialized = false;

  bool get isInitialized => _initialized && _client != null;
  bool get isAuthenticated => _client?.auth.currentUser != null;
  String? get userId => _client?.auth.currentUser?.id;
  String? get userEmail => _client?.auth.currentUser?.email;
  
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
    _client?.auth.onAuthStateChange.listen((data) {
      debugPrint('[Supabase] Auth state changed: ${data.event} - ${data.session?.user.email}');
    });
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

  Future<void> uploadInvoices(List<Invoice> invoices) async {
    if (!isAuthenticated) return;
    
    for (final invoice in invoices) {
      final map = _invoiceToSupabase(invoice);
      // Eliminar factura en la nube con mismo numero pero distinto id (renumeración)
      await _client!.from('invoices')
          .delete()
          .eq('user_id', userId!)
          .eq('numero', invoice.numero.toString())
          .neq('id', invoice.id);
      await _client!.from('invoices').upsert(map, onConflict: 'id');
    }
    debugPrint('[Supabase] Uploaded ${invoices.length} invoices');
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
    
    // Fase 2: Subir gigs SIN invoice_id (para que invoices pueda referenciarlos)
    for (final gig in gigs) {
      final map = _gigToSupabase(gig);
      map['invoice_id'] = null; // Temporalmente sin invoice
      await _client!.from('gigs').upsert(map, onConflict: 'id');
    }
    debugPrint('[Supabase] Uploaded ${gigs.length} gigs (phase 1, without invoice_id)');
    
    // Fase 3: Subir invoices (ahora gigs existen)
    await uploadInvoices(invoices);
    
    // Fase 4: Actualizar gigs con invoice_id correcto
    _validInvoiceIds = invoices.map((i) => i.id).toSet();
    for (final gig in gigs) {
      if (gig.invoiceId != null && _validInvoiceIds.contains(gig.invoiceId)) {
        await _client!.from('gigs').update({'invoice_id': gig.invoiceId}).eq('id', gig.id);
      }
    }
    debugPrint('[Supabase] Updated gigs with invoice_id (phase 2)');
  }

  // ================== SETTINGS (Datos de facturación) ==================

  Future<void> uploadSettings(AppSettings settings) async {
    if (!isAuthenticated) return;
    
    // Subir logo si existe
    String? logoUrl;
    debugPrint('[Supabase] Logo path: "${settings.logoPath}"');
    if (settings.logoPath.isNotEmpty) {
      final exists = File(settings.logoPath).existsSync();
      debugPrint('[Supabase] Logo file exists: $exists');
      if (exists) {
        logoUrl = await uploadLogo(settings.logoPath);
        debugPrint('[Supabase] Logo uploaded: $logoUrl');
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

  Future<AppSettings?> downloadSettings() async {
    if (!isAuthenticated) return null;
    
    try {
      final data = await _client!
          .from('user_settings')
          .select()
          .eq('user_id', userId!)
          .maybeSingle();
      
      if (data == null) {
        debugPrint('[Supabase] No settings found');
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
      
      await _client!.storage.from('logos').upload(
        fileName,
        file,
        fileOptions: const FileOptions(upsert: true),
      );
      
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
      final bytes = await _client!.storage.from('logos').download(cloudPath);
      
      final dir = await getApplicationDocumentsDirectory();
      final ext = p.extension(cloudPath);
      final localPath = '${dir.path}/logo$ext';
      
      final file = File(localPath);
      await file.writeAsBytes(bytes);
      
      debugPrint('[Supabase] Downloaded logo to: $localPath');
      return localPath;
    } catch (e) {
      debugPrint('[Supabase] Download logo error: $e');
      return null;
    }
  }

  // ================== DELETE (Local → Cloud) ==================

  Future<void> deleteGig(String id) async {
    if (!isAuthenticated) return;
    try {
      await _client!.from('gigs').delete().eq('id', id);
      debugPrint('[Supabase] Deleted gig $id from cloud');
    } catch (e) {
      debugPrint('[Supabase] Delete gig error: $e');
    }
  }

  Future<void> deleteClient(String id) async {
    if (!isAuthenticated) return;
    try {
      await _client!.from('clients').delete().eq('id', id);
      debugPrint('[Supabase] Deleted client $id from cloud');
    } catch (e) {
      debugPrint('[Supabase] Delete client error: $e');
    }
  }

  Future<void> deleteInvoice(String id) async {
    if (!isAuthenticated) return;
    try {
      await _client!.from('invoices').delete().eq('id', id);
      debugPrint('[Supabase] Deleted invoice $id from cloud');
    } catch (e) {
      debugPrint('[Supabase] Delete invoice error: $e');
    }
  }

  /// Borra un registro de cualquier tabla por nombre (para pending deletions)
  Future<void> deleteByTable(String tableName, String recordId) async {
    if (!isAuthenticated) return;
    await _client!.from(tableName).delete().eq('id', recordId);
    debugPrint('[Supabase] Deleted $tableName/$recordId from cloud');
  }

  // ================== DOWNLOAD (Cloud → Local) ==================

  Future<List<Client>> downloadClients() async {
    if (!isAuthenticated) return [];
    
    final data = await _client!.from('clients').select();
    final clients = (data as List).map((e) => _clientFromSupabase(e)).toList();
    debugPrint('[Supabase] Downloaded ${clients.length} clients');
    return clients;
  }

  Future<List<Gig>> downloadGigs() async {
    if (!isAuthenticated) return [];
    
    final data = await _client!.from('gigs').select();
    final gigs = (data as List).map((e) => _gigFromSupabase(e)).toList();
    debugPrint('[Supabase] Downloaded ${gigs.length} gigs');
    return gigs;
  }

  Future<List<Invoice>> downloadInvoices() async {
    if (!isAuthenticated) return [];
    
    final data = await _client!.from('invoices').select();
    final invoices = (data as List).map((e) => _invoiceFromSupabase(e)).toList();
    debugPrint('[Supabase] Downloaded ${invoices.length} invoices');
    return invoices;
  }

  // ================== CONVERSIONES ==================

  Map<String, dynamic> _clientToSupabase(Client c) => {
    'id': c.id,
    'user_id': userId,
    'nombre': c.nombre,
    'alias': c.alias,
    'cif_nif': c.cifNif,
    'direccion': c.direccion,
    'ciudad': c.ciudad,
    'provincia': c.provincia,
    'codigo_postal': c.codigoPostal,
    'email': c.email,
    'telefono': c.telefono,
    'created_at': c.createdAt.toUtc().toIso8601String(),
    'updated_at': c.updatedAt.toUtc().toIso8601String(),
  };

  Client _clientFromSupabase(Map<String, dynamic> m) => Client(
    id: m['id'],
    nombre: m['nombre'] ?? '',
    alias: m['alias'] ?? '',
    cifNif: m['cif_nif'] ?? '',
    direccion: m['direccion'] ?? '',
    ciudad: m['ciudad'] ?? '',
    provincia: m['provincia'] ?? '',
    codigoPostal: m['codigo_postal'] ?? '',
    email: m['email'],
    telefono: m['telefono'],
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
  };

  Gig _gigFromSupabase(Map<String, dynamic> m) => Gig(
    id: m['id'],
    fecha: DateTime.parse(m['fecha']),
    clientId: m['client_id'] ?? '',
    notas: m['notas'],
    cachet: m['cachet'] != null ? (m['cachet'] as num).toDouble() : null,
    facturable: m['facturable'] ?? true,
    status: GigStatusExtension.fromDb(m['status'] ?? 'pendiente'),
    invoiceId: m['invoice_id'],
    createdAt: DateTime.parse(m['created_at']),
  );

  Map<String, dynamic> _invoiceToSupabase(Invoice i) => {
    'id': i.id,
    'user_id': userId,
    'numero': i.numero.toString(),
    'fecha_emision': i.fecha.toIso8601String().split('T').first,
    'client_id': i.clientId,
    'gig_id': i.gigId,
    'items': i.items.map((e) => e.toMap()).toList(),
    'subtotal': i.subtotal,
    'iva_porcentaje': i.ivaRate * 100,
    'iva_importe': i.ivaAmount,
    'total': i.total,
    'status': i.status.dbValue,
    'created_at': i.createdAt.toUtc().toIso8601String(),
  };

  Invoice _invoiceFromSupabase(Map<String, dynamic> m) {
    final itemsRaw = m['items'];
    List<InvoiceLineItem> items = [];
    if (itemsRaw is List) {
      items = itemsRaw.map((e) => InvoiceLineItem.fromMap(e as Map<String, dynamic>)).toList();
    } else if (itemsRaw is String) {
      final decoded = jsonDecode(itemsRaw) as List;
      items = decoded.map((e) => InvoiceLineItem.fromMap(e as Map<String, dynamic>)).toList();
    }

    return Invoice(
      id: m['id'],
      numero: int.tryParse(m['numero']?.toString() ?? '0') ?? 0,
      fecha: DateTime.parse(m['fecha_emision']),
      clientId: m['client_id'] ?? '',
      gigId: m['gig_id'] ?? '',
      items: items,
      subtotal: (m['subtotal'] as num?)?.toDouble() ?? 0,
      ivaRate: ((m['iva_porcentaje'] as num?)?.toDouble() ?? 21) / 100,
      ivaAmount: (m['iva_importe'] as num?)?.toDouble() ?? 0,
      total: (m['total'] as num?)?.toDouble() ?? 0,
      status: InvoiceStatusExtension.fromDb(m['status'] ?? 'borrador'),
      createdAt: DateTime.parse(m['created_at']),
    );
  }
}
