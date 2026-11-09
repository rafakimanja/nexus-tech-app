import 'package:nexus_tech/core/repositories/api/notificacao_repository.dart';
import 'package:nexus_tech/core/repositories/api/denuncia_repository.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexus_tech/app/app.dart';
import 'package:nexus_tech/app/app_dependencies.dart';
import 'package:nexus_tech/core/api/api_client.dart';
import 'package:nexus_tech/core/repositories/api/admin_repository.dart';
import 'package:nexus_tech/core/repositories/api/area_repository.dart';
import 'package:nexus_tech/core/repositories/api/demanda_repository.dart';
import 'package:nexus_tech/core/repositories/api/recursos_indisponiveis.dart';
import 'package:nexus_tech/core/repositories/api/usuario_repository.dart';
import 'package:nexus_tech/core/services/api_auth_service.dart';
import 'package:nexus_tech/features/auth/screens/login_screen.dart';
import 'package:nexus_tech/features/demandas/screens/professor_home_screen.dart';

void main() {
  testWidgets(
      'login API abre demandas reais do transporte, atualiza e faz logout sem Firebase',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <String>[];
    var status = 'cadastrada';
    final user = {
      'id': 2,
      'name': 'Professora API',
      'email': 'prof@example.test',
      'role': 'professor',
      'profile_complete': true,
      'blocked': false,
      'photo_url': null
    };
    final api = ApiClient('https://example.test', client: MockClient((r) async {
      requests.add('${r.method} ${r.url.path}');
      dynamic data;
      switch (r.url.path) {
        case '/notifications':
        case '/reports':
          return http.Response('[]', 200);
        case '/login/v2':
          data = {
            'access_token': 'jwt',
            'token_type': 'Bearer',
            'expires_at':
                DateTime.now().add(const Duration(hours: 12)).toIso8601String(),
            'user': user
          };
        case '/me':
          data = {'user': user};
        case '/teachers/2':
          data = {
            ...user,
            'siape': '0012345',
            'is_active': true,
            'areas': [],
            'created_at': '2026-11-04T12:00:00Z'
          };
        case '/demands/':
          final mine = r.url.queryParameters['escopo'] == 'minhas';
          data =
              mine && status == 'cadastrada' || !mine && status != 'cadastrada'
                  ? []
                  : [
                      {
                        'id': 42,
                        'demandanteId': 1,
                        'demandanteNome': 'Associação',
                        'demandanteTipo': 'ong',
                        'titulo': 'Demanda recebida da API',
                        'descricao': 'Descrição da demanda',
                        'publicoAlvo': 'Moradores',
                        'impacto': 'Melhorar atendimento',
                        'status': status,
                        'professorId': status == 'cadastrada' ? null : 2,
                        'criadoEm': '2026-11-04T12:00:00Z',
                      }
                    ];
        case '/demands/42/analisar':
          status = 'emAnalise';
          data = {};
        default:
          throw StateError('Endpoint inesperado: ${r.url}');
      }
      if (r.url.path != '/login/v2') {
        expect(r.headers['Authorization'], 'Bearer jwt');
      }
      return http.Response(jsonEncode(data), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    final auth = ApiAuthService(api,
        googleToken: () async => 'google', googleSignOut: () async {});
    final deps = AppDependencies(
        usaApi: true,
        auth: auth,
        usuario: ApiUsuarioRepository(api),
        area: ApiAreaRepository(api),
        demanda: ApiDemandaRepository(api),
        admin: ApiAdminRepository(api),
        anexo: ApiAnexoRepository(),
        chat: ApiChatRepository(),
        denuncia: ApiDenunciaRepository(api),
        fotoPerfil: ApiFotoPerfilRepository(),
        notificacao: ApiNotificacaoRepository(api),
        disposeApi: () {
          auth.dispose();
          api.dispose();
        });
    await tester.pumpWidget(App(dependencies: deps));
    await tester.pumpAndSettle();
    expect(find.text('Demonstração • dados temporários'), findsNothing);
    await tester.tap(find.text('Entrar com Google'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfessorHomeScreen), findsOneWidget);
    expect(find.text('Demanda recebida da API'), findsOneWidget);
    await deps.demanda.marcarParaAnalise(
        demandaId: '42', professorId: '2', professorNome: 'Professora');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Minhas Demandas').last);
    await tester.pumpAndSettle();
    expect(find.text('Demanda recebida da API'), findsOneWidget);
    await tester.tap(find.text('Conversas').last);
    await tester.pumpAndSettle();
    expect(find.text('Conversas ainda não está disponível nesta versão.'),
        findsOneWidget);
    expect(requests.any((r) => r.contains('chat')), false);
    expect(requests.any((r) => r.contains('/notifications')), true);
    expect(find.byTooltip('Notificações'), findsOneWidget);
    await auth.signOut();
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    // Nova sessão não espera o descarte assíncrono de assinaturas anteriores.
    await tester.tap(find.text('Entrar com Google'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfessorHomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
