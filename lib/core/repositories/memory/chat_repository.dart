import '../../constants/app_constants.dart';
import '../../exceptions/app_exception.dart';
import '../../models/chat.dart';
import '../../models/notificacao.dart';
import '../chat_repository.dart';
import 'memory_events.dart';
import 'memory_store.dart';

class MemoryChatRepository implements ChatRepository {
  final MemoryStore store;
  MemoryChatRepository(this.store);

  Chat _buscar(String id) {
    final usuario = store.exigirUsuario();
    final chat = store.chats[id] ?? (throw const NotFoundException('Conversa'));
    if (!chat.participantes.contains(usuario.id))
      throw const PermissionException();
    return chat;
  }

  @override
  Stream<List<Chat>> observarChats(String id) => store.observar(() {
        store.exigirUsuario(id: id);
        return store.chats.values
            .where((c) => c.participantes.contains(id))
            .toList()
          ..sort((a, b) => (b.ultimaMensagemEm ?? b.criadoEm)
              .compareTo(a.ultimaMensagemEm ?? a.criadoEm));
      });
  @override
  Stream<Chat?> observarChat(String chatId) => store
      .observar(() => store.chats.containsKey(chatId) ? _buscar(chatId) : null);
  @override
  Stream<List<Mensagem>> observarMensagens(String chatId) => store.observar(() {
        _buscar(chatId);
        return (store.mensagens[chatId] ?? [])
            .reversed
            .take(AppConstants.limiteMensagensChat)
            .toList()
            .reversed
            .toList();
      });
  @override
  Future<Chat?> buscar(String chatId) async {
    await store.preparar();
    return store.chats.containsKey(chatId) ? _buscar(chatId) : null;
  }

  @override
  Future<Chat?> buscarPorDemanda(String demandaId) async {
    await store.preparar();
    final chats = store.chats.values.where((c) => c.demandaId == demandaId);
    return chats.isEmpty ? null : _buscar(chats.first.id);
  }

  @override
  Future<void> enviarMensagem(
      {required String chatId,
      required String autorId,
      required String autorNome,
      required String texto}) async {
    await store.preparar();
    store.exigirUsuario(id: autorId);
    final chat = _buscar(chatId);
    if (!chat.ativo)
      throw const ConflictException('Esta conversa foi encerrada.');
    if (texto.trim().isEmpty ||
        texto.length > AppConstants.maxCaracteresMensagem)
      throw const ValidationException('Mensagem vazia ou muito longa.');
    final destino = chat.outroId(autorId);
    adicionarMensagem(store,
        chatId: chatId,
        autorId: autorId,
        autorNome: autorNome,
        texto: texto.trim());
    if (chat.naoLidasDe(destino) == 0)
      avisar(store,
          destinatarioId: destino,
          tipo: TipoNotificacao.novaMensagem,
          titulo: 'Nova mensagem',
          corpo: texto.trim(),
          demandaId: chat.demandaId,
          chatId: chatId);
    store.notificar();
  }

  @override
  Future<void> registrarMensagemSistema(
      {required String chatId, required String texto}) async {
    await store.preparar();
    _buscar(chatId);
    adicionarMensagem(store, chatId: chatId, texto: texto, sistema: true);
    store.notificar();
  }

  @override
  Future<void> marcarComoLido(
      {required String chatId, required String id}) async {
    await store.preparar();
    store.exigirUsuario(id: id);
    final chat = _buscar(chatId);
    if (chat.naoLidasDe(id) == 0) return;
    store.chats[chatId] = Chat.fromMap(chatId, {
      ...chat.toMap(),
      'naoLidas': {...chat.naoLidas, id: 0}
    });
    store.notificar();
  }

  @override
  Future<void> encerrar(
      {required String chatId, required String motivo}) async {
    await store.preparar();
    final chat = _buscar(chatId);
    fecharChat(store, chat.demandaId, motivo);
    store.notificar();
  }
}
