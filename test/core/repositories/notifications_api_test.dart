import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_tech/core/models/notificacao.dart';
import 'package:nexus_tech/core/models/denuncia.dart';
import 'package:nexus_tech/core/exceptions/app_exception.dart';
import 'package:nexus_tech/core/repositories/api/notificacao_repository.dart';
import 'package:nexus_tech/core/repositories/api/denuncia_repository.dart';
import 'package:nexus_tech/core/services/api_push_service.dart';
import 'api_backend_test.dart' as f;
import 'package:nexus_tech/core/api/api_dto.dart';

Map<String, dynamic> notification(int id) => {
      'id': id,
      'user_id': 2,
      'type': 'demandaRecomendada',
      'title': 'Sugestão',
      'body': 'Nova demanda',
      'resource_type': 'demand',
      'resource_id': 42,
      'created_at': '2026-11-09T12:00:00Z',
      'read_at': null,
    };

class FakeMessaging implements PushMessaging {
  final tokens = StreamController<String>.broadcast();
  String token = 'device-token';
  int deleted = 0;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<String?> getToken() async => token;
  @override
  Future<void> deleteToken() async {
    deleted++;
  }

  @override
  Stream<String> get onTokenRefresh => tokens.stream;
}

void main() {
  test('consulta detalhes de denúncia pelo ID numérico', () async {
    final api = f.client((r) {
      expect(r.url.path, '/reports/7');
      expect(r.headers['Authorization'], 'Bearer jwt');
      return f.json({
        'id': 7,
        'demandaId': 42,
        'professorId': 2,
        'motivo': 'spam',
        'descricao': 'Propaganda indevida',
        'status': 'pendente',
        'criadoEm': '2026-11-09T12:00:00Z',
      });
    })
      ..setToken('jwt');
    final report = await ApiDenunciaRepository(api).buscar('7');
    expect(report.demandaId, '42');
    expect(report.professorId, '2');
    expect(report.motivo, MotivoDenuncia.spam);
  });

  test('renovação registra o token novo; expiração o invalida', () async {
    final registered = StreamController<String>();
    final api = f.client((r) {
      expect(r.method, 'PUT');
      registered.add((jsonDecode(r.body) as Map)['token'] as String);
      return f.json(null, 204);
    })
      ..setToken('jwt');
    final messaging = FakeMessaging();
    final events = StreamIterator(registered.stream);
    final push = ApiPushService(api, messaging)..start();
    await events.moveNext();
    expect(events.current, 'device-token');
    messaging.token = 'renewed-token';
    messaging.tokens.add(messaging.token);
    await events.moveNext();
    expect(events.current, 'renewed-token');
    api.setToken(null);
    await push.stop(expired: true);
    expect(messaging.deleted, 1);
    push.dispose();
    await events.cancel();
    await registered.close();
    await messaging.tokens.close();
  });

  test('paginação inclui avisos antigos e mapeia recursos e leitura', () async {
    final paths = <String>[];
    final api = f.client((r) {
      expect(r.headers['Authorization'], 'Bearer jwt');
      paths.add(r.url.query);
      return f.json(r.url.queryParameters['before'] == null
          ? List.generate(100, (i) => notification(102 - i))
          : [
              {
                ...notification(2),
                'resource_type': 'report',
                'resource_id': 7,
                'type': 'denunciaRecebida',
                'read_at': '2026-11-09T13:00:00Z'
              }
            ]);
    })
      ..setToken('jwt');
    final list = await ApiNotificacaoRepository(api).listar();
    expect(list.length, 101);
    expect(paths.last, 'limit=100&before=3');
    expect(list.first.tipo, TipoNotificacao.demandaRecomendada);
    expect(list.first.demandaId, '42');
    expect(list.last.denunciaId, '7');
    expect(list.last.lida, true);
    expect(list.where((n) => !n.lida).length, 100);
  });

  test('leitura individual e coletiva atualizam observação', () async {
    var read = false;
    final methods = <String>[];
    final api = f.client((r) {
      methods.add('${r.method} ${r.url.path}');
      if (r.method == 'PATCH') {
        read = true;
        return f.json(null, 204);
      }
      return f.json([
        {...notification(12), 'read_at': read ? '2026-11-09T13:00:00Z' : null}
      ]);
    })
      ..setToken('jwt');
    final repo = ApiNotificacaoRepository(api);
    final events = StreamIterator(repo.observar('2'));
    await events.moveNext();
    expect(events.current.single.lida, false);
    await repo.marcarComoLida('12');
    await events.moveNext();
    expect(events.current.single.lida, true);
    await repo.marcarTodasComoLidas('2');
    expect(methods, contains('PATCH /notifications/read-all'));
    await events.cancel();
  });

  test('denúncia envia apenas campos do contrato e trata duplicação', () async {
    final api = f.client((r) {
      expect(r.url.path, '/reports');
      expect(jsonDecode(r.body), {
        'demandaId': 42,
        'motivo': 'spam',
        'descricao': 'Propaganda indevida'
      });
      return f.json({
        'error': {'message': 'duplicate'}
      }, 409);
    })
      ..setToken('jwt');
    await expectLater(
        ApiDenunciaRepository(api).denunciar(
            demanda: apiDemand(f.demand()),
            professorId: '2',
            professorNome: 'Professor',
            motivo: MotivoDenuncia.spam,
            descricao: 'Propaganda indevida',
            adminIds: {'999'}),
        throwsA(isA<ConflictException>()));
  });

  test('logout aguarda registro e remove token no corpo com JWT ativo',
      () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final methods = <String>[];
    final api = f.client((r) async {
      methods.add(r.method);
      expect(r.headers['Authorization'], 'Bearer jwt');
      expect(r.url.path, '/notifications/devices');
      expect(r.url.hasQuery, false);
      expect(jsonDecode(r.body), {'token': 'device-token'});
      if (r.method == 'PUT') {
        entered.complete();
        await release.future;
      }
      return f.json(null, 204);
    })
      ..setToken('jwt');
    final messaging = FakeMessaging();
    final push = ApiPushService(api, messaging)..start();
    await entered.future;
    final stopping = push.stop();
    release.complete();
    await stopping;
    expect(methods, ['PUT', 'DELETE']);
    expect(messaging.deleted, 0);
    push.dispose();
    await messaging.tokens.close();
  });

  test('falha ao desvincular invalida token FCM', () async {
    final api = f.client((_) => f.json({}, 500))..setToken('jwt');
    final messaging = FakeMessaging();
    final push = ApiPushService(api, messaging);
    await push.stop();
    expect(messaging.deleted, 1);
    push.dispose();
    await messaging.tokens.close();
  });
}
