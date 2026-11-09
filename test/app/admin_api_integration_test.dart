import 'package:nexus_tech/core/repositories/api/notificacao_repository.dart';
import 'package:nexus_tech/core/repositories/api/denuncia_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:nexus_tech/features/admin/screens/admin_home_screen.dart';
import 'package:nexus_tech/features/admin/screens/admin_professor_metricas_screen.dart';
import 'package:nexus_tech/features/admin/screens/admin_demandante_detalhes_screen.dart';
import 'package:nexus_tech/features/admin/screens/api_admin_screen.dart';
import 'package:nexus_tech/features/admin/widgets/admin_widgets.dart';
import 'package:nexus_tech/features/auth/screens/login_screen.dart';
import '../core/repositories/api_backend_test.dart' as fixtures;

void main() {
  for (final failInitially in [false, true]) {
    testWidgets(
        'painel original integrado à API, falha inicial: $failInitially',
        (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var fail = failInitially;
      final requests = <String>[];
      final user = {
        ...fixtures.session(),
        'id': 9,
        'role': 'admin',
        'name': 'Admin API'
      };
      final api =
          ApiClient('https://example.test', client: MockClient((r) async {
        requests.add('${r.method} ${r.url.path}');
        if (r.url.path == '/login/v2') {
          return fixtures.json({
            'access_token': 'jwt',
            'token_type': 'Bearer',
            'expires_at':
                DateTime.now().add(const Duration(hours: 12)).toIso8601String(),
            'user': user,
          });
        }
        expect(r.headers['Authorization'], 'Bearer jwt');
        expect(r.method, 'GET');
        if (r.url.path == '/notifications' || r.url.path == '/reports') {
          return fixtures.json([]);
        }
        switch (r.url.path) {
          case '/me':
            return fixtures.json({'user': user});
          case '/teachers/':
            return fail
                ? fixtures.json({}, 500)
                : fixtures.json([fixtures.teacher()]);
          case '/applicants/':
            return fixtures.json([
              {
                'id': 1,
                'name': 'Associação API',
                'email': 'ong@example.test',
                'created_at': '2026-11-04T12:00:00Z',
                'phone': '11999999999',
                'type': 'ong',
                'cpf_cnpj': '12345678000100',
                'address': 'Rua Um',
                'strikes': 1,
                'blocked': false,
              }
            ]);
          case '/demands/':
            expect(r.url.queryParameters['escopo'], isNull);
            return fail
                ? fixtures.json({}, 500)
                : fixtures.json([
                    fixtures.demand(status: 'emProducao'),
                    {
                      ...fixtures.demand(status: 'concluida'),
                      'id': 43,
                      'titulo': 'Demanda entregue',
                      'analiseIniciadaEm': '2026-11-01T12:00:00Z',
                      'producaoIniciadaEm': '2026-11-02T12:00:00Z',
                      'concluidaEm': '2026-11-04T12:00:00Z'
                    },
                    {
                      ...fixtures.demand(status: 'emAnalise'),
                      'id': 44,
                      'professorId': 99
                    },
                  ]);
          default:
            throw StateError('Endpoint inesperado: ${r.url}');
        }
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
        },
      );
      await tester.pumpWidget(App(dependencies: deps));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entrar com Google'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminHomeScreen), findsOneWidget);
      expect(find.byType(ApiAdminScreen), findsNothing);
      if (failInitially) {
        expect(
            find.text('Erro no servidor. Tente novamente em alguns instantes.'),
            findsWidgets);
        expect(find.widgetWithText(CartaoMetrica, 'Total'), findsNothing);
        await tester.tap(find.text('Professores').last);
        await tester.pumpAndSettle();
        expect(find.text('Nenhum professor cadastrado'), findsNothing);
        expect(
            find.text('Erro no servidor. Tente novamente em alguns instantes.'),
            findsOneWidget);
        fail = false;
        await tester.pump(const Duration(seconds: 15));
        await tester.pumpAndSettle();
        expect(find.text('Professora'), findsOneWidget);
        await tester.tap(find.text('Visão geral').last);
        await tester.pumpAndSettle();
      }
      final total = find.widgetWithText(CartaoMetrica, 'Total');
      expect(
          find.descendant(of: total, matching: find.text('3')), findsOneWidget);
      await tester.tap(find.text('Denúncias').last);
      await tester.pumpAndSettle();
      expect(
          find.text('Denúncias registradas. Julgamento ainda não disponível.'),
          findsOneWidget);
      expect(find.text('Nada pendente'), findsOneWidget);
      await tester.tap(find.text('Professores').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'inexistente');
      await tester.pumpAndSettle();
      expect(find.text('Nada encontrado'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '0012345');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Professora'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminProfessorMetricasScreen), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('2d 0h'), findsOneWidget);
      expect(find.text('Software'), findsOneWidget);
      expect(
          find.descendant(
              of: find.widgetWithText(CartaoMetrica, 'Atribuídas'),
              matching: find.text('2')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.widgetWithText(CartaoMetrica, 'Devolvidas'),
              matching: find.text('—')),
          findsOneWidget);
      expect(find.text('Desativar perfil'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Demanda entregue'), 300);
      await tester.pumpAndSettle();
      expect(find.text('Demanda entregue'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, 1800));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(900, 1800);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Demandantes').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Associação API'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminDemandanteDetalhesScreen), findsOneWidget);
      expect(find.text('12345678000100'), findsOneWidget);
      expect(find.text('Rua Um'), findsOneWidget);
      expect(find.text('Advertir'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Visão geral').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Sair'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      await tester.tap(find.text('Entrar com Google'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminHomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      final count = requests.length;
      await tester.pump(const Duration(seconds: 30));
      expect(requests.length, count);
    });
  }
}
