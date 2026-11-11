import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:nexus_tech/core/providers/auth_provider.dart';
import 'package:nexus_tech/core/repositories/denuncia_repository.dart';
import 'package:nexus_tech/core/repositories/demanda_repository.dart';
import 'package:nexus_tech/core/repositories/api/denuncia_repository.dart';
import 'package:nexus_tech/core/repositories/api/demanda_repository.dart';
import 'package:nexus_tech/core/repositories/api/usuario_repository.dart';
import 'package:nexus_tech/core/services/api_auth_service.dart';
import 'package:nexus_tech/features/admin/screens/api_denuncia_detalhes_screen.dart';
import '../core/repositories/api_backend_test.dart' as f;
import '../core/repositories/report_judgment_test.dart' as fixtures;

void main() {
  for (final scenario in [
    'procedente',
    'improcedente',
    'conflito',
    'falha',
    'professor'
  ]) {
    testWidgets('detalhes e julgamento: $scenario', (tester) async {
      tester.view.physicalSize = const Size(1100, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final user = {
        ...f.session(),
        'role': scenario == 'professor' ? 'professor' : 'admin'
      };
      var status = scenario == 'professor' ? 'procedente' : 'pendente';
      var patches = 0;
      final pending = Completer<http.Response>();
      final api = f.client((r) {
        if (r.url.path == '/login/v2')
          return f.json({
            'access_token': 'jwt',
            'token_type': 'Bearer',
            'expires_at':
                DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
            'user': user,
          });
        if (r.url.path == '/me') return f.json({'user': user});
        if (r.method == 'PATCH') {
          patches++;
          return pending.future;
        }
        if (r.url.path == '/reports/7')
          return f.json(fixtures.report(status: status));
        if (r.url.path == '/demands/42') return f.json(f.demand());
        if (r.url.path == '/teachers/2') return f.json(f.teacher());
        throw StateError('Consulta inesperada: ${r.url}');
      });
      final auth = ApiAuthService(api,
          googleToken: () async => 'google', googleSignOut: () async {});
      addTearDown(auth.dispose);
      await auth.signInWithGoogle();
      await tester.pumpWidget(MultiProvider(providers: [
        Provider<DenunciaRepository>.value(value: ApiDenunciaRepository(api)),
        Provider<DemandaRepository>.value(value: ApiDemandaRepository(api)),
        ChangeNotifierProvider(
            create: (_) => AuthProvider(
                authService: auth,
                usuarioRepository: ApiUsuarioRepository(api))),
      ], child: const MaterialApp(home: ApiDenunciaDetalhesScreen(id: '7'))));
      await tester.pumpAndSettle();
      expect(find.text('Agenda comunitária'), findsOneWidget);
      if (scenario == 'professor') {
        expect(find.text('Parecer registrado'), findsOneWidget);
        expect(find.text('Julgar procedente'), findsNothing);
        expect(find.text('Julgar improcedente'), findsNothing);
      } else {
        await tester.tap(find.text(scenario == 'improcedente'
            ? 'Julgar improcedente'
            : 'Julgar procedente'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirmar julgamento'));
        await tester.pumpAndSettle();
        expect(find.text('Informe a justificativa.'), findsOneWidget);
        expect(patches, 0);
        await tester.enterText(
            find.byType(TextFormField), 'Parecer registrado');
        await tester.tap(find.text('Confirmar julgamento'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(patches, 1);
        expect(
            tester
                .widget<FilledButton>(
                    find.widgetWithText(FilledButton, 'Julgar procedente'))
                .onPressed,
            isNull);
        if (scenario == 'falha') {
          pending.complete(f.json({}, 500));
        } else if (scenario == 'conflito') {
          status = 'improcedente';
          pending.complete(f.json({}, 409));
        } else {
          status = scenario;
          pending.complete(f.json(
              fixtures.report(status: status, strike: status == 'procedente')));
        }
        await tester.pumpAndSettle();
        expect(patches, 1);
        if (scenario == 'falha') {
          expect(
              find.text(
                  'Erro no servidor. Tente novamente em alguns instantes.'),
              findsOneWidget);
          expect(find.text('Situação: Pendente'), findsOneWidget);
          expect(
              tester
                  .widget<FilledButton>(
                      find.widgetWithText(FilledButton, 'Julgar procedente'))
                  .onPressed,
              isNotNull);
        } else {
          expect(find.text('Parecer registrado'), findsOneWidget);
          expect(find.text('Julgar procedente'), findsNothing);
          if (scenario == 'conflito') {
            expect(
                find.text(
                    'Esta denúncia já foi julgada por outro administrador.'),
                findsOneWidget);
          }
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      api.dispose();
      await tester.pumpAndSettle();
    });
  }
}
