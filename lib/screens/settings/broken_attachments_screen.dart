import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/drive_document_sync_service.dart';

class BrokenAttachmentsScreen extends StatefulWidget {
  const BrokenAttachmentsScreen({super.key});

  @override
  State<BrokenAttachmentsScreen> createState() => _BrokenAttachmentsScreenState();
}

class _BrokenAttachmentsScreenState extends State<BrokenAttachmentsScreen> {
  late Future<List<BrokenAttachmentItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = DriveDocumentSyncService.instance.getBrokenAttachments();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Adjuntos rotos')),
      body: FutureBuilder<List<BrokenAttachmentItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const Center(child: Text('No hay adjuntos rotos.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                child: ListTile(
                  title: Text(
                    '${item.entityType == 'expense' ? 'Gasto' : 'Inversión'} #${item.entityId}',
                  ),
                  subtitle: Text(
                    '${item.fileName ?? 'Sin nombre'}\n${item.reason}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: true,
                  trailing: TextButton(
                    onPressed: () {
                      if (item.entityType == 'expense') {
                        context.push('/expense/edit/${item.entityId}');
                      } else {
                        context.push('/asset/edit/${item.entityId}');
                      }
                    },
                    child: const Text('Reasignar'),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
