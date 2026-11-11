import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexus_tech/app/app_config.dart';
import 'package:nexus_tech/core/api/api_client.dart';
import 'package:nexus_tech/core/api/api_dto.dart';
import 'package:nexus_tech/core/exceptions/app_exception.dart';
import 'package:nexus_tech/core/models/area_selecionada.dart';
import 'package:nexus_tech/core/models/criar_demanda.dart';
import 'package:nexus_tech/core/models/demanda.dart';
import 'package:nexus_tech/core/models/enums.dart';
import 'package:nexus_tech/core/models/professor.dart';
import 'package:nexus_tech/core/repositories/api/area_repository.dart';
import 'package:nexus_tech/core/repositories/api/demanda_repository.dart';
import 'package:nexus_tech/core/repositories/api/usuario_repository.dart';
import 'package:nexus_tech/core/repositories/area_repository.dart';
import 'package:nexus_tech/core/services/api_auth_service.dart';

Map<String, dynamic> session({bool complete = true}) => {
      'id': 2,
      'name': 'Professora',
      'email': 'prof@example.test',
      'role': 'professor',
      'photo_url': null,
      'profile_complete': complete,
      'blocked': false,
    };
Map<String, dynamic> teacher() => {
      ...session(),
      'created_at': '2026-11-04T12:00:00Z',
      'siape': '0012345',
      'is_active': true,
      'areas': [
        {'areas_id': 10, 'name': 'Software', 'type': 'técnica'},
        {'areas_id': 11, 'name': 'Educação', 'type': 'interesse'}
      ],
    };
Map<String, dynamic> demand({String status = 'cadastrada'}) => {
      'id': 42,
      'demandanteId': 1,
      'demandanteNome': 'Associação',
      'demandanteTipo': 'ong',
      'titulo': 'Agenda comunitária',
      'descricao': 'Organizar atividades',
      'publicoAlvo': 'Moradores',
      'impacto': 'Facilitar atendimento',
      'status': status,
      'professorId': status == 'cadastrada' ? null : 2,
      'professorNome': status == 'cadastrada' ? null : 'Professora',
      'criadoEm': '2026-11-04T12:00:00Z',
      'atualizadoEm': '2026-11-04T13:00:00Z',
    };
http.Response json(dynamic data, [int code = 200]) =>
    http.Response(jsonEncode(data), code,
        headers: {'content-type': 'application/json; charset=utf-8'});
ApiClient client(FutureOr<http.Response> Function(http.Request) handler,
    {Duration poll = const Duration(hours: 1)}) {
  final api = ApiClient('https://example.test',
      client: MockClient((request) async => handler(request)),
      pollInterval: poll);
  addTearDown(api.dispose);
  return api;
}

void main() {
  test('demandantes antigos não interrompem a leitura por tipo ou campos opcionais', () {
    final base = <String, dynamic>{
      'id': 1,
      'name': 'Associação',
      'email': 'ong@example.test',
      'created_at': '2026-11-04T12:00:00Z',
      'strikes': 3,
    };
    for (final entry in {
      'ONG': TipoDemandante.ong,
      'Órgão Público': TipoDemandante.orgaoPublico,
      'pessoa_fisica': TipoDemandante.pessoaFisica,
      'instituicao-educacional': TipoDemandante.instituicaoEducacional,
      'tipoLegado': TipoDemandante.naoInformado,
      '': TipoDemandante.naoInformado,
    }.entries) {
      final d = apiApplicant({...base, 'type': entry.key});
      expect(d.tipo, entry.value);
      expect(d.nome, 'Associação');
      expect(d.banido, isTrue);
      expect(d.telefone, isEmpty);
    }
    expect(apiApplicant(base).tipo, TipoDemandante.naoInformado);
    expect(TipoDemandante.cadastraveis, isNot(contains(TipoDemandante.naoInformado)));
    expect(apiDemand({...demand(), 'demandanteTipo': 'tipoLegado'}).demandanteTipo,
        TipoDemandante.naoInformado);
  });

  test('bloqueio em /me não consulta endpoints negados nem abre cadastro',
      () async {
    final api = client((r) {
      expect(r.url.path, '/me');
      return json({
        'user': {...session(complete: false), 'blocked': true}
      });
    })
      ..setToken('jwt');
    await expectLater(ApiUsuarioRepository(api).buscarPorId('2'),
        throwsA(isA<ContaBloqueadaException>()));
  });
  test(
      'cadastro usa POST para perfil ausente e PUT para perfil incompleto existente',
      () async {
    for (final exists in [true, false]) {
      final requests = <http.Request>[];
      final api = client((r) {
        requests.add(r);
        if (r.url.path == '/me') {
          return json({
            'user': {
              ...session(complete: false),
              'photo_url': 'https://example.test/photo.png'
            }
          });
        }
        if (r.method == 'GET') {
          return exists
              ? json(teacher())
              : json({
                  'error': {'code': 404}
                }, 404);
        }
        return exists ? http.Response('', 204) : json({'teacherID': 2}, 201);
      })
        ..setToken('jwt');
      await ApiUsuarioRepository(api).criarProfessor(apiTeacher(teacher()));
      expect(requests.last.method, exists ? 'PUT' : 'POST');
      expect(requests.last.url.path, exists ? '/teachers/2' : '/teachers/');
      expect(jsonDecode(requests.last.body)['photo_url'],
          'https://example.test/photo.png');
    }
  });
  test('API é padrão e Firebase continua selecionável', () {
    expect(AppConfig.fromEnvironment().backend, AppBackend.api);
    expect(AppConfig.parse('firebase').backend, AppBackend.firebase);
    expect(() => AppConfig.parse('memory'), throwsArgumentError);
    expect(() => AppConfig.parse('invalid'), throwsArgumentError);
  });
  test('login troca ID token por JWT e respeita papel definido pelo servidor',
      () async {
    final requests = <http.Request>[];
    final api = client((r) {
      requests.add(r);
      if (r.url.path == '/login/v2') {
        return json({
          'access_token': 'api-jwt',
          'token_type': 'Bearer',
          'expires_at':
              DateTime.now().add(const Duration(hours: 12)).toIso8601String(),
          'user': {...session(), 'role': 'admin'},
        });
      }
      return json({'user': session()});
    });
    final auth = ApiAuthService(api,
        googleToken: () async => 'google-id-token', googleSignOut: () async {});
    addTearDown(auth.dispose);
    final events = <String?>[];
    final sub = auth.authStateChanges.listen((u) => events.add(u?.id));
    final user = await auth.signInWithGoogle();
    expect(user!.id, '2');
    expect(user.role, UserRole.administrador);
    expect(requests.single.headers.containsKey('Authorization'), false);
    expect(jsonDecode(requests.single.body), {'idToken': 'google-id-token'});
    await api.request('GET', '/me');
    expect(requests.last.headers['Authorization'], 'Bearer api-jwt');
    await auth.signOut();
    await Future<void>.delayed(Duration.zero);
    expect(events, [null, '2', null]);
    expect(auth.currentUser, isNull);
    await expectLater(api.request('GET', '/me'), throwsA(isA<AuthException>()));
    await sub.cancel();
  });
  test('login cancelado não chama a API', () async {
    final api = client((_) => throw StateError('Não deve acessar a rede'));
    final auth = ApiAuthService(api,
        googleToken: () async => null, googleSignOut: () async {});
    addTearDown(auth.dispose);
    expect(await auth.signInWithGoogle(), isNull);
  });
  test('logout durante login não restaura sessão atrasada', () async {
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final api = client((_) {
      started.complete();
      return response.future;
    });
    final auth = ApiAuthService(api,
        googleToken: () async => 'google', googleSignOut: () async {});
    addTearDown(auth.dispose);
    final pending = auth.signInWithGoogle();
    await started.future;
    await auth.signOut();
    response.complete(json({
      'access_token': 'jwt',
      'token_type': 'Bearer',
      'expires_at':
          DateTime.now().add(const Duration(hours: 12)).toIso8601String(),
      'user': session()
    }));
    expect(await pending, isNull);
    expect(auth.currentUser, isNull);
  });
  test('401 encerra sessão e não permite novas consultas autenticadas',
      () async {
    var login = true;
    final api = client((_) => login
        ? json({
            'access_token': 'jwt',
            'token_type': 'Bearer',
            'expires_at':
                DateTime.now().add(const Duration(hours: 12)).toIso8601String(),
            'user': session()
          })
        : http.Response('Unauthorized', 401));
    final auth = ApiAuthService(api,
        googleToken: () async => 'google', googleSignOut: () async {});
    addTearDown(auth.dispose);
    await auth.signInWithGoogle();
    login = false;
    await expectLater(api.request('GET', '/me'), throwsA(isA<AuthException>()));
    expect(auth.currentUser, isNull);
  });
  test('erros HTTP são tipados; HTML 502 não é tratado como JSON válido',
      () async {
    for (final entry in <int, Matcher>{
      400: isA<ValidationException>(),
      403: isA<PermissionException>(),
      404: isA<NotFoundException>(),
      409: isA<ConflictException>(),
      500: isA<ServerException>()
    }.entries) {
      final api = client((_) => json({
            'error': {'code': entry.key, 'message': 'internal detail'}
          }, entry.key))
        ..setToken('jwt');
      await expectLater(api.request('GET', '/me'), throwsA(entry.value));
    }
    final api = client((_) => http.Response('<html>Bad gateway</html>', 502))
      ..setToken('jwt');
    await expectLater(
        api.request('GET', '/me'), throwsA(isA<ServerException>()));
  });
  test('204 e resposta com lista null são aceitos', () async {
    final api =
        client((r) => r.method == 'PUT' ? http.Response('', 204) : json(null))
          ..setToken('jwt');
    expect(await api.request('PUT', '/teachers/2', body: {}), isNull);
    expect(await ApiAreaRepository(api).listar(TipoArea.tecnica), isEmpty);
  });
  test('perfil incompleto não é interpretado como cadastrado', () async {
    final api = client((r) {
      expect(r.url.path, '/me');
      return json({'user': session(complete: false)});
    })
      ..setToken('jwt');
    expect(await ApiUsuarioRepository(api).buscarPorId('2'), isNull);
  });
  test('perfil professor preserva ID de áreas, zeros no SIAPE e papel',
      () async {
    final api = client(
        (r) => json(r.url.path == '/me' ? {'user': session()} : teacher()))
      ..setToken('jwt');
    final profile =
        await ApiUsuarioRepository(api).buscarPorId('2') as Professor;
    expect(profile.siape, '0012345');
    expect(profile.areasTecnicas.single.id, '10');
    expect(profile.areasInteresse.single.nome, 'Educação');
    expect(profile.role, UserRole.professor);
  });
  test('edição envia formulário completo preservando SIAPE e foto', () async {
    late Map<String, dynamic> body;
    final api = client((r) {
      if (r.method == 'GET') {
        return json(
            {...teacher(), 'photo_url': 'https://example.test/photo.png'});
      }
      expect(r.url.path, '/teachers/2');
      body = jsonDecode(r.body) as Map<String, dynamic>;
      return http.Response('', 204);
    })
      ..setToken('jwt');
    await ApiUsuarioRepository(api).atualizarProfessor(
        id: '2',
        nome: 'Novo nome',
        areasTecnicas: [const AreaSelecionada(id: '10', nome: 'Software')],
        areasInteresse: [const AreaSelecionada(id: '11', nome: 'Educação')]);
    expect(body['name'], 'Novo nome');
    expect(body['siape'], '0012345');
    expect(body['photo_url'], 'https://example.test/photo.png');
    expect(body['areas'], [
      {'areas_id': 10, 'type': 'técnica'},
      {'areas_id': 11, 'type': 'interesse'}
    ]);
  });
  test('criação e ações enviam somente campos aceitos, sem identidade/status',
      () async {
    final requests = <http.Request>[];
    final api = client((r) {
      requests.add(r);
      return json(demand());
    })
      ..setToken('jwt');
    final repo = ApiDemandaRepository(api);
    final id = await repo.criar(const CriarDemanda(
        demandanteId: '1',
        demandanteNome: 'Associação',
        demandanteTipo: TipoDemandante.ong,
        titulo: 'Agenda',
        descricao: 'Descrição',
        publicoAlvo: 'Público',
        impacto: 'Impacto'));
    expect(id, '42');
    expect(jsonDecode(requests.last.body), {
      'titulo': 'Agenda',
      'descricao': 'Descrição',
      'publicoAlvo': 'Público',
      'impacto': 'Impacto'
    });
    await repo.marcarParaAnalise(
        demandaId: id, professorId: '2', professorNome: 'Professora');
    await repo.rejeitarAnalise(demandaId: id, professorId: '2');
    await repo.assumir(demandaId: id, professorId: '2');
    await repo.concluir(
        demandaId: id, professorId: '2', descricaoSolucao: 'Solução');
    expect(jsonDecode(requests.last.body), {'descricaoSolucao': 'Solução'});
    await repo.cancelar(id: id, autorId: '1', motivo: 'Motivo');
    expect(jsonDecode(requests.last.body), {'motivoCancelamento': 'Motivo'});
    expect(requests.map((r) => r.url.path), [
      '/demands/',
      '/demands/42/analisar',
      '/demands/42/devolver',
      '/demands/42/assumir',
      '/demands/42/concluir',
      '/demands/42/cancelar'
    ]);
    expect(jsonDecode(requests[1].body), isEmpty);
  });
  test('listas usam escopo correto e mapeiam IDs, status e datas', () async {
    final api = client((r) {
      expect(r.url.queryParameters['escopo'], 'minhas');
      return json([demand(), demand(status: 'emProducao')]);
    })
      ..setToken('jwt');
    final values = await ApiDemandaRepository(api)
        .listarDoProfessor(
            professorId: '2', filtroStatus: StatusDemanda.emProducao)
        .first;
    expect(values.single.id, '42');
    expect(values.single.professorId, '2');
    expect(values.single.criadoEm, DateTime.utc(2026, 11, 4, 12));
  });
  test('status desconhecido não vira demanda disponível silenciosamente', () {
    expect(
        () => apiDemand(demand(status: 'desconhecido')), throwsArgumentError);
  });
  test('mutações atualizam assinantes, erros transitórios não encerram polling',
      () async {
    var count = 0;
    final api = client((r) {
      if (r.method == 'POST') return http.Response('', 204);
      count++;
      if (count == 1) {
        return json({
          'error': {'code': 500}
        }, 500);
      }
      return json(count);
    })
      ..setToken('jwt');
    final failure = Completer<void>(), recovered = Completer<void>();
    final sub = api.watch(() => api.request('GET', '/value')).listen((value) {
      if (!recovered.isCompleted) recovered.complete();
    }, onError: (Object error) {
      expect(error, isA<ServerException>());
      failure.complete();
    });
    await failure.future;
    await api.request('POST', '/change', body: {});
    await recovered.future;
    await sub.cancel();
    await api.request('POST', '/change', body: {});
    await Future<void>.delayed(Duration.zero);
    expect(count, 2);
  });
  test('resposta de uma sessão anterior nunca chega à próxima', () async {
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final api = client((_) {
      started.complete();
      return response.future;
    })
      ..setToken('old');
    final pending = api.request('GET', '/me');
    await started.future;
    api.setToken('new');
    final assertion = expectLater(pending, throwsA(isA<AuthException>()));
    response.complete(json({'private': 'old session'}));
    await assertion;
  });
  test('recursos ausentes falham explicitamente sem executar requisição',
      () async {
    final api = client(
        (_) => throw StateError('Não deve consultar endpoint inexistente'));
    final repo = ApiDemandaRepository(api);
    await expectLater(
        repo.buscarAnexos('42'), throwsA(isA<RecursoIndisponivelException>()));
    await expectLater(
        repo.criar(
            const CriarDemanda(
                demandanteId: '1',
                demandanteNome: 'A',
                demandanteTipo: TipoDemandante.ong,
                titulo: 'T',
                descricao: 'D',
                publicoAlvo: 'P',
                impacto: 'I'),
            originalCanceladaId: '42'),
        throwsA(isA<RecursoIndisponivelException>()));
  });
}
