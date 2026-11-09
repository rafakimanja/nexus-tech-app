import '../../models/criar_demanda.dart';
import '../../exceptions/app_exception.dart';
import '../../models/anexo.dart';
import '../../models/demanda.dart';
import '../../models/enums.dart';
import '../../models/notificacao.dart';
import '../demanda_repository.dart';
import 'memory_events.dart';
import 'memory_store.dart';

class MemoryDemandaRepository implements DemandaRepository {
  final MemoryStore store;
  MemoryDemandaRepository(this.store);

  Demanda _buscar(String id) =>
      store.demandas[id] ?? (throw const NotFoundException('Demanda'));

  void _expirar() {
    for (final d in store.demandas.values.toList()) {
      if (d.status == StatusDemanda.emAnalise &&
          d.analiseExpiraEm != null &&
          !d.analiseExpiraEm!.isAfter(store.agora())) {
        _alterar(d, {
          'status': 'cadastrada',
          'professorUid': null,
          'professorNome': null,
          'analiseIniciadaEm': null,
          'analiseExpiraEm': null
        });
        store.devolvidas
            .update(d.professorId!, (n) => n + 1, ifAbsent: () => 1);
      }
    }
  }

  Demanda _alterar(Demanda d, Map<String, dynamic> campos) =>
      store.demandas[d.id] = Demanda.fromMap(d.id, {
        ...d.toMap(),
        ...campos,
        'atualizadoEm': store.agora().toIso8601String()
      });

  List<Demanda> _lista(bool Function(Demanda) filtro, StatusDemanda? status,
      FiltroPeriodo? periodo) {
    store.exigirUsuario();
    _expirar();
    final range = periodo?.range;
    return store.demandas.values
        .where((d) =>
            filtro(d) &&
            (status == null || d.status == status) &&
            (range?.inicio == null || !d.criadoEm.isBefore(range!.inicio!)) &&
            (range?.fim == null || d.criadoEm.isBefore(range!.fim!)))
        .toList()
      ..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
  }

  @override
  Future<String> criar(CriarDemanda demanda,
      {String? originalCanceladaId}) async {
    await store.preparar();
    store.exigirUsuario(id: demanda.demandanteId, role: UserRole.demandante);
    if (originalCanceladaId != null) {
      final original = _buscar(originalCanceladaId);
      if (original.demandanteId != demanda.demandanteId)
        throw const PermissionException();
      if (original.status != StatusDemanda.cancelada ||
          original.republicadaComoId != null) {
        throw const ConflictException('Esta demanda não pode ser republicada.');
      }
    }
    final id = store.novoId();
    store.demandas[id] = demanda.materializar(id: id, criadoEm: store.agora());
    if (originalCanceladaId != null)
      _alterar(_buscar(originalCanceladaId), {'republicadaComoId': id});
    store.notificar();
    return id;
  }

  @override
  Future<void> atualizar(
      {required String id,
      required String autorId,
      required String titulo,
      required String descricao,
      required String publicoAlvo,
      required String impacto}) async {
    await store.preparar();
    store.exigirUsuario(id: autorId, role: UserRole.demandante);
    final d = _buscar(id);
    if (d.demandanteId != autorId) throw const PermissionException();
    if (!d.status.podeEditarDemandante)
      throw const ConflictException('A demanda já foi assumida.');
    _alterar(d, {
      'titulo': titulo.trim(),
      'descricao': descricao.trim(),
      'publicoAlvo': publicoAlvo.trim(),
      'impacto': impacto.trim()
    });
    store.notificar();
  }

  @override
  Future<void> cancelar(
      {required String id,
      required String autorId,
      required String motivo}) async {
    await store.preparar();
    store.exigirUsuario(id: autorId, role: UserRole.demandante);
    final d = _buscar(id);
    if (d.demandanteId != autorId) throw const PermissionException();
    if (!d.status.podeCancelarDemandante)
      throw const ConflictException(
          'A demanda não pode ser cancelada neste estado.');
    if (motivo.trim().isEmpty)
      throw const ValidationException('Informe o motivo do cancelamento.');
    _alterar(d, {
      'status': 'cancelada',
      'motivoCancelamento': motivo.trim(),
      'canceladoEm': store.agora().toIso8601String()
    });
    store.notificar();
  }

  @override
  Stream<List<Demanda>> listarDoDemandante(
          {required String demandanteId,
          StatusDemanda? filtroStatus,
          FiltroPeriodo? filtroPeriodo}) =>
      store.observar(() {
        store.exigirUsuario(id: demandanteId);
        return _lista(
            (d) => d.demandanteId == demandanteId, filtroStatus, filtroPeriodo);
      });
  @override
  Stream<List<Demanda>> listarDoProfessor(
          {required String professorId,
          StatusDemanda? filtroStatus,
          FiltroPeriodo? filtroPeriodo}) =>
      store.observar(() {
        store.exigirUsuario(id: professorId);
        return _lista(
            (d) => d.professorId == professorId, filtroStatus, filtroPeriodo);
      });
  @override
  Stream<List<Demanda>> listarPrateleira() => store.observar(() {
        store.exigirUsuario(role: UserRole.professor);
        return _lista((d) => d.status.visivelNaPrateleira, null, null);
      });
  @override
  Stream<Demanda?> observar(String id) => store.observar(() {
        _expirar();
        final u = store.exigirUsuario();
        final d = store.demandas[id];
        if (d != null &&
            u.role != UserRole.administrador &&
            d.demandanteId != u.id &&
            !(u.role == UserRole.professor &&
                (d.professorId == u.id || d.status.visivelNaPrateleira)))
          throw const PermissionException();
        return d;
      });

  Demanda _paraAcao(String demandaId, String professorId, StatusDemanda de) {
    store.exigirUsuario(id: professorId, role: UserRole.professor);
    _expirar();
    final d = _buscar(demandaId);
    if (d.status != de ||
        (de == StatusDemanda.cadastrada
            ? d.professorId != null
            : d.professorId != professorId)) {
      throw const ConflictException(
          'A demanda mudou de estado ou está atribuída a outro professor.');
    }
    return d;
  }

  @override
  Future<void> marcarParaAnalise(
      {required String demandaId,
      required String professorId,
      required String professorNome}) async {
    await store.preparar();
    _paraAcao(demandaId, professorId, StatusDemanda.cadastrada);
    // Revalidar após o await também impede duas reservas concorrentes no fake.
    final d = _buscar(demandaId);
    if (d.status != StatusDemanda.cadastrada)
      throw const ConflictException('Esta demanda já foi reservada.');
    _alterar(d, {
      'status': 'emAnalise',
      'professorUid': professorId,
      'professorNome': store.usuarios[professorId]!.nome,
      'analiseIniciadaEm': store.agora().toIso8601String(),
      'analiseExpiraEm':
          store.agora().add(const Duration(hours: 24)).toIso8601String()
    });
    avisar(store,
        destinatarioId: d.demandanteId,
        tipo: TipoNotificacao.demandaEmAnalise,
        titulo: 'Demanda em análise',
        corpo: d.titulo,
        demandaId: d.id);
    store.notificar();
  }

  @override
  Future<void> rejeitarAnalise(
      {required String demandaId,
      required String professorId,
      bool automatico = false}) async {
    await store.preparar();
    store.exigirUsuario(id: professorId, role: UserRole.professor);
    final d = _buscar(demandaId);
    if (d.status != StatusDemanda.emAnalise || d.professorId != professorId)
      throw const ConflictException('A demanda não está em sua análise.');
    _alterar(d, {
      'status': 'cadastrada',
      'professorUid': null,
      'professorNome': null,
      'analiseIniciadaEm': null,
      'analiseExpiraEm': null
    });
    store.devolvidas.update(professorId, (n) => n + 1, ifAbsent: () => 1);
    avisar(store,
        destinatarioId: d.demandanteId,
        tipo: TipoNotificacao.demandaDevolvida,
        titulo: 'Demanda devolvida',
        corpo: d.titulo,
        demandaId: d.id);
    store.notificar();
  }

  @override
  Future<void> assumir(
      {required String demandaId, required String professorId}) async {
    await store.preparar();
    _paraAcao(demandaId, professorId, StatusDemanda.emAnalise);
    final atual = _buscar(demandaId);
    if (atual.status != StatusDemanda.emAnalise ||
        atual.professorId != professorId)
      throw const ConflictException('A demanda mudou.');
    final d = _alterar(atual, {
      'status': 'emProducao',
      'analiseExpiraEm': null,
      'producaoIniciadaEm': store.agora().toIso8601String()
    });
    final chatId = criarChat(store, d);
    avisar(store,
        destinatarioId: d.demandanteId,
        tipo: TipoNotificacao.demandaEmProducao,
        titulo: 'Demanda aceita',
        corpo: d.titulo,
        demandaId: d.id,
        chatId: chatId);
    store.notificar();
  }

  @override
  Future<void> concluir(
      {required String demandaId,
      required String professorId,
      required String descricaoSolucao}) async {
    await store.preparar();
    _paraAcao(demandaId, professorId, StatusDemanda.emProducao);
    final atual = _buscar(demandaId);
    if (atual.status != StatusDemanda.emProducao)
      throw const ConflictException('A demanda já foi concluída.');
    if (descricaoSolucao.trim().isEmpty)
      throw const ValidationException('Descreva a solução entregue.');
    final d = _alterar(atual, {
      'status': 'concluida',
      'descricaoSolucao': descricaoSolucao.trim(),
      'concluidaEm': store.agora().toIso8601String()
    });
    fecharChat(store, demandaId, 'Demanda concluída. Conversa encerrada.');
    avisar(store,
        destinatarioId: d.demandanteId,
        tipo: TipoNotificacao.demandaConcluida,
        titulo: 'Demanda concluída',
        corpo: d.titulo,
        demandaId: d.id);
    store.notificar();
  }

  @override
  Stream<List<Anexo>> listarAnexos(String demandaId) =>
      store.observar(() => store.anexos[demandaId]?.values.toList() ?? []);
  @override
  Future<List<Anexo>> buscarAnexos(String demandaId) async {
    await store.preparar();
    return store.anexos[demandaId]?.values.toList() ?? [];
  }

  @override
  Future<int> contarAnexos(String demandaId) async =>
      store.anexos[demandaId]?.length ?? 0;
}
