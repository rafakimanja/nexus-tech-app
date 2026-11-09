import '../../constants/app_constants.dart';
import '../../exceptions/app_exception.dart';
import '../../models/demanda.dart';
import '../../models/demandante.dart';
import '../../models/denuncia.dart';
import '../../models/enums.dart';
import '../../models/notificacao.dart';
import '../denuncia_repository.dart';
import 'memory_events.dart';
import 'memory_store.dart';

class MemoryDenunciaRepository implements DenunciaRepository {
  final MemoryStore store;
  MemoryDenunciaRepository(this.store);
  @override
  Future<String> denunciar(
      {required Demanda demanda,
      required String professorId,
      required String professorNome,
      required MotivoDenuncia motivo,
      required String descricao,
      required Set<String> adminIds}) async {
    await store.preparar();
    store.exigirUsuario(id: professorId, role: UserRole.professor);
    if (descricao.trim().length < 10)
      throw const ValidationException(
          'Descreva o problema com pelo menos 10 caracteres.');
    if (store.denuncias.values
        .any((d) => d.demandaId == demanda.id && d.professorId == professorId))
      throw const ConflictException('Você já denunciou esta demanda.');
    final id = store.novoId();
    store.denuncias[id] = Denuncia(
        id: id,
        demandaId: demanda.id,
        tituloDemanda: demanda.titulo,
        demandanteId: demanda.demandanteId,
        demandanteNome: demanda.demandanteNome,
        professorId: professorId,
        professorNome: professorNome,
        motivo: motivo,
        descricao: descricao.trim(),
        status: StatusDenuncia.pendente,
        criadoEm: store.agora());
    for (final adminId in adminIds) {
      avisar(store,
          destinatarioId: adminId,
          tipo: TipoNotificacao.denunciaRecebida,
          titulo: 'Nova denúncia',
          corpo: demanda.titulo,
          demandaId: demanda.id,
          denunciaId: id);
    }
    store.notificar();
    return id;
  }

  @override
  Future<bool> jaDenunciou(
      {required String demandaId, required String professorId}) async {
    await store.preparar();
    return store.denuncias.values
        .any((d) => d.demandaId == demandaId && d.professorId == professorId);
  }

  @override
  Stream<List<Denuncia>> observarTodas({bool apenasPendentes = false}) =>
      store.observar(() {
        store.exigirUsuario(role: UserRole.administrador);
        return store.denuncias.values
            .where(
                (d) => !apenasPendentes || d.status == StatusDenuncia.pendente)
            .toList()
          ..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
      });
  @override
  Stream<List<Denuncia>> observarDoProfessor(String professorId) =>
      store.observar(() {
        final u = store.exigirUsuario();
        if (u.role != UserRole.administrador && u.id != professorId)
          throw const PermissionException();
        return store.denuncias.values
            .where((d) => d.professorId == professorId)
            .toList();
      });
  @override
  Stream<List<Denuncia>> observarDoDemandante(String demandanteId) =>
      store.observar(() {
        final u = store.exigirUsuario();
        if (u.role != UserRole.administrador && u.id != demandanteId)
          throw const PermissionException();
        return store.denuncias.values
            .where((d) => d.demandanteId == demandanteId)
            .toList();
      });
  @override
  Future<ResultadoJulgamento> julgar(
      {required Denuncia denuncia,
      required bool procedente,
      required String adminId,
      required String adminNome,
      required String parecer}) async {
    await store.preparar();
    store.exigirUsuario(id: adminId, role: UserRole.administrador);
    final atual = store.denuncias[denuncia.id] ??
        (throw const NotFoundException('Denúncia'));
    if (atual.status != StatusDenuncia.pendente)
      throw const ConflictException('Esta denúncia já foi julgada.');
    if (parecer.trim().length < 10)
      throw const ValidationException(
          'Informe um parecer com pelo menos 10 caracteres.');
    final usuario = store.usuarios[atual.demandanteId];
    if (usuario is! Demandante) throw const NotFoundException('Demandante');
    final strikes = usuario.strikes + (procedente ? 1 : 0);
    final banido = strikes >= AppConstants.strikesParaBanimento;
    store.denuncias[atual.id] = Denuncia.fromMap(atual.id, {
      ...atual.toMap(),
      'status': procedente ? 'procedente' : 'improcedente',
      'analisadaEm': store.agora().toIso8601String(),
      'analisadaPorUid': adminId,
      'analisadaPorNome': adminNome,
      'parecerAdmin': parecer.trim(),
      'strikeAplicado': procedente
    });
    if (procedente) {
      store.atualizarUsuario(usuario.id, {
        'strikes': strikes,
        'banido': banido,
        'banidoEm': banido ? store.agora().toIso8601String() : null
      });
      avisar(store,
          destinatarioId: usuario.id,
          tipo: banido
              ? TipoNotificacao.contaBanida
              : TipoNotificacao.strikeAplicado,
          titulo: 'Denúncia julgada procedente',
          corpo: parecer,
          demandaId: atual.demandaId,
          denunciaId: atual.id);
    }
    avisar(store,
        destinatarioId: atual.professorId,
        tipo: TipoNotificacao.denunciaAnalisada,
        titulo: 'Denúncia analisada',
        corpo: parecer,
        denunciaId: atual.id);
    store.notificar();
    return ResultadoJulgamento(
        procedente: procedente,
        strikeAplicado: procedente,
        strikesTotais: strikes,
        contaBanida: banido);
  }
}
