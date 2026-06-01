import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../models/ai_assistant.dart';
import '../../providers/ai_chat_provider.dart';

class AiAssistantScreen extends ConsumerStatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  ConsumerState<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends ConsumerState<AiAssistantScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    final sending = ref.read(aiChatProvider).valueOrNull?.sending ?? false;
    if (text.isEmpty || sending) return;
    HapticFeedback.selectionClick();
    _controller.clear();
    await ref.read(aiChatProvider.notifier).send(text);
    _scrollToBottom();
  }

  Future<void> _confirm(AiAssistantMessage message) async {
    await ref.read(aiChatProvider.notifier).confirm(message);
    HapticFeedback.lightImpact();
    _scrollToBottom();
  }

  Future<void> _newChat() async {
    if (_controller.text.trim().isNotEmpty) {
      final shouldContinue = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Crear nuevo chat'),
          content: const Text(
            'Hay texto sin enviar. Si creas un chat nuevo, se limpiará el campo de escritura.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Crear nuevo'),
            ),
          ],
        ),
      );
      if (shouldContinue != true) return;
    }
    _controller.clear();
    await ref.read(aiChatProvider.notifier).newChat();
    _scrollToBottom();
  }

  Future<void> _showChatHistory() async {
    final chats = await ref.read(aiChatRepositoryProvider).getChats();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          itemCount: chats.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final chat = chats[index];
            return ListTile(
              leading: Icon(
                chat.isActive
                    ? Icons.radio_button_checked
                    : Icons.chat_bubble_outline,
              ),
              title: Text(chat.title),
              subtitle: Text(_formatChatDate(chat.updatedAt)),
              onTap: () async {
                Navigator.of(context).pop();
                _controller.clear();
                await ref.read(aiChatProvider.notifier).activateChat(chat.id);
                _scrollToBottom();
              },
            );
          },
        ),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatAsync = ref.watch(aiChatProvider);
    ref.listen(aiChatProvider, (_, __) => _scrollToBottom());

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Bolín'),
        actions: [
          IconButton(
            tooltip: 'Chats anteriores',
            onPressed: _showChatHistory,
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'Nuevo chat',
            onPressed: _newChat,
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      body: chatAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error cargando chat: $error')),
        data: (chatState) {
          return SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: chatState.messages.isEmpty
                      ? const _EmptyChatState()
                      : ListView.builder(
                          controller: _scrollController,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                          itemCount: chatState.messages.length,
                          itemBuilder: (context, index) => _MessageBubble(
                            message: chatState.messages[index],
                            onConfirm: _confirm,
                          ),
                        ),
                ),
                if (chatState.sending)
                  const LinearProgressIndicator(minHeight: 2),
                _Composer(
                  controller: _controller,
                  sending: chatState.sending,
                  onSend: _send,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatChatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month ${hour}h$minute';
  }
}

class _EmptyChatState extends StatelessWidget {
  const _EmptyChatState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              'Pregúntale a Bolín o dile qué quieres apuntar.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Puedo preparar bolos, buscar agenda o dejar acciones listas para confirmar.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final AiAssistantMessage message;
  final ValueChanged<AiAssistantMessage> onConfirm;

  const _MessageBubble({required this.message, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == AiAssistantMessageRole.user;
    final colors = Theme.of(context).colorScheme;
    final preview = message.preview;
    final actionStatus = message.actionStatus;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 720),
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: isUser ? colors.primary : colors.surface,
                border: Border.all(
                  color: isUser ? colors.primary : AppColors.divider,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                child: Text(
                  message.text,
                  style: TextStyle(
                    color: isUser ? colors.onPrimary : AppColors.textPrimary,
                    height: 1.35,
                  ),
                ),
              ),
            ),
            if (preview != null) ...[
              const SizedBox(height: 8),
              _ActionPreviewCard(
                preview: preview,
                status: actionStatus,
                canConfirm:
                    preview.requiresConfirmation &&
                    preview.executable &&
                    actionStatus != AiActionStatus.executing &&
                    actionStatus != AiActionStatus.completed,
                onConfirm: () => onConfirm(message),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionPreviewCard extends StatelessWidget {
  final AiActionPreview preview;
  final AiActionStatus? status;
  final bool canConfirm;
  final VoidCallback onConfirm;

  const _ActionPreviewCard({
    required this.preview,
    required this.status,
    required this.canConfirm,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.fact_check_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    preview.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (status != null) _StatusChip(status: status!),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              preview.description,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            if (preview.items.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...preview.items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _PreviewLine(item: item),
                ),
              ),
            ],
            if (preview.requiresConfirmation) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: canConfirm ? onConfirm : null,
                      icon: status == AiActionStatus.executing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(_confirmButtonLabel(status)),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _confirmButtonLabel(AiActionStatus? status) {
    if (status == AiActionStatus.executing) return 'Ejecutando...';
    if (status == AiActionStatus.completed) return 'Completado';
    if (status == AiActionStatus.failed) return 'Reintentar acción';
    return 'Confirmar acción';
  }
}

class _PreviewLine extends StatelessWidget {
  final String item;

  const _PreviewLine({required this.item});

  @override
  Widget build(BuildContext context) {
    final parts = item.split('|');
    if (parts.length >= 3 && parts.first == 'section') {
      return Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 2),
        child: Text(
          parts[1],
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      );
    }
    if (parts.length >= 3 && parts.first == 'before') {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.circle, size: 8, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${parts[1]}: ${parts[2]}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      );
    }
    if (parts.length >= 4 && parts.first == 'diff') {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.swap_horiz, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 2,
              children: [
                Text('${parts[1]}:'),
                Text(
                  parts[2],
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                const Text('→'),
                Text(
                  parts[3],
                  style: const TextStyle(
                    color: Color(0xFF137D4A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.chevron_right, size: 16),
        const SizedBox(width: 4),
        Expanded(child: Text(item)),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final AiActionStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      AiActionStatus.pendingConfirmation => ('Pendiente', const Color(0xFFA86B00)),
      AiActionStatus.executing => ('Ejecutando', const Color(0xFF1E4DB7)),
      AiActionStatus.completed => ('Completado', const Color(0xFF137D4A)),
      AiActionStatus.failed => ('Error', const Color(0xFFB3261E)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 8, 12, bottomInset > 0 ? 12 : 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              enabled: !sending,
              decoration: const InputDecoration(
                hintText: 'Escribe una acción para Bolín',
                prefixIcon: Icon(Icons.auto_awesome_outlined),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Enviar',
            onPressed: sending ? null : onSend,
            icon: const Icon(Icons.arrow_upward),
          ),
        ],
      ),
    );
  }
}
