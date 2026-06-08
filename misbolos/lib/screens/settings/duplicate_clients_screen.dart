import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../database/database_helper.dart';
import '../../models/client.dart';
import '../../providers/client_provider.dart';
import '../../providers/gig_provider.dart';
import '../../providers/invoice_provider.dart';

// ==================== UTILIDADES ====================

String _normalize(String s) {
  return s
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n')
      // Abreviaturas → forma completa
      .replaceAll(RegExp(r'\bentreb\.?\b'), 'entrebotas')
      // Sufijos que no cambian el cliente
      .replaceAll(RegExp(r'\bsono\b'), '')
      .replaceAll(RegExp(r'\bsonora\b'), '')
      .replaceAll(RegExp(r'\bs\.?l\.?\b'), '')
      .replaceAll(RegExp(r'\bs\.?a\.?\b'), '')
      .replaceAll(RegExp(r'\bslu\b'), '')
      .replaceAll(RegExp(r'\binversiones\b'), '')
      .replaceAll(RegExp(r'\(.*?\)'), '')
      .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  List<int> v0 = List.generate(b.length + 1, (i) => i);
  List<int> v1 = List.filled(b.length + 1, 0);

  for (int i = 0; i < a.length; i++) {
    v1[0] = i + 1;
    for (int j = 0; j < b.length; j++) {
      final cost = a[i] == b[j] ? 0 : 1;
      v1[j + 1] = [v1[j] + 1, v0[j + 1] + 1, v0[j] + cost]
          .reduce((x, y) => x < y ? x : y);
    }
    v0 = List.from(v1);
  }
  return v0[b.length];
}

bool _isDuplicate(
    String normI, List<String> aliasesI, String normJ, List<String> aliasesJ) {
  if (normI == normJ) return true;
  if (normI.length >= 4 && normJ.contains(normI)) return true;
  if (normJ.length >= 4 && normI.contains(normJ)) return true;
  if (aliasesI.contains(normJ)) return true;
  if (aliasesJ.contains(normI)) return true;
  if (_levenshtein(normI, normJ) <= 2) return true;
  return false;
}

List<List<Client>> _findDuplicateGroups(List<Client> clients) {
  final groups = <List<Client>>[];
  final processed = <String>{};

  for (int i = 0; i < clients.length; i++) {
    if (processed.contains(clients[i].id)) continue;

    final group = [clients[i]];
    final normI = _normalize(clients[i].nombre);
    final aliasesI = [
      if (clients[i].alias.isNotEmpty) _normalize(clients[i].alias),
      ...clients[i].aliases.map(_normalize),
    ];

    for (int j = i + 1; j < clients.length; j++) {
      if (processed.contains(clients[j].id)) continue;

      final normJ = _normalize(clients[j].nombre);
      final aliasesJ = [
        if (clients[j].alias.isNotEmpty) _normalize(clients[j].alias),
        ...clients[j].aliases.map(_normalize),
      ];

      if (_isDuplicate(normI, aliasesI, normJ, aliasesJ)) {
        group.add(clients[j]);
        processed.add(clients[j].id);
      }
    }

    if (group.length > 1) {
      groups.add(group);
      processed.add(clients[i].id);
    }
  }

  return groups;
}

// ==================== PANTALLA ====================

class DuplicateClientsScreen extends ConsumerStatefulWidget {
  const DuplicateClientsScreen({super.key});

  @override
  ConsumerState<DuplicateClientsScreen> createState() =>
      _DuplicateClientsScreenState();
}

class _DuplicateClientsScreenState
    extends ConsumerState<DuplicateClientsScreen> {
  List<List<Client>>? _groups;
  Map<String, int> _gigCounts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _findDuplicates();
  }

  Future<void> _findDuplicates() async {
    setState(() => _loading = true);
    final clients = await ref.read(clientsProvider.future);

    // Count gigs per client for recommendation
    final db = await DatabaseHelper.instance.database;
    final counts = await db.rawQuery(
      'SELECT client_id, COUNT(*) as cnt FROM gigs GROUP BY client_id',
    );
    final gigCounts = <String, int>{};
    for (final row in counts) {
      gigCounts[row['client_id'] as String] = row['cnt'] as int;
    }

    final groups = _findDuplicateGroups(clients);

    setState(() {
      _groups = groups;
      _gigCounts = gigCounts;
      _loading = false;
    });
  }

  String _recommendedId(List<Client> group) {
    // 1. Si uno tiene CIF/NIF → ese es el principal
    final withCif = group.where((c) => c.cifNif.isNotEmpty).toList();
    if (withCif.length == 1) return withCif.first.id;

    // 2. El que tenga más bolos asociados
    final sorted = [...group]..sort((a, b) {
        final gigsA = _gigCounts[a.id] ?? 0;
        final gigsB = _gigCounts[b.id] ?? 0;
        return gigsB.compareTo(gigsA);
      });
    if ((_gigCounts[sorted.first.id] ?? 0) >
        (_gigCounts[sorted[1].id] ?? 0)) {
      return sorted.first.id;
    }

    // 3. Empate → el nombre más largo (más completo)
    final byLength = [...group]
      ..sort((a, b) => b.nombre.length.compareTo(a.nombre.length));
    return byLength.first.id;
  }

  Future<void> _mergeClients(Client keep, List<Client> duplicates) async {
    final db = await DatabaseHelper.instance.database;

    // Collect all aliases from duplicates
    final allAliases = <String>{...keep.aliases};
    if (keep.alias.isNotEmpty) allAliases.add(keep.alias);

    for (final dup in duplicates) {
      // Add duplicate name and aliases as aliases of the kept client
      allAliases.add(dup.nombre);
      if (dup.alias.isNotEmpty) allAliases.add(dup.alias);
      allAliases.addAll(dup.aliases);

      // Reassign all gigs from duplicate to kept client
      await db.update(
        'gigs',
        {'client_id': keep.id},
        where: 'client_id = ?',
        whereArgs: [dup.id],
      );

      // Reassign all invoices from duplicate to kept client
      await db.update(
        'invoices',
        {'client_id': keep.id},
        where: 'client_id = ?',
        whereArgs: [dup.id],
      );

      // Delete the duplicate client
      await db.delete('clients', where: 'id = ?', whereArgs: [dup.id]);
    }

    // Remove keep's own name from aliases
    allAliases.remove(keep.nombre.toLowerCase());
    allAliases.remove(keep.nombre);

    // Update kept client with merged aliases
    final updated = keep.copyWith(aliases: allAliases.toList());
    await db.update(
      'clients',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [keep.id],
    );

    // Refresh providers
    ref.invalidate(clientsProvider);
    ref.invalidate(gigsProvider);
    ref.invalidate(invoicesProvider);

    // Re-scan
    await _findDuplicates();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Fusionados ${duplicates.length + 1} clientes → ${keep.nombre}'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes duplicados'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _groups == null || _groups!.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 64,
                          color: AppColors.success.withValues(alpha: 0.5)),
                      const SizedBox(height: 16),
                      Text(
                        'No se encontraron duplicados',
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _groups!.length,
                  itemBuilder: (context, index) {
                    final group = _groups![index];
                    return _DuplicateGroupCard(
                      group: group,
                      recommendedId: _recommendedId(group),
                      gigCounts: _gigCounts,
                      onMerge: (keep, dups) => _mergeClients(keep, dups),
                    );
                  },
                ),
    );
  }
}

class _DuplicateGroupCard extends StatefulWidget {
  final List<Client> group;
  final String recommendedId;
  final Map<String, int> gigCounts;
  final Future<void> Function(Client keep, List<Client> duplicates) onMerge;

  const _DuplicateGroupCard({
    required this.group,
    required this.recommendedId,
    required this.gigCounts,
    required this.onMerge,
  });

  @override
  State<_DuplicateGroupCard> createState() => _DuplicateGroupCardState();
}

class _DuplicateGroupCardState extends State<_DuplicateGroupCard> {
  late String _selectedKeepId;
  bool _merging = false;

  @override
  void initState() {
    super.initState();
    _selectedKeepId = widget.recommendedId;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: AppColors.warning, size: 20),
                const SizedBox(width: 8),
                Text(
                  '${widget.group.length} posibles duplicados',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Selecciona el cliente que quieres conservar:',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: _selectedKeepId,
              onChanged: (v) =>
                  setState(() => _selectedKeepId = v ?? _selectedKeepId),
              child: Column(
                children: widget.group.map((client) {
                  final isRecommended = client.id == widget.recommendedId;
                  final gigs = widget.gigCounts[client.id] ?? 0;
                  return RadioListTile<String>(
                    value: client.id,
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            client.nombre,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (isRecommended)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.successBg,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'Recomendado',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.success,
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Text(
                      [
                        if (client.alias.isNotEmpty) 'Alias: ${client.alias}',
                        if (client.cifNif.isNotEmpty) 'NIF: ${client.cifNif}',
                        if (client.email != null && client.email!.isNotEmpty)
                          client.email!,
                        '$gigs bolos',
                      ].join(' · '),
                      style: const TextStyle(fontSize: 12),
                    ),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _merging
                    ? null
                    : () async {
                        final keep = widget.group
                            .firstWhere((c) => c.id == _selectedKeepId);
                        final dups = widget.group
                            .where((c) => c.id != _selectedKeepId)
                            .toList();

                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Confirmar fusión'),
                            content: Text(
                              'Se conservará "${keep.nombre}" y se fusionarán '
                              '${dups.length} cliente(s) duplicado(s). '
                              'Sus bolos y facturas se reasignarán. '
                              'Esta acción no se puede deshacer.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancelar'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.warning,
                                ),
                                child: const Text('Fusionar'),
                              ),
                            ],
                          ),
                        );

                        if (confirmed == true) {
                          setState(() => _merging = true);
                          await widget.onMerge(keep, dups);
                        }
                      },
                icon: _merging
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.merge_type),
                label: const Text('Fusionar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
