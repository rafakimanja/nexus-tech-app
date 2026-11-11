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

  Future<Denuncia> _parse(Map<String, dynamic> m,
      Map<String, Future<Map<String, dynamic>?>> relacionados) async {
    String? texto(dynamic value) =>
        value is String && value.trim().isNotEmpty ? value.trim() : null;

    Future<Map<String, dynamic>?> buscarRelacionado(String path) =>
        relacionados.putIfAbsent(path, () async {
          try {
            return Map<String, dynamic>.from(
                await client.request('GET', path) as Map);
          } on NotFoundException {
            // Uma conta ou demanda removida não deve esconder a denúncia.
            return null;
          } on PermissionException {
            // O professor pode consultar o parecer mesmo quando já não pode
            // acessar a demanda cancelada ou os perfis relacionados.
            return null;
          }
        });

    final demanda = texto(m['tituloDemanda']) == null ||
            texto(m['demandanteNome']) == null ||
            m['demandanteId'] == null
        ? await buscarRelacionado(
            '/demands/${numericId(apiId(m['demandaId']))}')
        : null;
    final professor = texto(m['professorNome']) == null
        ? await buscarRelacionado(
            '/teachers/${numericId(apiId(m['professorId']))}')
        : null;
    final demandanteId = m['demandanteId'] ?? demanda?['demandanteId'];
    return Denuncia(
      id: apiId(m['id']),
      demandaId: apiId(m['demandaId']),
      tituloDemanda: texto(m['tituloDemanda']) ??
          texto(demanda?['titulo']) ??
          'Demanda indisponível',
      demandanteId: demandanteId == null ? '' : apiId(demandanteId),
      demandanteNome: texto(m['demandanteNome']) ??
          texto(demanda?['demandanteNome']) ??
          'Demandante indisponível',
      professorId: apiId(m['professorId']),
      professorNome: texto(m['professorNome']) ??
          texto(professor?['name']) ??
          'Professor indisponível',
      motivo: MotivoDenuncia.from(m['motivo'] as String?),
      descricao: m['descricao'] as String,
      status: StatusDenuncia.from(m['status'] as String?),
      criadoEm: DateTime.parse(m['criadoEm'] as String),
      analisadaEm: m['julgadoEm'] == null
          ? null
          : DateTime.parse(m['julgadoEm'] as String),
      analisadaPorId: m['julgadoPor'] == null ? null : apiId(m['julgadoPor']),
      parecerAdmin: texto(m['justificativa']),
      strikeAplicado: m['strikeAplicado'] as bool? ?? false,
    );
  }

  Future<Denuncia> buscar(String id) async => _parse(
      await client.request('GET', '/reports/${numericId(id)}')
          as Map<String, dynamic>,
      {});

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
      client.watch(() async {
        final registros = await apiPages(client, '/reports');
        final relacionados = <String, Future<Map<String, dynamic>?>>{};
        final denuncias =
            await Future.wait(registros.map((m) => _parse(m, relacionados)));
        return denuncias.where((d) => !apenasPendentes || d.pendente).toList();
      });

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
      required String parecer}) async {
    final texto = parecer.trim();
    if (texto.isEmpty || utf8.encode(texto).length > 5000) {
      throw const ValidationException(
          'Informe uma justificativa de até 5000 bytes.');
    }
    if (!denuncia.pendente) {
      throw const ConflictException('Esta denúncia já foi julgada.');
    }
    late Map<String, dynamic> resposta;
    try {
      resposta = await client.request(
          'PATCH', '/reports/${numericId(denuncia.id)}/judgment',
          body: {
            'decisao': procedente ? 'procedente' : 'improcedente',
            'justificativa': texto,
          }) as Map<String, dynamic>;
    } on ConflictException {
      throw const ConflictException(
          'Esta denúncia já foi julgada por outro administrador.');
    }
    // Não faz leituras auxiliares depois do PATCH: uma falha nelas não pode
    // transformar uma decisão já gravada em aparente falha do julgamento.
    final atualizada = Denuncia(
      id: apiId(resposta['id']),
      demandaId: apiId(resposta['demandaId']),
      tituloDemanda: denuncia.tituloDemanda,
      demandanteId: denuncia.demandanteId,
      demandanteNome: denuncia.demandanteNome,
      professorId: apiId(resposta['professorId']),
      professorNome: denuncia.professorNome,
      motivo: MotivoDenuncia.from(resposta['motivo'] as String?),
      descricao: resposta['descricao'] as String,
      status: StatusDenuncia.values.byName(resposta['status'] as String),
      criadoEm: DateTime.parse(resposta['criadoEm'] as String),
      analisadaEm: DateTime.parse(resposta['julgadoEm'] as String),
      analisadaPorId: apiId(resposta['julgadoPor']),
      parecerAdmin: resposta['justificativa'] as String,
      strikeAplicado: resposta['strikeAplicado'] as bool,
    );
    return ResultadoJulgamento(
      procedente: atualizada.status == StatusDenuncia.procedente,
      strikeAplicado: atualizada.strikeAplicado,
      denunciaAtualizada: atualizada,
    );
  }
}
