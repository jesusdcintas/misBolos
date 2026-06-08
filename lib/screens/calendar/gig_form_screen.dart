import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/utils/date_formatter.dart';
import '../../widgets/common/animated_facturable_toggle.dart';
import '../../models/client.dart';
import '../../models/gig.dart';
import '../../providers/gig_provider.dart';
import '../../providers/client_provider.dart';
import '../../providers/stats_provider.dart';
import '../../services/google_auth_service.dart';
import '../../services/google_calendar_service.dart';
import 'client_picker_screen.dart';

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
                leading: const Icon(
                  Icons.calendar_today,
                  color: AppColors.primary,
                ),
                title: const Text(AppStrings.fecha),
                subtitle: Text(DateFormatter.display(_fecha)),
                onTap: _pickDate,
              ),
            ),
            const SizedBox(height: 12),

            // Cliente
            clientsAsync.when(
              data: (clients) {
                Client? selectedClient;
                if (_clientId != null) {
                  for (final client in clients) {
                    if (client.id == _clientId) {
                      selectedClient = client;
                      break;
                    }
                  }
                }
                final selectedName = selectedClient == null
                    ? null
                    : (selectedClient.alias.isNotEmpty
                          ? selectedClient.alias
                          : selectedClient.nombre);
                final selectedDetails = selectedClient == null
                    ? null
                    : [
                        if ((selectedClient.telefono ?? '').trim().isNotEmpty)
                          selectedClient.telefono!.trim(),
                        if ((selectedClient.email ?? '').trim().isNotEmpty)
                          selectedClient.email!.trim(),
                      ].join(' · ');

                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _isLoading
                      ? null
                      : () async {
                          final picked = await showClientPicker(
                            context,
                            ref,
                            selectedClientId: _clientId,
                          );
                          if (picked == null || !mounted) return;
                          setState(() => _clientId = picked.id);
                        },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: AppStrings.cliente,
                      prefixIcon: const Icon(Icons.person),
                      suffixIcon: const Icon(Icons.chevron_right),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selectedName ?? 'Seleccionar cliente',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: selectedName == null
                                ? AppColors.textSecondary
                                : AppColors.textPrimary,
                          ),
                        ),
                        if (selectedDetails != null &&
                            selectedDetails.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            selectedDetails,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => const Text('Error cargando clientes'),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  await context.push('/client/new');
                  if (!mounted) return;
                  ref.invalidate(clientsProvider);
                },
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
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
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
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 400),
                        style: Theme.of(context).textTheme.titleLarge!.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _facturable
                              ? AppColors.accentGreen
                              : AppColors.accentPurple,
                        ),
                        child: Text(AppStrings.facturable),
                      ),
                      const SizedBox(width: 16),
                      AnimatedFacturableToggle(
                        value: _facturable,
                        onChanged: (v) => setState(() => _facturable = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      _facturable
                          ? 'Se generará factura con IVA'
                          : 'Se cobrará sin factura (solo en local)',
                      key: ValueKey(_facturable),
                      style: TextStyle(
                        fontSize: 12,
                        color: _facturable
                            ? AppColors.accentGreen
                            : AppColors.accentPurple,
                      ),
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
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
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
    if (_clientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un cliente para continuar')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final cachet = double.parse(_cachetController.text.replaceAll(',', '.'));
      final notas = _notasController.text.trim();
      Gig savedGig;

      if (_existingGig != null) {
        GigStatus status = _existingGig!.status;
        if (_existingGig!.facturable != _facturable) {
          // Adaptar estado al cambiar entre facturable y privado.
          if (_facturable) {
            if (status == GigStatus.confirmadoB ||
                status == GigStatus.realizadoB) {
              status = GigStatus.confirmado;
            } else if (status == GigStatus.cobradoB) {
              status = GigStatus.cobrado;
            }
          } else {
            if (status == GigStatus.confirmado || status == GigStatus.facturado) {
              status = GigStatus.confirmadoB;
            } else if (status == GigStatus.cobrado) {
              status = GigStatus.cobradoB;
            }
          }
        }
        savedGig = _existingGig!.copyWith(
          fecha: _fecha,
          clientId: _clientId,
          cachet: cachet,
          notas: notas.isEmpty ? null : notas,
          facturable: _facturable,
          status: status,
        );
        await ref.read(gigsProvider.notifier).updateGig(savedGig);
      } else {
        savedGig = Gig(
          fecha: _fecha,
          clientId: _clientId!,
          cachet: cachet,
          notas: notas.isEmpty ? null : notas,
          facturable: _facturable,
          status: _facturable ? GigStatus.confirmado : GigStatus.confirmadoB,
        );
        await ref.read(gigsProvider.notifier).add(savedGig);
      }

      // Sincronizar con Google Calendar si está conectado
      final authState = ref.read(googleAuthProvider);
      if (authState.isSignedIn) {
        try {
          final client = await ref.read(
            clientByIdProvider(savedGig.clientId).future,
          );
          await GoogleCalendarService().syncGig(
            gig: savedGig,
            clientName: client?.displayName ?? 'Cliente',
            cachet: savedGig.cachet,
          );
        } catch (_) {}
      }

      ref.invalidate(gigsProvider);
      ref.invalidate(gigByIdProvider(savedGig.id));
      ref.invalidate(recentGigsProvider);
      ref.invalidate(dashboardStatsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _existingGig != null
                  ? AppStrings.boloActualizado
                  : AppStrings.boloCreado,
            ),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
