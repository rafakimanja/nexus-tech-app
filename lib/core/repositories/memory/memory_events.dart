import '../../models/chat.dart';
import '../../models/demanda.dart';
import '../../models/notificacao.dart';
import 'memory_store.dart';

void avisar(MemoryStore store,
    {required String destinatarioId,
    required TipoNotificacao tipo,
    required String titulo,
    required String corpo,
    String? demandaId,
    String? chatId,
    String? denunciaId}) {
  final id = store.novoId();
  store.notificacoes[id] = Notificacao(
      id: id,
      destinatarioId: destinatarioId,
      autorId: store.sessao?.id ?? '',
      autorNome: store.sessao?.nome ?? 'Nexus Tech',
      tipo: tipo,
      titulo: titulo,
      corpo: corpo,
      criadoEm: store.agora(),
      demandaId: demandaId,
      chatId: chatId,
      denunciaId: denunciaId);
}

String criarChat(MemoryStore store, Demanda demanda) {
  final existentes = store.chats.values.where((c) => c.demandaId == demanda.id);
  if (existentes.isNotEmpty) return existentes.first.id;
  final id = store.novoId();
  store.chats[id] = Chat(
      id: id,
      demandaId: demanda.id,
      tituloDemanda: demanda.titulo,
      demandanteId: demanda.demandanteId,
      demandanteNome: demanda.demandanteNome,
      professorId: demanda.professorId!,
      professorNome: demanda.professorNome!,
      participantes: [demanda.demandanteId, demanda.professorId!],
      naoLidas: {},
      criadoEm: store.agora());
  adicionarMensagem(store,
      chatId: id,
      texto: 'Demanda assumida. A conversa está disponível.',
      sistema: true);
  return id;
}

void adicionarMensagem(MemoryStore store,
    {required String chatId,
    required String texto,
    String autorId = '',
    String autorNome = 'Nexus Tech',
    bool sistema = false}) {
  final chat = store.chats[chatId]!;
  final agora = store.agora();
  final mensagem = Mensagem(
      id: store.novoId(),
      autorId: autorId,
      autorNome: autorNome,
      texto: texto,
      enviadaEm: agora,
      sistema: sistema);
  store.mensagens.putIfAbsent(chatId, () => []).add(mensagem);
  store.chats[chatId] = Chat.fromMap(chatId, {
    ...chat.toMap(),
    'ultimaMensagem': texto,
    'ultimaMensagemAutorUid': autorId,
    'ultimaMensagemEm': agora.toIso8601String(),
    'naoLidas': {
      for (final id in chat.participantes)
        id: sistema
            ? chat.naoLidasDe(id)
            : id == autorId
                ? 0
                : chat.naoLidasDe(id) + 1
    },
  });
}

void fecharChat(MemoryStore store, String demandaId, String motivo) {
  for (final chat
      in store.chats.values.where((c) => c.demandaId == demandaId).toList()) {
    adicionarMensagem(store, chatId: chat.id, texto: motivo, sistema: true);
    store.chats[chat.id] = Chat.fromMap(
        chat.id, {...store.chats[chat.id]!.toMap(), 'ativo': false});
  }
}
