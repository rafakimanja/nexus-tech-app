import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_tech/core/exceptions/app_exception.dart';
import 'package:nexus_tech/core/models/denuncia.dart';
import 'package:nexus_tech/core/repositories/api/denuncia_repository.dart';
import 'package:nexus_tech/core/services/api_auth_service.dart';
import 'api_backend_test.dart' as f;

Map<String, dynamic> report(
        {String status = 'pendente', bool strike = false}) =>
    {
      'id': 7,
      'demandaId': 42,
      'professorId': 2,
      'motivo': 'spam',
      'descricao': 'Propaganda indevida',
      'status': status,
      'criadoEm': '2026-11-09T12:00:00Z',
      'julgadoPor': status == 'pendente' ? null : 9,
      'julgadoEm': status == 'pendente' ? null : '2026-11-11T12:00:00Z',
      'justificativa': status == 'pendente' ? '' : 'Parecer registrado',
      'strikeAplicado': strike,
    };

Denuncia original() => Denuncia(
      id: '7',
      demandaId: '42',
      tituloDemanda: 'Agenda comunitária',
      demandanteId: '1',
      demandanteNome: 'Associação',
      professorId: '2',
      professorNome: 'Professora',
      motivo: MotivoDenuncia.spam,
      descricao: 'Propaganda indevida',
      status: StatusDenuncia.pendente,
      criadoEm: DateTime.utc(2026, 11, 9, 12),
    );

void main() {
  for (final decisao in ['procedente', 'improcedente']) {
    for (final strike in decisao == 'procedente' ? [false, true] : [false]) {
      test(
          'julgamento $decisao, strike $strike, usa resposta sem leituras posteriores',
          () async {
        final api = f.client((r) {
          expect(r.method, 'PATCH');
          expect(r.url.path, '/reports/7/judgment');
          expect(jsonDecode(r.body),
              {'decisao': decisao, 'justificativa': 'Parecer registrado'});
          return f.json(report(status: decisao, strike: strike));
        })
          ..setToken('jwt');
        final resultado = await ApiDenunciaRepository(api).julgar(
          denuncia: original(),
          procedente: decisao == 'procedente',
          adminId: '999',
          adminNome: 'Não enviar',
          parecer: '  Parecer registrado  ',
        );
        expect(resultado.strikeAplicado, strike);
        expect(resultado.strikesTotais, isNull);
        expect(resultado.contaBanida, isNull);
        final d = resultado.denunciaAtualizada!;
        expect(d.status.name, decisao);
        expect(d.analisadaPorId, '9');
        expect(d.analisadaEm, DateTime.utc(2026, 11, 11, 12));
        expect(d.parecerAdmin, 'Parecer registrado');
        expect(d.professorNome, 'Professora');
      });
    }
  }

  test('valida justificativa por bytes antes de enviar', () async {
    final api = f.client((_) => throw StateError('Não deve enviar'))
      ..setToken('jwt');
    final repo = ApiDenunciaRepository(api);
    for (final texto in ['  ', List.filled(2501, 'á').join()]) {
      await expectLater(
          repo.julgar(
              denuncia: original(),
              procedente: true,
              adminId: '9',
              adminNome: 'Admin',
              parecer: texto),
          throwsA(isA<ValidationException>()));
    }
  });

  test('409 é conflito de julgamento, sem reenvio', () async {
    var calls = 0;
    final api = f.client((_) {
      calls++;
      return f.json({}, 409);
    })
      ..setToken('jwt');
    await expectLater(
        ApiDenunciaRepository(api).julgar(
            denuncia: original(),
            procedente: true,
            adminId: '9',
            adminNome: 'Admin',
            parecer: 'Motivo'),
        throwsA(isA<ConflictException>()));
    expect(calls, 1);
  });

  test('professor lê parecer mesmo sem acesso à demanda cancelada', () async {
    final api = f.client((r) {
      if (r.url.path == '/reports/7')
        return f.json(report(status: 'procedente', strike: true));
      if (r.url.path == '/demands/42') return f.json({}, 403);
      if (r.url.path == '/teachers/2') return f.json(f.teacher());
      throw StateError('Consulta inesperada');
    })
      ..setToken('jwt');
    final d = await ApiDenunciaRepository(api).buscar('7');
    expect(d.parecerAdmin, 'Parecer registrado');
    expect(d.strikeAplicado, isTrue);
    expect(d.professorNome, 'Professora');
  });

  test('403 de bloqueio consulta /me e informa suspensão na sessão', () async {
    final calls = <String>[];
    final api = f.client((r) {
      calls.add(r.url.path);
      if (r.url.path == '/login/v2')
        return f.json({
          'access_token': 'jwt',
          'token_type': 'Bearer',
          'expires_at':
              DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
          'user': f.session(),
        });
      if (r.url.path == '/me')
        return f.json({
          'user': {
            ...f.session(),
            'blocked': true,
            'block_reason': 'strike_limit',
          }
        });
      return f.json({
        'error': {'message': 'account blocked'}
      }, 403);
    });
    final auth = ApiAuthService(api,
        googleToken: () async => 'google', googleSignOut: () async {});
    addTearDown(auth.dispose);
    final erro = Completer<Object>();
    final sub = auth.authStateChanges.listen((_) {}, onError: erro.complete);
    addTearDown(sub.cancel);
    await auth.signInWithGoogle();
    await expectLater(api.request('GET', '/notifications'),
        throwsA(isA<ContaBloqueadaException>()));
    expect(await erro.future, isA<ContaBloqueadaException>());
    expect(calls, ['/login/v2', '/notifications', '/me']);
  });
}
