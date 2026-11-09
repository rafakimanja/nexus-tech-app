import '../models/notificacao.dart';

/// Contrato de dados independente do backend.
abstract interface class NotificacaoRepository {
  Stream<List<Notificacao>> observar(String id);

  Future<void> marcarComoLida(String id);

  Future<void> marcarTodasComoLidas(String id);

  Future<void> enfileirar({
    required String destinatarioId,
    required String autorId,
    required String autorNome,
    required TipoNotificacao tipo,
    required String titulo,
    required String corpo,
    String? demandaId,
    String? chatId,
    String? denunciaId,
  });
}
