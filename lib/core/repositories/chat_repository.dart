import '../models/chat.dart';

/// Contrato de dados independente do backend.
abstract interface class ChatRepository {
  Stream<List<Chat>> observarChats(String id);

  Stream<Chat?> observarChat(String chatId);

  Stream<List<Mensagem>> observarMensagens(String chatId);

  Future<Chat?> buscar(String chatId);

  /// Localiza a conversa sem presumir igualdade entre IDs de entidades.
  Future<Chat?> buscarPorDemanda(String demandaId);

  Future<void> enviarMensagem({
    required String chatId,
    required String autorId,
    required String autorNome,
    required String texto,
  });

  Future<void> registrarMensagemSistema({
    required String chatId,
    required String texto,
  });

  Future<void> marcarComoLido({
    required String chatId,
    required String id,
  });

  Future<void> encerrar({
    required String chatId,
    required String motivo,
  });
}
