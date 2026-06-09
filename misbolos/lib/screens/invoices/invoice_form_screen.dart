import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/drive_document_sync_service.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/invoice.dart';
import '../../models/client.dart';
import '../../models/gig.dart';
import '../../models/app_settings.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/client_provider.dart';
import '../../providers/gig_provider.dart';
import '../../providers/settings_provider.dart';

class InvoiceFormScreen extends ConsumerStatefulWidget {
  final String? invoiceId;
  final String? gigId;

  const InvoiceFormScreen({super.key, this.invoiceId, this.gigId});

  @override
  ConsumerState<InvoiceFormScreen> createState() => _InvoiceFormScreenState();
}

class _InvoiceFormScreenState extends ConsumerState<InvoiceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isSaving = false;

  Invoice? _existingInvoice;
  Gig? _gig;
  Client? _client;
  AppSettings? _settings;

  List<_LineItemState> _items = [];
  double _ivaRate = 0.21;
  double _irpfRate = 0.0;
  bool _applyIrpf = false;
  DateTime _fecha = DateTime.now();

  static const List<double> _irpfOptions = [0.0, 0.07, 0.15, 0.19];

  DateTime _asDateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final settings = await ref.read(settingsProvider.future);
      _settings = settings;
      _ivaRate = settings.ivaDefault;
      _irpfRate = settings.irpfDefault;
      _applyIrpf = settings.irpfDefault > 0;

      if (widget.invoiceId != null) {
        // Editando factura existente
        final invoice = await ref.read(
          invoiceByIdProvider(widget.invoiceId!).future,
        );
        if (invoice != null) {
          _existingInvoice = invoice;
          _gig = await ref.read(gigByIdProvider(invoice.gigId).future);
          _client = await ref.read(clientByIdProvider(invoice.clientId).future);
          _ivaRate = invoice.ivaRate;
          _irpfRate = invoice.irpfRate;
          _applyIrpf = invoice.irpfRate > 0;
          _fecha = invoice.fecha;
          _items = invoice.items
              .map(
                (item) => _LineItemState(
                  cantidad: item.cantidad,
                  descripcion: item.descripcion,
                  precioUnitario: item.precioUnitario,
                ),
              )
              .toList();
        }
      } else if (widget.gigId != null) {
        // Creando nueva factura desde gig o editando existente
        _gig = await ref.read(gigByIdProvider(widget.gigId!).future);
        if (_gig != null) {
          _client = await ref.read(clientByIdProvider(_gig!.clientId).future);

          // Verificar si ya existe una factura para este gig
          if (_gig!.invoiceId != null) {
            final existingInvoice = await ref.read(
              invoiceByIdProvider(_gig!.invoiceId!).future,
            );
            if (existingInvoice != null) {
              _existingInvoice = existingInvoice;
              _ivaRate = existingInvoice.ivaRate;
              _irpfRate = existingInvoice.irpfRate;
              _applyIrpf = existingInvoice.irpfRate > 0;
              _fecha = existingInvoice.fecha;
              _items = existingInvoice.items
                  .map(
                    (item) => _LineItemState(
                      cantidad: item.cantidad,
                      descripcion: item.descripcion,
                      precioUnitario: item.precioUnitario,
                    ),
                  )
                  .toList();
            }
          }
          _existingInvoice ??= await ref.read(
            invoiceByGigProvider(_gig!.id).future,
          );
          if (_existingInvoice != null) {
            final existingInvoice = _existingInvoice!;
            _ivaRate = existingInvoice.ivaRate;
            _irpfRate = existingInvoice.irpfRate;
            _applyIrpf = existingInvoice.irpfRate > 0;
            _fecha = existingInvoice.fecha;
            _items = existingInvoice.items
                .map(
                  (item) => _LineItemState(
                    cantidad: item.cantidad,
                    descripcion: item.descripcion,
                    precioUnitario: item.precioUnitario,
                  ),
                )
                .toList();
          }

          // Si no hay factura existente, crear items por defecto
          if (_existingInvoice == null) {
            _fecha = _asDateOnly(_gig!.fecha);
            _items = [
              _LineItemState(
                cantidad: 1,
                descripcion: _gig!.notas?.isNotEmpty == true
                    ? _gig!.notas!.toUpperCase()
                    : 'DJ SET',
                precioUnitario: _gig!.cachet ?? 0,
              ),
            ];
          }
        }
      }

      if (_items.isEmpty) {
        _items = [
          _LineItemState(cantidad: 1, descripcion: 'DJ SET', precioUnitario: 0),
        ];
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  double get _subtotal => _items.fold(0, (sum, item) => sum + item.total);
  double get _ivaAmount => _subtotal * _ivaRate;
  double get _irpfAmount => _applyIrpf ? _subtotal * _irpfRate : 0;
  double get _total => _subtotal + _ivaAmount - _irpfAmount;

  @override
  Widget build(BuildContext context) {
    final isEditing = _existingInvoice != null;
    final isLocked = _existingInvoice?.isFiscallyLocked == true;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Editar Factura' : 'Nueva Factura'),
        actions: [
          if (!_isLoading && !_isSaving && !isLocked)
            IconButton(
              onPressed: _save,
              icon: const Icon(Icons.check),
              tooltip: 'Guardar factura',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : isLocked
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 42),
                    const SizedBox(height: 12),
                    Text(
                      'Factura bloqueada por modo fiscal estricto',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Para corregirla, crea una factura rectificativa desde el detalle de la factura.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Info del emisor y cliente
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_settings != null)
                        Expanded(child: _buildEmisorCard()),
                      const SizedBox(width: 12),
                      if (_client != null) Expanded(child: _buildClientCard()),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Fecha de factura
                  _buildFechaSelector(),
                  const SizedBox(height: 16),

                  // Líneas de factura
                  _buildSectionTitle('Líneas de factura'),
                  const SizedBox(height: 8),
                  ..._buildLineItems(),
                  const SizedBox(height: 8),
                  _buildAddLineButton(),
                  const SizedBox(height: 24),

                  // Impuestos y retención
                  _buildSectionTitle('Impuestos'),
                  const SizedBox(height: 8),
                  _buildIvaSelector(),
                  const SizedBox(height: 16),
                  _buildIrpfSection(),
                  const SizedBox(height: 24),

                  // Resumen de totales
                  _buildTotalsCard(),
                  const SizedBox(height: 24),

                  // Botón de guardar
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save),
                      label: Text(
                        _isSaving
                            ? 'Guardando...'
                            : (_existingInvoice != null
                                  ? 'Guardar cambios'
                                  : 'Crear factura'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: AppColors.primary,
      ),
    );
  }

  Widget _buildFechaSelector() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.calendar_today, color: AppColors.primary),
        title: const Text('Fecha de factura'),
        subtitle: Text(
          '${_fecha.day.toString().padLeft(2, '0')}/${_fecha.month.toString().padLeft(2, '0')}/${_fecha.year}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        trailing: const Icon(Icons.edit, size: 20),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: _fecha,
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
            locale: const Locale('es', 'ES'),
          );
          if (picked != null) {
            setState(() => _fecha = picked);
          }
        },
      ),
    );
  }

  Widget _buildEmisorCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'EMISOR',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _settings!.emisorNombre,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            if (_settings!.emisorNIF.isNotEmpty) Text(_settings!.emisorNIF),
            if (_settings!.emisorDireccion.isNotEmpty)
              Text(_settings!.emisorDireccion),
            if (_settings!.emisorCiudad.isNotEmpty ||
                _settings!.emisorProvincia.isNotEmpty ||
                _settings!.emisorCodigoPostal.isNotEmpty)
              Text(
                [
                  _settings!.emisorCiudad,
                  if (_settings!.emisorProvincia.isNotEmpty)
                    _settings!.emisorProvincia,
                  if (_settings!.emisorCodigoPostal.isNotEmpty)
                    _settings!.emisorCodigoPostal,
                ].where((s) => s.isNotEmpty).join(', '),
              ),
            if (_settings!.emisorEmail.isNotEmpty)
              Text(
                _settings!.emisorEmail,
                style: const TextStyle(color: Colors.blue),
              ),
            if (_settings!.emisorTelefono.isNotEmpty)
              Text(_settings!.emisorTelefono),
          ],
        ),
      ),
    );
  }

  Widget _buildClientCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'FACTURAR A',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _client!.nombre,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            if (_client!.cifNif.isNotEmpty) Text(_client!.cifNif),
            if (_client!.direccion.isNotEmpty) Text(_client!.direccion),
            if (_client!.ciudad.isNotEmpty ||
                _client!.codigoPostal.isNotEmpty ||
                _client!.provincia.isNotEmpty)
              Text(
                [
                  _client!.ciudad,
                  if (_client!.provincia.isNotEmpty) _client!.provincia,
                  if (_client!.codigoPostal.isNotEmpty) _client!.codigoPostal,
                ].where((s) => s.isNotEmpty).join(', '),
              ),
            if (_client!.email != null && _client!.email!.isNotEmpty)
              Text(_client!.email!, style: const TextStyle(color: Colors.blue)),
            if (_client!.telefono != null && _client!.telefono!.isNotEmpty)
              Text(_client!.telefono!),
            if (_client!.whatsappPhone != null &&
                _client!.whatsappPhone!.isNotEmpty)
              Text('WhatsApp: ${_client!.whatsappPhone!}'),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildLineItems() {
    return List.generate(_items.length, (index) {
      final item = _items[index];
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Línea ${index + 1}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (_items.length > 1)
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: AppColors.accentRed,
                      ),
                      onPressed: () => _removeItem(index),
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: item.descripcion,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() => item.descripcion = value);
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Requerido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: item.cantidad.toString(),
                      decoration: const InputDecoration(
                        labelText: 'Cantidad',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (value) {
                        setState(() {
                          item.cantidad = int.tryParse(value) ?? 1;
                        });
                      },
                      validator: (value) {
                        if (value == null ||
                            value.isEmpty ||
                            int.tryParse(value) == null ||
                            int.parse(value) < 1) {
                          return 'Min 1';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      initialValue: item.precioUnitario.toStringAsFixed(2),
                      decoration: const InputDecoration(
                        labelText: 'Precio unitario (€)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (value) {
                        setState(() {
                          item.precioUnitario =
                              double.tryParse(value.replaceAll(',', '.')) ?? 0;
                        });
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Requerido';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Total línea: ${CurrencyFormatter.format(item.total)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildAddLineButton() {
    return OutlinedButton.icon(
      onPressed: _addItem,
      icon: const Icon(Icons.add),
      label: const Text('Añadir línea'),
    );
  }

  void _addItem() {
    setState(() {
      _items.add(
        _LineItemState(cantidad: 1, descripcion: '', precioUnitario: 0),
      );
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
  }

  Widget _buildIvaSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Text('IVA:', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(width: 16),
            Expanded(
              child: DropdownButtonFormField<double>(
                initialValue: _ivaRate,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 0.0, child: Text('0%')),
                  DropdownMenuItem(value: 0.04, child: Text('4%')),
                  DropdownMenuItem(value: 0.10, child: Text('10%')),
                  DropdownMenuItem(value: 0.21, child: Text('21%')),
                ],
                onChanged: (value) {
                  setState(() => _ivaRate = value ?? 0.21);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIrpfSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Retención IRPF',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                Switch(
                  value: _applyIrpf,
                  activeTrackColor: AppColors.primary,
                  onChanged: (value) {
                    setState(() {
                      _applyIrpf = value;
                      if (!value) _irpfRate = 0.0;
                      if (value && _irpfRate == 0) {
                        _irpfRate = _settings?.irpfDefault ?? 0.15;
                      }
                    });
                  },
                ),
              ],
            ),
            if (_applyIrpf) ...[
              const SizedBox(height: 12),
              const Text(
                'Selecciona el porcentaje de retención:',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _irpfOptions.where((r) => r > 0).map((rate) {
                  final isSelected = _irpfRate == rate;
                  return ChoiceChip(
                    label: Text('${(rate * 100).toInt()}%'),
                    selected: isSelected,
                    selectedColor: AppColors.primary.withValues(alpha: 0.2),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _irpfRate = rate);
                      }
                    },
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTotalsCard() {
    return Card(
      color: AppColors.primary.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTotalRow('Subtotal', _subtotal),
            const SizedBox(height: 8),
            _buildTotalRow(
              'IVA (${(_ivaRate * 100).toStringAsFixed(0)}%)',
              _ivaAmount,
            ),
            if (_applyIrpf && _irpfRate > 0) ...[
              const SizedBox(height: 8),
              _buildTotalRow(
                'Retención IRPF (${(_irpfRate * 100).toStringAsFixed(0)}%)',
                -_irpfAmount,
                isNegative: true,
              ),
            ],
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'TOTAL',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  CurrencyFormatter.format(_total),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalRow(
    String label,
    double amount, {
    bool isNegative = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 14)),
        Text(
          isNegative
              ? '-${CurrencyFormatter.format(amount.abs())}'
              : CurrencyFormatter.format(amount),
          style: TextStyle(
            fontSize: 14,
            color: isNegative ? AppColors.accentRed : null,
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_gig == null || _client == null) return;
    if (_existingInvoice?.isFiscallyLocked == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Factura bloqueada por modo fiscal estricto'),
          ),
        );
      }
      return;
    }

    setState(() => _isSaving = true);

    try {
      final items = _items
          .map(
            (item) => InvoiceLineItem(
              cantidad: item.cantidad,
              descripcion: item.descripcion,
              precioUnitario: item.precioUnitario,
            ),
          )
          .toList();

      final subtotal = _subtotal;
      final ivaAmount = _ivaAmount;
      final irpfAmount = _applyIrpf ? _irpfAmount : 0.0;
      final total = _total;
      final irpfRate = _applyIrpf ? _irpfRate : 0.0;

      if (_existingInvoice != null) {
        // Actualizar factura existente
        final updatedInvoice = _existingInvoice!.copyWith(
          fecha: _fecha,
          items: items,
          subtotal: subtotal,
          ivaRate: _ivaRate,
          ivaAmount: ivaAmount,
          irpfRate: irpfRate,
          irpfAmount: irpfAmount,
          total: total,
        );
        await ref.read(invoicesProvider.notifier).updateInvoice(updatedInvoice);
        await _tryAutoSyncInvoiceToDrive(updatedInvoice.id);
      } else {
        // Crear nueva factura
        final nextNum = await ref.read(
          nextInvoiceNumberProvider(_fecha.year).future,
        );
        final invoiceDate = _gig != null ? _asDateOnly(_gig!.fecha) : _fecha;
        final invoice = Invoice(
          numero: nextNum,
          fecha: invoiceDate,
          clientId: _client!.id,
          gigId: _gig!.id,
          items: items,
          subtotal: subtotal,
          ivaRate: _ivaRate,
          ivaAmount: ivaAmount,
          irpfRate: irpfRate,
          irpfAmount: irpfAmount,
          total: total,
        );
        await ref.read(invoicesProvider.notifier).addAndLinkToGig(invoice);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Factura guardada. Pendiente de subir a Drive.'),
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
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _tryAutoSyncInvoiceToDrive(String invoiceId) async {
    try {
      await DriveDocumentSyncService.instance.enqueuePendingUpload(
        entityType: 'invoice',
        entityId: invoiceId,
        targetFolderType: 'FACTURAS',
        documentType: 'invoice_pdf',
        mimeType: 'application/pdf',
        logicalPath: 'FACTURAS/$invoiceId',
      );
      unawaited(
        DriveDocumentSyncService.instance.processPendingUploads(
          reason: 'invoice_form_saved',
        ),
      );
    } catch (_) {
      // La factura ya está guardada; Drive se puede reintentar desde Perfil.
    }
  }
}

class _LineItemState {
  int cantidad;
  String descripcion;
  double precioUnitario;

  _LineItemState({
    required this.cantidad,
    required this.descripcion,
    required this.precioUnitario,
  });

  double get total => cantidad * precioUnitario;
}
