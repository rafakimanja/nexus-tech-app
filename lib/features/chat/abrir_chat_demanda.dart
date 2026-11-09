import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/exceptions/app_exception.dart';
import '../../core/repositories/chat_repository.dart';
import 'screens/chat_screen.dart';

Future<void> abrirChatDaDemanda(BuildContext context, String demandaId) async {
  try {
    final chat =
        await context.read<ChatRepository>().buscarPorDemanda(demandaId);
    if (!context.mounted) return;
    if (chat == null) throw const NotFoundException('Conversa');
    await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ChatScreen(chatId: chat.id)));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e is AppException
            ? e.message
            : 'Não foi possível abrir a conversa.')));
  }
}
