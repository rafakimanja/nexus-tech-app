import 'dart:convert';
import '../../api/api_client.dart';
import '../../api/api_dto.dart';
import '../../exceptions/app_exception.dart';
import '../../models/demanda.dart';
import '../../models/denuncia.dart';
import '../denuncia_repository.dart';
import 'notificacao_repository.dart';

class ApiDenunciaRepository implements DenunciaRepository {
  final ApiClient client;
  ApiDenunciaRepository(this.client);

  Denuncia _parse(Map<String, dynamic> m) => Denuncia(
        id: apiId(m['id']),
        demandaId: apiId(m['demandaId']),
        tituloDemanda: 'Demanda #${m['demandaId']}',
        demandanteId: '',
        demandanteNome: '',
        professorId: apiId(m['professorId']),
        professorNome: 'Professor #${m['professorId']}',
        motivo: MotivoDenuncia.from(m['motivo'] as String?),
        descricao: m['descricao'] as String,
        status: StatusDenuncia.from(m['status'] as String?),
        criadoEm: DateTime.parse(m['criadoEm'] as String),
      );

  Future<Denuncia> buscar(String id) async =>
      _parse(await client.request('GET', '/reports/${numericId(id)}')
          as Map<String, dynamic>);

  @override
  Future<String> denunciar(
      {required Demanda demanda,
      required String professorId,
      required String professorNome,
      required MotivoDenuncia motivo,
      required String descricao,
      required Set<String> adminIds}) async {
    final text = descricao.trim();
    if (text.isEmpty || utf8.encode(text).length > 5000) {
      throw const ValidationException(
          'Informe uma descrição de até 5000 bytes.');
    }
    try {
      final result = await client.request('POST', '/reports', body: {
        'demandaId': numericId(demanda.id),
        'motivo': motivo.name,
        'descricao': text,
      }) as Map<String, dynamic>;
      return apiId(result['id']);
    } on ConflictException {
      throw const ConflictException('Você já denunciou esta demanda.');
    }
  }

  @override
  Stream<List<Denuncia>> observarTodas({bool apenasPendentes = false}) =>
      client.watch(() async => (await apiPages(client, '/reports'))
          .map(_parse)
          .where((d) => !apenasPendentes || d.pendente)
          .toList());

  @override
  Future<bool> jaDenunciou(
          {required String demandaId, required String professorId}) async =>
      throw const RecursoIndisponivelException('Consulta prévia de denúncia');
  @override
  Stream<List<Denuncia>> observarDoProfessor(String professorId) =>
      Stream.error(
          const RecursoIndisponivelException('Histórico do professor'));
  @override
  Stream<List<Denuncia>> observarDoDemandante(String demandanteId) =>
      Stream.error(
          const RecursoIndisponivelException('Histórico do demandante'));
  @override
  Future<ResultadoJulgamento> julgar(
          {required Denuncia denuncia,
          required bool procedente,
          required String adminId,
          required String adminNome,
          required String parecer}) async =>
      throw const RecursoIndisponivelException('Julgamento de denúncias');
}
