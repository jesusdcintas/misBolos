import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../models/client.dart';
import '../../providers/client_provider.dart';

Future<Client?> showClientPicker(
  BuildContext context,
  WidgetRef ref, {
  String? selectedClientId,
}) async {
  final isMobile = MediaQuery.of(context).size.width < 900;
  if (isMobile) {
    return Navigator.of(context).push<Client>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ClientPickerScreen(selectedClientId: selectedClientId),
      ),
    );
  }

  return showDialog<Client>(
    context: context,
    barrierDismissible: true,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
        child: ClientPickerScreen(
          selectedClientId: selectedClientId,
          embeddedDialog: true,
        ),
      ),
    ),
  );
}

class ClientPickerScreen extends ConsumerStatefulWidget {
  final String? selectedClientId;
  final bool embeddedDialog;

  const ClientPickerScreen({
    super.key,
    this.selectedClientId,
    this.embeddedDialog = false,
  });

  @override
  ConsumerState<ClientPickerScreen> createState() => _ClientPickerScreenState();
}

class _ClientPickerScreenState extends ConsumerState<ClientPickerScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _normalize(String input) {
    const accentMap = {
      'á': 'a',
      'à': 'a',
      'ä': 'a',
      'â': 'a',
      'ã': 'a',
      'é': 'e',
      'è': 'e',
      'ë': 'e',
      'ê': 'e',
      'í': 'i',
      'ì': 'i',
      'ï': 'i',
      'î': 'i',
      'ó': 'o',
      'ò': 'o',
      'ö': 'o',
      'ô': 'o',
      'õ': 'o',
      'ú': 'u',
      'ù': 'u',
      'ü': 'u',
      'û': 'u',
      'ñ': 'n',
      'ç': 'c',
    };
    final lower = input.toLowerCase().trim();
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(accentMap[char] ?? char);
    }
    return buffer.toString();
  }

  bool _matches(Client client, String normalizedQuery) {
    if (normalizedQuery.isEmpty) return true;
    final haystacks = <String>[
      client.nombre,
      client.alias,
      ...client.aliases,
    ].map(_normalize);
    return haystacks.any((text) => text.contains(normalizedQuery));
  }

  Future<void> _createClient() async {
    await context.push('/client/new');
    if (!mounted) return;
    ref.invalidate(clientsProvider);
  }

  Widget _buildHeader(BuildContext context) {
    final title = const Text(
      'Seleccionar cliente',
      style: TextStyle(fontWeight: FontWeight.w700),
    );

    if (!widget.embeddedDialog) {
      return AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: title,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Cancelar'),
          ),
        ],
      );
    }

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 4),
            Expanded(child: title),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _clientTile(Client client, {required bool selected}) {
    final displayName = client.alias.isNotEmpty ? client.alias : client.nombre;
    final subtitleParts = <String>[
      if (client.alias.isNotEmpty) client.nombre,
      if ((client.telefono ?? '').trim().isNotEmpty) client.telefono!.trim(),
      if ((client.email ?? '').trim().isNotEmpty) client.email!.trim(),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).pop(client),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.45)
                    : AppColors.divider,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: selected
                      ? AppColors.primary.withValues(alpha: 0.18)
                      : AppColors.background,
                  child: Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      if (subtitleParts.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitleParts.join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle, color: AppColors.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clientsAsync = ref.watch(clientsProvider);
    final normalizedQuery = _normalize(_query);

    final body = Column(
      children: [
        SafeArea(
          top: false,
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Buscar cliente...',
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
          ),
        ),
        Expanded(
          child: clientsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 34,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 10),
                    Text('Error cargando clientes: $error'),
                  ],
                ),
              ),
            ),
            data: (clients) {
              if (clients.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.people_outline,
                          size: 42,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(height: 12),
                        const Text('No tienes clientes creados todavía'),
                        const SizedBox(height: 14),
                        ElevatedButton.icon(
                          onPressed: _createClient,
                          icon: const Icon(Icons.add),
                          label: const Text('Crear nuevo cliente'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final filtered = clients
                  .where((client) => _matches(client, normalizedQuery))
                  .toList(growable: false);

              if (filtered.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.search_off, size: 40),
                        const SizedBox(height: 10),
                        const Text('No se encontraron clientes'),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: _createClient,
                          icon: const Icon(Icons.person_add_alt_1),
                          label: const Text('Crear nuevo cliente'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.builder(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: filtered.length,
                itemBuilder: (_, index) {
                  final client = filtered[index];
                  return _clientTile(
                    client,
                    selected: client.id == widget.selectedClientId,
                  );
                },
              );
            },
          ),
        ),
      ],
    );

    if (!widget.embeddedDialog) {
      return Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: _buildHeader(context),
        ),
        body: SafeArea(top: false, child: body),
      );
    }

    return Material(
      color: AppColors.surface,
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(child: body),
        ],
      ),
    );
  }
}
