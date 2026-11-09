import '../../constants/app_constants.dart';
import '../../exceptions/app_exception.dart';
import '../../models/demanda.dart';
import '../../models/demandante.dart';
import '../../models/enums.dart';
import '../../models/metricas_professor.dart';
import '../../models/notificacao.dart';
import '../../models/professor.dart';
import '../admin_repository.dart';
import 'memory_events.dart';
import 'memory_store.dart';

class MemoryAdminRepository implements AdminRepository {
  final MemoryStore store;
  MemoryAdminRepository(this.store);
  T _admin<T>(T Function() ler) {
    store.exigirUsuario(role: UserRole.administrador);
    return ler();
  }

  @override
  Stream<List<Professor>> observarProfessores() => store.observar(() => _admin(
      () => store.usuarios.values.whereType<Professor>().toList()
        ..sort((a, b) => a.nome.compareTo(b.nome))));
  @override
  Stream<List<Demandante>> observarDemandantes() => store.observar(() => _admin(
      () => store.usuarios.values.whereType<Demandante>().toList()
        ..sort((a, b) => a.nome.compareTo(b.nome))));
  @override
  Stream<List<Demanda>> observarTodasDemandas() =>
      store.observar(() => _admin(() => store.demandas.values.toList()
        ..sort((a, b) => b.criadoEm.compareTo(a.criadoEm))));
  @override
  Stream<MetricasProfessor> observarMetricas(String professorId) =>
      store.observar(() => _admin(() => MetricasProfessor.calcular(
          professorId: professorId,
          demandas: store.demandas.values
              .where((d) => d.professorId == professorId)
              .toList(),
          devolvidas: store.devolvidas[professorId] ?? 0)));
  @override
  Stream<List<Demanda>> observarDemandasDoProfessor(String professorId) =>
      store.observar(() => _admin(() => store.demandas.values
          .where((d) => d.professorId == professorId)
          .toList()));
  @override
  Future<void> definirProfessorAtivo(
      {required Professor professor,
      required bool ativo,
      required String adminId,
      required String adminNome,
      String? motivo}) async {
    await store.preparar();
    store.exigirUsuario(id: adminId, role: UserRole.administrador);
    if (!ativo && (motivo == null || motivo.trim().length < 5))
      throw const ValidationException(
          'Informe o motivo da desativação (mínimo 5 caracteres).');
    store.atualizarUsuario(professor.id, {
      'ativo': ativo,
      'desativadoEm': ativo ? null : store.agora().toIso8601String(),
      'motivoDesativacao': ativo ? null : motivo!.trim()
    });
    avisar(store,
        destinatarioId: professor.id,
        tipo: ativo
            ? TipoNotificacao.perfilReativado
            : TipoNotificacao.perfilDesativado,
        titulo: ativo ? 'Perfil reativado' : 'Perfil desativado',
        corpo: motivo ?? 'Seu perfil foi reativado.');
    store.notificar();
  }

  @override
  Future<void> ajustarStrikes(
      {required Demandante demandante,
      required int novoTotal,
      required String adminId,
      required String adminNome,
      required String motivo}) async {
    await store.preparar();
    store.exigirUsuario(id: adminId, role: UserRole.administrador);
    if (novoTotal < 0 || motivo.trim().length < 5)
      throw const ValidationException(
          'Informe uma contagem válida e um motivo (mínimo 5 caracteres).');
    final banido = novoTotal >= AppConstants.strikesParaBanimento;
    store.atualizarUsuario(demandante.id, {
      'strikes': novoTotal,
      'banido': banido,
      'banidoEm': banido ? store.agora().toIso8601String() : null,
      'motivoBanimento': banido ? motivo.trim() : null
    });
    avisar(store,
        destinatarioId: demandante.id,
        tipo: banido
            ? TipoNotificacao.contaBanida
            : TipoNotificacao.strikeAplicado,
        titulo: 'Advertências atualizadas',
        corpo: motivo.trim());
    store.notificar();
  }

  @override
  Future<void> reverterBanimento(
          {required Demandante demandante,
          required String adminId,
          required String adminNome,
          required String motivo}) =>
      ajustarStrikes(
          demandante: demandante,
          novoTotal: 0,
          adminId: adminId,
          adminNome: adminNome,
          motivo: motivo);
}
