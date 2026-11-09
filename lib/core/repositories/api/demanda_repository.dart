import '../../api/api_client.dart';
import '../../api/api_dto.dart';
import '../../exceptions/app_exception.dart';
import '../../models/anexo.dart';
import '../../models/criar_demanda.dart';
import '../../models/demanda.dart';
import '../demanda_repository.dart';

class ApiDemandaRepository implements DemandaRepository {
  final ApiClient client;
  ApiDemandaRepository(this.client);
  Map<String, dynamic> _fields(String titulo, String descricao,
          String publicoAlvo, String impacto) =>
      {
        'titulo': titulo,
        'descricao': descricao,
        'publicoAlvo': publicoAlvo,
        'impacto': impacto
      };
  @override
  Future<String> criar(CriarDemanda dados,
      {String? originalCanceladaId}) async {
    if (originalCanceladaId != null) {
      throw const RecursoIndisponivelException('Republicação');
    }
    final result = await client.request('POST', '/demands/',
        body: _fields(
            dados.titulo, dados.descricao, dados.publicoAlvo, dados.impacto));
    return apiId(result['id']);
  }

  @override
  Future<void> atualizar(
      {required String id,
      required String autorId,
      required String titulo,
      required String descricao,
      required String publicoAlvo,
      required String impacto}) async {
    await client.request('PUT', '/demands/${numericId(id)}',
        body: _fields(titulo, descricao, publicoAlvo, impacto));
  }

  Future<void> _action(String id, String action,
      [Map<String, dynamic>? body]) async {
    await client.request('POST', '/demands/${numericId(id)}/$action',
        body: body ?? {});
  }

  @override
  Future<void> cancelar(
          {required String id,
          required String autorId,
          required String motivo}) =>
      _action(id, 'cancelar', {'motivoCancelamento': motivo});
  @override
  Future<void> marcarParaAnalise(
          {required String demandaId,
          required String professorId,
          required String professorNome}) =>
      _action(demandaId, 'analisar');
  @override
  Future<void> rejeitarAnalise(
      {required String demandaId,
      required String professorId,
      bool automatico = false}) async {
    // A expiração é reconciliada pelo servidor, nunca simulada pelo cliente.
    if (!automatico) await _action(demandaId, 'devolver');
  }

  @override
  Future<void> assumir(
          {required String demandaId, required String professorId}) =>
      _action(demandaId, 'assumir');
  @override
  Future<void> concluir(
          {required String demandaId,
          required String professorId,
          required String descricaoSolucao}) =>
      _action(demandaId, 'concluir', {'descricaoSolucao': descricaoSolucao});
  @override
  Stream<Demanda?> observar(String id) => client.watch(() async {
        try {
          return apiDemand(
              await client.request('GET', '/demands/${numericId(id)}'));
        } on NotFoundException {
          return null;
        }
      });
  Future<List<Demanda>> listar({String? escopo}) async =>
      apiList(await client.request(
              'GET', '/demands/${escopo == null ? '' : '?escopo=$escopo'}'))
          .map(apiDemand)
          .toList();
  @override
  Stream<List<Demanda>> listarPrateleira() =>
      client.watch(() => listar(escopo: 'prateleira'));
  Stream<List<Demanda>> _mine(StatusDemanda? status, FiltroPeriodo? period) =>
      client.watch(() async {
        final demands = await listar(escopo: 'minhas');
        final range = period?.range;
        return demands
            .where((d) =>
                (status == null || d.status == status) &&
                (range?.inicio == null ||
                    !d.criadoEm.isBefore(range!.inicio!)) &&
                (range?.fim == null || !d.criadoEm.isAfter(range!.fim!)))
            .toList();
      });
  @override
  Stream<List<Demanda>> listarDoDemandante(
          {required String demandanteId,
          StatusDemanda? filtroStatus,
          FiltroPeriodo? filtroPeriodo}) =>
      _mine(filtroStatus, filtroPeriodo);
  @override
  Stream<List<Demanda>> listarDoProfessor(
          {required String professorId,
          StatusDemanda? filtroStatus,
          FiltroPeriodo? filtroPeriodo}) =>
      _mine(filtroStatus, filtroPeriodo);
  @override
  Stream<List<Anexo>> listarAnexos(String demandaId) =>
      Stream.error(const RecursoIndisponivelException('Anexos'));
  @override
  Future<List<Anexo>> buscarAnexos(String demandaId) async =>
      throw const RecursoIndisponivelException('Anexos');
  @override
  Future<int> contarAnexos(String demandaId) async =>
      throw const RecursoIndisponivelException('Anexos');
}
