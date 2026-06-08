import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ai_assistant.dart';
import '../repositories/ai_chat_repository.dart';
import '../services/ai_assistant_service.dart';
import '../services/ai_conversation_context_service.dart';

final aiChatRepositoryProvider = Provider((ref) => AiChatRepository.instance);

final aiChatProvider = AsyncNotifierProvider<AiChatNotifier, AiChatState>(
  AiChatNotifier.new,
);

class AiChatState {
  final AiChat activeChat;
  final List<AiAssistantMessage> messages;
  final bool sending;
  final String? error;

  const AiChatState({
    required this.activeChat,
    required this.messages,
    this.sending = false,
    this.error,
  });

  AiChatState copyWith({
    AiChat? activeChat,
    List<AiAssistantMessage>? messages,
    bool? sending,
    String? error,
    bool clearError = false,
  }) {
    return AiChatState(
      activeChat: activeChat ?? this.activeChat,
      messages: messages ?? this.messages,
      sending: sending ?? this.sending,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class AiChatNotifier extends AsyncNotifier<AiChatState> {
  @override
  Future<AiChatState> build() async {
    final repository = ref.read(aiChatRepositoryProvider);
    final chat = await repository.getOrCreateActiveChat();
    final messages = await repository.getMessages(chat.id);
    return AiChatState(activeChat: chat, messages: messages);
  }

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final current = state.valueOrNull;
    if (current == null || current.sending) return;

    final repository = ref.read(aiChatRepositoryProvider);
    final userMessage = AiAssistantMessage(
      role: AiAssistantMessageRole.user,
      text: trimmed,
    );
    await repository.addMessage(
      chatId: current.activeChat.id,
      message: userMessage,
    );

    state = AsyncData(
      current.copyWith(
        messages: [...current.messages, userMessage],
        sending: true,
        clearError: true,
      ),
    );

    try {
      final conversationContext = AiConversationContextService.instance
          .fromMessages(current.messages);
      final contextualUpdate = _tryContextualAmountUpdate(
        message: trimmed,
        context: conversationContext,
      );
      if (contextualUpdate.$1 != null) {
        final action = contextualUpdate.$1!;
        final preview = await AiAssistantService.instance.buildPreview(action);
        final nextContext = AiConversationContextService.instance.fromAction(
          action: action,
          current: conversationContext,
        );
        final actionId =
            '${current.activeChat.id}-${DateTime.now().microsecondsSinceEpoch}';
        var metadata = aiActionMetadata(
          action: action,
          preview: preview,
          actionId: actionId,
          actionStatus: AiActionStatus.pendingConfirmation,
        );
        metadata = AiConversationContextService.instance.attach(
          metadata,
          nextContext,
        );
        final assistantMessage = AiAssistantMessage(
          role: AiAssistantMessageRole.assistant,
          text: preview.description,
          action: action,
          preview: preview,
          metadata: metadata,
        );
        await repository.addMessage(
          chatId: current.activeChat.id,
          message: assistantMessage,
        );
        final latest = state.valueOrNull;
        if (latest == null) return;
        state = AsyncData(
          latest.copyWith(
            messages: [...latest.messages, assistantMessage],
            sending: false,
            clearError: true,
          ),
        );
        return;
      }
      if (contextualUpdate.$2 != null) {
        var metadata = aiActionMetadata();
        metadata = AiConversationContextService.instance.attach(
          metadata,
          conversationContext,
        );
        final assistantMessage = AiAssistantMessage(
          role: AiAssistantMessageRole.assistant,
          text: contextualUpdate.$2!,
          metadata: metadata,
        );
        await repository.addMessage(
          chatId: current.activeChat.id,
          message: assistantMessage,
        );
        final latest = state.valueOrNull;
        if (latest == null) return;
        state = AsyncData(
          latest.copyWith(
            messages: [...latest.messages, assistantMessage],
            sending: false,
            clearError: true,
          ),
        );
        return;
      }
      final pendingResolved = AiConversationContextService.instance
          .tryResolvePending(
            context: conversationContext,
            message: trimmed,
            now: DateTime.now(),
          );
      debugPrint('[AiChat] raw_message="$trimmed"');
      if (pendingResolved.action == null &&
          pendingResolved.assistantMessage != null) {
        var metadata = aiActionMetadata();
        metadata = AiConversationContextService.instance.attach(
          metadata,
          pendingResolved.context,
        );
        final assistantMessage = AiAssistantMessage(
          role: AiAssistantMessageRole.assistant,
          text: pendingResolved.assistantMessage!,
          metadata: metadata,
        );
        await repository.addMessage(
          chatId: current.activeChat.id,
          message: assistantMessage,
        );
        final latest = state.valueOrNull;
        if (latest == null) return;
        state = AsyncData(
          latest.copyWith(
            messages: [...latest.messages, assistantMessage],
            sending: false,
            clearError: true,
          ),
        );
        return;
      }
      final entities = _conversationEntities(current.messages);
      final collectionGigIds = _lastCollectionGigIds(current.messages);
      if (conversationContext.lastReferencedEntity != null) {
        final refEntity = conversationContext.lastReferencedEntity!;
        final entityType = refEntity['entity_type'] ?? '';
        final entityId = refEntity['entity_id'] ?? '';
        if (entityType.isNotEmpty && entityId.isNotEmpty) {
          entities.insert(0, {'type': entityType, 'id': entityId});
        }
      }
      final interpreted = pendingResolved.action ??
          await AiAssistantService.instance.interpret(
            trimmed,
            conversationEntities: entities,
            collectionGigIds: collectionGigIds,
          );
      debugPrint('[AiChat] intent_detectado=${interpreted.accion}');
      final action = await AiAssistantService.instance.resolveEntities(
        interpreted,
      );
      debugPrint('[AiChat] filtros_extraidos=${action.filtros}');
      final preview = await AiAssistantService.instance.buildPreview(action);
      final responseText = action.pregunta?.trim().isNotEmpty == true
          ? action.pregunta!
          : (pendingResolved.assistantMessage ?? preview.description);
      final nextContext = AiConversationContextService.instance.fromAction(
        action: action,
        current: pendingResolved.context,
      );
      debugPrint(
        '[AiChat] lastReferencedEntity BEFORE=${pendingResolved.context.lastReferencedEntity}',
      );
      debugPrint('[AiChat] lastReferencedEntity AFTER=${nextContext.lastReferencedEntity}');
      final actionId = '${current.activeChat.id}-${DateTime.now().microsecondsSinceEpoch}';
      var metadata = aiActionMetadata(
        action: action,
        preview: preview,
        actionId: actionId,
        actionStatus: preview.requiresConfirmation
            ? AiActionStatus.pendingConfirmation
            : null,
      );
      final previewCollectionGigIds = await AiAssistantService.instance
          .collectionGigIdsFor(action);
      if (previewCollectionGigIds.isNotEmpty) {
        metadata['collection_gig_ids'] = previewCollectionGigIds;
      }
      metadata = AiConversationContextService.instance.attach(
        metadata,
        nextContext,
      );
      final assistantMessage = AiAssistantMessage(
        role: AiAssistantMessageRole.assistant,
        text: responseText,
        action: action,
        preview: preview,
        metadata: metadata,
      );
      await repository.addMessage(
        chatId: current.activeChat.id,
        message: assistantMessage,
      );
      final latest = state.valueOrNull;
      if (latest == null) return;
      state = AsyncData(
        latest.copyWith(
          messages: [...latest.messages, assistantMessage],
          sending: false,
          clearError: true,
        ),
      );
    } catch (e) {
      final errorMessage = AiAssistantMessage(
        role: AiAssistantMessageRole.assistant,
        text:
            'No he podido interpretar eso. Prueba con una frase más concreta. $e',
      );
      await repository.addMessage(
        chatId: current.activeChat.id,
        message: errorMessage,
      );
      final latest = state.valueOrNull;
      if (latest == null) return;
      state = AsyncData(
        latest.copyWith(
          messages: [...latest.messages, errorMessage],
          sending: false,
          error: e.toString(),
        ),
      );
    }
  }

  (AiAssistantAction?, String?) _tryContextualAmountUpdate({
    required String message,
    required AiConversationContext context,
  }) {
    final lower = message.toLowerCase();
    final isContextualVerb = lower.contains('cámbiale') ||
        lower.contains('cambiale') ||
        lower.contains('modifícale') ||
        lower.contains('modificale') ||
        lower.contains('ponle') ||
        lower.contains('súbele') ||
        lower.contains('subele') ||
        lower.contains('bájale') ||
        lower.contains('bajale');
    final amountMatch = RegExp(r'(\d+(?:[.,]\d{1,2})?)\s*€').firstMatch(lower);
    if (!isContextualVerb || amountMatch == null) {
      return (null, null);
    }
    final amount = double.tryParse(amountMatch.group(1)!.replaceAll(',', '.'));
    final reference = context.lastReferencedEntity;
    final entityType = reference?['entity_type'] ?? '';
    final entityId = reference?['entity_id'] ?? '';

    debugPrint(
      '[CONTEXT_UPDATE_AMOUNT] lastReferencedEntity=$reference extractedAmount=$amount resolvedEntityId=$entityId',
    );

    if (amount == null) return (null, null);
    if (entityType != 'gig' || entityId.isEmpty) {
      return (
        null,
        'Necesito que me digas qué bolo quieres modificar antes de cambiar el importe.',
      );
    }
    final raw = <String, dynamic>{
      'accion': 'actualizar_bolo',
      'requiere_confirmacion': true,
      'confianza': 0.96,
      'resolved_entity_type': 'gig',
      'resolved_entity_id': entityId,
      'filtros': const <String, dynamic>{},
      'objetivo': {'gig_id': entityId},
      'updates': {'importe': amount},
      'cliente': const <String, dynamic>{},
      'clientes': const <dynamic>[],
      'factura': const <String, dynamic>{},
      'email': const <String, dynamic>{},
      'advertencias': const <dynamic>[],
      '_source_message': message,
    };
    return (AiAssistantAction.fromJson(raw), null);
  }

  Future<void> confirm(AiAssistantMessage message) async {
    final action = message.action;
    final current = state.valueOrNull;
    if (action == null || current == null || current.sending) return;
    final status = message.actionStatus;
    if (status == AiActionStatus.executing || status == AiActionStatus.completed) {
      return;
    }
    final actionId = message.actionId;
    if (actionId != null &&
        current.messages.any(
          (item) =>
              item.id != message.id &&
              item.actionId == actionId &&
              item.actionStatus == AiActionStatus.completed,
        )) {
      return;
    }

    final executingMessage = _withActionStatus(
      message,
      AiActionStatus.executing,
    );
    await ref.read(aiChatRepositoryProvider).updateMessageMetadata(
      messageId: message.id,
      metadata: executingMessage.metadata ?? const {},
    );
    final withExecuting = _replaceMessage(current.messages, executingMessage);
    state = AsyncData(
      current.copyWith(
        messages: withExecuting,
        sending: true,
        clearError: true,
      ),
    );

    try {
      final result = await AiAssistantService.instance.execute(action, ref);
      final currentContext = AiConversationContextService.instance.fromMessages(
        state.valueOrNull?.messages ?? const [],
      );
      final nextContext = AiConversationContext(
        pendingAction: null,
        missingFields: const [],
        partialData: const {},
        lastCreatedActionId: currentContext.lastCreatedActionId,
        lastPreviewAction: currentContext.lastPreviewAction,
        lastReferencedEntity:
            result.referencedEntity ?? currentContext.lastReferencedEntity,
      );
      var metadata = aiActionMetadata(preview: result.preview);
      metadata = AiConversationContextService.instance.attach(
        metadata,
        nextContext,
      );
      final assistantMessage = AiAssistantMessage(
        role: AiAssistantMessageRole.assistant,
        text: result.message,
        preview: result.preview,
        metadata: metadata.isEmpty ? null : metadata,
      );
      await ref
          .read(aiChatRepositoryProvider)
          .addMessage(chatId: current.activeChat.id, message: assistantMessage);
      final latest = state.valueOrNull;
      if (latest == null) return;
      final completedMessage = _withActionStatus(
        executingMessage,
        AiActionStatus.completed,
      );
      await ref.read(aiChatRepositoryProvider).updateMessageMetadata(
        messageId: completedMessage.id,
        metadata: completedMessage.metadata ?? const {},
      );
      state = AsyncData(
        latest.copyWith(
          messages: [
            ..._replaceMessage(latest.messages, completedMessage),
            assistantMessage,
          ],
          sending: false,
          clearError: true,
        ),
      );
    } catch (e) {
      final errorMessage = AiAssistantMessage(
        role: AiAssistantMessageRole.assistant,
        text: 'No he podido ejecutar la acción: $e',
      );
      await ref
          .read(aiChatRepositoryProvider)
          .addMessage(chatId: current.activeChat.id, message: errorMessage);
      final latest = state.valueOrNull;
      if (latest == null) return;
      final failedMessage = _withActionStatus(
        executingMessage,
        AiActionStatus.failed,
      );
      await ref.read(aiChatRepositoryProvider).updateMessageMetadata(
        messageId: failedMessage.id,
        metadata: failedMessage.metadata ?? const {},
      );
      state = AsyncData(
        latest.copyWith(
          messages: [
            ..._replaceMessage(latest.messages, failedMessage),
            errorMessage,
          ],
          sending: false,
          error: e.toString(),
        ),
      );
    }
  }

  Future<void> newChat() async {
    final repository = ref.read(aiChatRepositoryProvider);
    final chat = await repository.createChat(title: 'Nuevo chat');
    state = AsyncData(AiChatState(activeChat: chat, messages: const []));
  }

  Future<void> activateChat(String chatId) async {
    final repository = ref.read(aiChatRepositoryProvider);
    await repository.setActiveChat(chatId);
    final chat = await repository.getActiveChat();
    if (chat == null) return;
    final messages = await repository.getMessages(chat.id);
    state = AsyncData(AiChatState(activeChat: chat, messages: messages));
  }

  List<Map<String, String>> _conversationEntities(
    List<AiAssistantMessage> messages,
  ) {
    final entities = <Map<String, String>>[];
    for (final message in messages.reversed) {
      final action = message.action;
      final id = action?.resolvedEntityId?.trim();
      final type = action?.resolvedEntityType?.trim();
      if (id == null || type == null || id.isEmpty || type.isEmpty) continue;
      final already = entities.any(
        (item) => item['id'] == id && item['type'] == type,
      );
      if (already) continue;
      entities.add({'type': type, 'id': id});
      if (entities.length >= 8) break;
    }
    return entities;
  }

  List<String> _lastCollectionGigIds(List<AiAssistantMessage> messages) {
    for (final message in messages.reversed) {
      final raw = message.metadata?['collection_gig_ids'];
      if (raw is List) {
        return raw
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList();
      }
    }
    return const [];
  }

  AiAssistantMessage _withActionStatus(
    AiAssistantMessage message,
    AiActionStatus status,
  ) {
    final metadata = <String, dynamic>{...?(message.metadata)};
    metadata['action_status'] = status.value;
    return AiAssistantMessage(
      id: message.id,
      role: message.role,
      text: message.text,
      action: message.action,
      preview: message.preview,
      metadata: metadata,
      createdAt: message.createdAt,
    );
  }

  List<AiAssistantMessage> _replaceMessage(
    List<AiAssistantMessage> source,
    AiAssistantMessage replacement,
  ) {
    return source
        .map((item) => item.id == replacement.id ? replacement : item)
        .toList();
  }
}
