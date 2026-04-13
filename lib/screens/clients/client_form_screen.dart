import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../models/client.dart';
import '../../providers/client_provider.dart';

class ClientFormScreen extends ConsumerStatefulWidget {
  final String? clientId;
  const ClientFormScreen({super.key, this.clientId});

  @override
  ConsumerState<ClientFormScreen> createState() => _ClientFormScreenState();
}

class _ClientFormScreenState extends ConsumerState<ClientFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _aliasController = TextEditingController();
  final _newAliasController = TextEditingController();
  List<String> _aliases = [];
  final _cifNifController = TextEditingController();
  final _direccionController = TextEditingController();
  final _ciudadController = TextEditingController();
  final _provinciaController = TextEditingController();
  final _codigoPostalController = TextEditingController();
  final _emailController = TextEditingController();
  final _telefonoController = TextEditingController();
  bool _isLoading = false;
  Client? _existingClient;

  @override
  void initState() {
    super.initState();
    if (widget.clientId != null) {
      _loadClient();
    }
  }

  Future<void> _loadClient() async {
    final client = await ref.read(clientByIdProvider(widget.clientId!).future);
    if (client != null && mounted) {
      setState(() {
        _existingClient = client;
        _nombreController.text = client.nombre;
        _aliasController.text = client.alias;
        _aliases = List<String>.from(client.aliases);
        _cifNifController.text = client.cifNif;
        _direccionController.text = client.direccion;
        _ciudadController.text = client.ciudad;
        _provinciaController.text = client.provincia;
        _codigoPostalController.text = client.codigoPostal;
        _emailController.text = client.email ?? '';
        _telefonoController.text = client.telefono ?? '';
      });
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _aliasController.dispose();
    _newAliasController.dispose();
    _cifNifController.dispose();
    _direccionController.dispose();
    _ciudadController.dispose();
    _provinciaController.dispose();
    _codigoPostalController.dispose();
    _emailController.dispose();
    _telefonoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.clientId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? AppStrings.editarCliente : AppStrings.nuevoCliente),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nombreController,
              decoration: const InputDecoration(
                labelText: '${AppStrings.nombre} *',
                prefixIcon: Icon(Icons.person),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? AppStrings.campoObligatorio : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _aliasController,
              decoration: const InputDecoration(
                labelText: 'Alias principal',
                hintText: 'Nombre corto para encontrarlo rápido',
                prefixIcon: Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: 12),
            // Aliases adicionales (nombres alternativos)
            InputDecorator(
              decoration: InputDecoration(
                labelText: 'Nombres alternativos',
                helperText: 'Otros nombres con los que se conoce al cliente',
                prefixIcon: const Icon(Icons.people_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_aliases.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: _aliases.map((a) => Chip(
                        label: Text(a),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () {
                          setState(() => _aliases.remove(a));
                        },
                        backgroundColor: AppColors.primaryLight,
                        labelStyle: const TextStyle(color: AppColors.primary),
                      )).toList(),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newAliasController,
                          decoration: const InputDecoration(
                            hintText: 'Añadir nombre alternativo...',
                            isDense: true,
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _addAlias(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
                        onPressed: _addAlias,
                        tooltip: 'Añadir',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _cifNifController,
              decoration: const InputDecoration(
                labelText: AppStrings.cifNif,
                prefixIcon: Icon(Icons.badge),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _direccionController,
              decoration: const InputDecoration(
                labelText: AppStrings.direccion,
                prefixIcon: Icon(Icons.location_on),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _ciudadController,
                    decoration: const InputDecoration(
                      labelText: AppStrings.ciudad,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _codigoPostalController,
                    decoration: const InputDecoration(
                      labelText: 'C.P.',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _provinciaController,
              decoration: const InputDecoration(
                labelText: 'Provincia',
                prefixIcon: Icon(Icons.map),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: AppStrings.email,
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
              validator: (v) {
                if (v != null && v.isNotEmpty && !v.contains('@')) {
                  return AppStrings.emailInvalido;
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _telefonoController,
              decoration: const InputDecoration(
                labelText: AppStrings.telefono,
                prefixIcon: Icon(Icons.phone),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 32),
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

  void _addAlias() {
    final text = _newAliasController.text.trim();
    if (text.isNotEmpty && !_aliases.contains(text)) {
      setState(() {
        _aliases.add(text);
        _newAliasController.clear();
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      final telefono = _telefonoController.text.trim();

      if (_existingClient != null) {
        final updated = _existingClient!.copyWith(
          nombre: _nombreController.text.trim(),
          alias: _aliasController.text.trim(),
          aliases: _aliases,
          cifNif: _cifNifController.text.trim(),
          direccion: _direccionController.text.trim(),
          ciudad: _ciudadController.text.trim(),
          provincia: _provinciaController.text.trim(),
          codigoPostal: _codigoPostalController.text.trim(),
          email: email.isEmpty ? null : email,
          telefono: telefono.isEmpty ? null : telefono,
        );
        await ref.read(clientsProvider.notifier).updateClient(updated);
      } else {
        final client = Client(
          nombre: _nombreController.text.trim(),
          alias: _aliasController.text.trim(),
          aliases: _aliases,
          cifNif: _cifNifController.text.trim(),
          direccion: _direccionController.text.trim(),
          ciudad: _ciudadController.text.trim(),
          provincia: _provinciaController.text.trim(),
          codigoPostal: _codigoPostalController.text.trim(),
          email: email.isEmpty ? null : email,
          telefono: telefono.isEmpty ? null : telefono,
        );
        await ref.read(clientsProvider.notifier).add(client);
      }

      ref.invalidate(clientsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_existingClient != null
                ? AppStrings.clienteActualizado
                : AppStrings.clienteCreado),
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
