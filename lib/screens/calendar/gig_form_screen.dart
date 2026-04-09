import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/utils/date_formatter.dart';
import '../../models/gig.dart';
import '../../providers/gig_provider.dart';
import '../../providers/client_provider.dart';
import '../../providers/stats_provider.dart';
import '../../services/google_auth_service.dart';
import '../../services/google_calendar_service.dart';

class GigFormScreen extends ConsumerStatefulWidget {
  final String? gigId;
  const GigFormScreen({super.key, this.gigId});

  @override
  ConsumerState<GigFormScreen> createState() => _GigFormScreenState();
}

class _GigFormScreenState extends ConsumerState<GigFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _fecha;
  String? _clientId;
  final _cachetController = TextEditingController();
  final _notasController = TextEditingController();
  bool _facturable = true;
  bool _isLoading = false;
  Gig? _existingGig;

  @override
  void initState() {
    super.initState();
    _fecha = DateTime.now();
    if (widget.gigId != null) {
      _loadGig();
    }
  }

  Future<void> _loadGig() async {
    final gig = await ref.read(gigByIdProvider(widget.gigId!).future);
    if (gig != null && mounted) {
      setState(() {
        _existingGig = gig;
        _fecha = gig.fecha;
        _clientId = gig.clientId;
        _cachetController.text = gig.cachet?.toStringAsFixed(2) ?? '';
        _notasController.text = gig.notas ?? '';
        _facturable = gig.facturable;
      });
    }
  }

  @override
  void dispose() {
    _cachetController.dispose();
    _notasController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clientsAsync = ref.watch(clientsProvider);
    final isEditing = widget.gigId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? AppStrings.editarBolo : AppStrings.nuevoBolo),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Fecha
            Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_today, color: AppColors.primary),
                title: const Text(AppStrings.fecha),
                subtitle: Text(DateFormatter.display(_fecha)),
                onTap: _pickDate,
              ),
            ),
            const SizedBox(height: 12),

            // Cliente
            clientsAsync.when(
              data: (clients) => DropdownButtonFormField<String>(
                initialValue: _clientId,
                decoration: const InputDecoration(
                  labelText: AppStrings.cliente,
                  prefixIcon: Icon(Icons.person),
                ),
                items: clients.map((c) => DropdownMenuItem(
                  value: c.id,
                  child: Text(c.alias.isNotEmpty ? c.alias : c.nombre),
                )).toList(),
                onChanged: (v) => setState(() => _clientId = v),
                validator: (v) => v == null ? AppStrings.campoObligatorio : null,
              ),
              loading: () => const CircularProgressIndicator(),
              error: (_, __) => const Text('Error cargando clientes'),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => context.push('/client/new'),
                icon: const Icon(Icons.add, size: 18),
                label: const Text(AppStrings.nuevoCliente),
              ),
            ),
            const SizedBox(height: 12),

            // Caché
            TextFormField(
              controller: _cachetController,
              decoration: const InputDecoration(
                labelText: AppStrings.cachet,
                prefixIcon: Icon(Icons.euro),
                suffixText: '€',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.isEmpty) return AppStrings.campoObligatorio;
                if (double.tryParse(v.replaceAll(',', '.')) == null) {
                  return 'Introduce un número válido';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Notas
            TextFormField(
              controller: _notasController,
              decoration: const InputDecoration(
                labelText: AppStrings.notas,
                prefixIcon: Icon(Icons.notes),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),

            // Toggle facturable - MUY PROMINENTE
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _facturable
                    ? AppColors.accentGreen.withValues(alpha: 0.1)
                    : AppColors.accentPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _facturable
                      ? AppColors.accentGreen
                      : AppColors.accentPurple,
                  width: 2,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    AppStrings.facturable,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _facturable
                              ? AppColors.accentGreen
                              : AppColors.accentPurple,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // NO
                      GestureDetector(
                        onTap: () => setState(() => _facturable = false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 14),
                          decoration: BoxDecoration(
                            color: !_facturable
                                ? AppColors.accentPurple
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: AppColors.accentPurple,
                              width: 2,
                            ),
                          ),
                          child: Text(
                            AppStrings.no,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: !_facturable
                                  ? Colors.white
                                  : AppColors.accentPurple,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      // SÍ
                      GestureDetector(
                        onTap: () => setState(() => _facturable = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 14),
                          decoration: BoxDecoration(
                            color: _facturable
                                ? AppColors.accentGreen
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: AppColors.accentGreen,
                              width: 2,
                            ),
                          ),
                          child: Text(
                            AppStrings.si,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _facturable
                                  ? Colors.white
                                  : AppColors.accentGreen,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _facturable
                        ? 'Se generará factura con IVA'
                        : 'Se cobrará sin factura (solo en local)',
                    style: TextStyle(
                      fontSize: 12,
                      color: _facturable
                          ? AppColors.accentGreen
                          : AppColors.accentPurple,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Botón guardar
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _save,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save),
                label: Text(AppStrings.guardar),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('es', 'ES'),
    );
    if (date != null) {
      setState(() => _fecha = date);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final cachet =
          double.parse(_cachetController.text.replaceAll(',', '.'));
      final notas = _notasController.text.trim();
      Gig savedGig;

      if (_existingGig != null) {
        savedGig = _existingGig!.copyWith(
          fecha: _fecha,
          clientId: _clientId,
          cachet: cachet,
          notas: notas.isEmpty ? null : notas,
          facturable: _facturable,
        );
        await ref.read(gigsProvider.notifier).updateGig(savedGig);
      } else {
        savedGig = Gig(
          fecha: _fecha,
          clientId: _clientId!,
          cachet: cachet,
          notas: notas.isEmpty ? null : notas,
          facturable: _facturable,
        );
        await ref.read(gigsProvider.notifier).add(savedGig);
      }

      // Sincronizar con Google Calendar si está conectado
      final authState = ref.read(googleAuthProvider);
      if (authState.isSignedIn) {
        try {
          final client = await ref.read(clientByIdProvider(savedGig.clientId).future);
          await GoogleCalendarService().syncGig(
            gig: savedGig,
            clientName: client?.nombre ?? 'Cliente',
            cachet: savedGig.cachet,
          );
        } catch (_) {}
      }

      ref.invalidate(gigsProvider);
      ref.invalidate(recentGigsProvider);
      ref.invalidate(dashboardStatsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_existingGig != null
                ? AppStrings.boloActualizado
                : AppStrings.boloCreado),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
