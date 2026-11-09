import '../../exceptions/app_exception.dart';
import '../../models/notificacao.dart';
import '../notificacao_repository.dart';
import 'memory_events.dart';
import 'memory_store.dart';

class MemoryNotificacaoRepository implements NotificacaoRepository {
  final MemoryStore store;
  MemoryNotificacaoRepository(this.store);
  @override
  Stream<List<Notificacao>> observar(String id) => store.observar(() {
        store.exigirUsuario(id: id);
        return store.notificacoes.values
            .where((n) => n.destinatarioId == id)
            .toList()
          ..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
      });
  @override
  Future<void> marcarComoLida(String id) async {
    await store.preparar();
    final n = store.notificacoes[id] ??
        (throw const NotFoundException('Notificação'));
    store.exigirUsuario(id: n.destinatarioId);
    store.notificacoes[id] = Notificacao.fromMap(id, {
      ...n.toMap(),
      'lida': true,
      'lidaEm': store.agora().toIso8601String()
    });
    store.notificar();
  }

  @override
  Future<void> marcarTodasComoLidas(String id) async {
    await store.preparar();
    store.exigirUsuario(id: id);
    for (final n in store.notificacoes.values
        .where((n) => n.destinatarioId == id)
        .toList()) {
      store.notificacoes[n.id] = Notificacao.fromMap(n.id, {
        ...n.toMap(),
        'lida': true,
        'lidaEm': store.agora().toIso8601String()
      });
    }
    store.notificar();
  }

  @override
  Future<void> enfileirar(
      {required String destinatarioId,
      required String autorId,
      required String autorNome,
      required TipoNotificacao tipo,
      required String titulo,
      required String corpo,
      String? demandaId,
      String? chatId,
      String? denunciaId}) async {
    await store.preparar();
    store.exigirUsuario(id: autorId);
    avisar(store,
        destinatarioId: destinatarioId,
        tipo: tipo,
        titulo: titulo,
        corpo: corpo,
        demandaId: demandaId,
        chatId: chatId,
        denunciaId: denunciaId);
    store.notificar();
  }
}
