import '../../api/api_client.dart';
import '../../api/api_dto.dart';
import '../../exceptions/app_exception.dart';
import '../../models/demanda.dart';
import '../../models/demandante.dart';
import '../../models/metricas_professor.dart';
import '../../models/professor.dart';
import '../admin_repository.dart';
import 'demanda_repository.dart';

class ApiAdminRepository implements AdminRepository {
  final ApiClient client;
  ApiAdminRepository(this.client);
  @override
  Stream<List<Professor>> observarProfessores() => client.watch(() async =>
      apiList(await client.request('GET', '/teachers/'))
          .map(apiTeacher)
          .toList());
  @override
  Stream<List<Demandante>> observarDemandantes() => client.watch(() async =>
      apiList(await client.request('GET', '/applicants/'))
          .map(apiApplicant)
          .toList());
  @override
  Stream<List<Demanda>> observarTodasDemandas() =>
      client.watch(() => ApiDemandaRepository(client).listar());
  @override
  Stream<List<Demanda>> observarDemandasDoProfessor(String professorId) =>
      observarTodasDemandas().map(
          (all) => all.where((d) => d.professorId == professorId).toList());
  // A API não fornece o histórico de devoluções necessário às métricas completas.
  @override
  Stream<MetricasProfessor> observarMetricas(String professorId) =>
      observarDemandasDoProfessor(professorId)
          .map((demandas) => MetricasProfessor.calcular(
                professorId: professorId,
                demandas: demandas,
                historicoDevolucoesDisponivel: false,
              ));
  @override
  Future<void> definirProfessorAtivo(
          {required Professor professor,
          required bool ativo,
          required String adminId,
          required String adminNome,
          String? motivo}) async =>
      throw const RecursoIndisponivelException(
          'Alteração de situação do professor');
  @override
  Future<void> ajustarStrikes(
          {required Demandante demandante,
          required int novoTotal,
          required String adminId,
          required String adminNome,
          required String motivo}) async =>
      throw const RecursoIndisponivelException('Ajuste de advertências');
  @override
  Future<void> reverterBanimento(
          {required Demandante demandante,
          required String adminId,
          required String adminNome,
          required String motivo}) async =>
      throw const RecursoIndisponivelException('Reversão de banimento');
}
