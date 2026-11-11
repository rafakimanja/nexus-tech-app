import 'package:nexus_tech/core/providers/auth_provider.dart';
import 'package:nexus_tech/core/services/api_auth_service.dart';
import 'package:nexus_tech/core/repositories/api/usuario_repository.dart';
import 'package:nexus_tech/core/repositories/denuncia_repository.dart';
import 'package:nexus_tech/core/repositories/api/denuncia_repository.dart';
import 'package:nexus_tech/core/repositories/api/notificacao_repository.dart';
import 'package:nexus_tech/features/notificacoes/providers/notificacoes_provider.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:nexus_tech/core/api/api_client.dart';
import 'package:nexus_tech/core/repositories/admin_repository.dart';
import 'package:nexus_tech/core/repositories/api/admin_repository.dart';
import 'package:nexus_tech/features/admin/screens/api_admin_screen.dart';
import 'package:nexus_tech/app/theme.dart';
import '../core/repositories/api_backend_test.dart' as fixtures;

void main() {
  testWidgets('admin pode alternar e revisitar todas as abas', (tester) async {
    final api = ApiClient('https://example.test', client: MockClient((r) async {
      return http.Response(jsonEncode([]), 200);
    }))
      ..setToken('jwt');
    final auth = ApiAuthService(api,
        googleToken: () async => null, googleSignOut: () async {});
    addTearDown(auth.dispose);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<AdminRepository>.value(value: ApiAdminRepository(api)),
        Provider<DenunciaRepository>.value(value: ApiDenunciaRepository(api)),
        ChangeNotifierProvider(
            create: (_) => NotificacoesProvider(
                repository: ApiNotificacaoRepository(api))),
        ChangeNotifierProvider(
            create: (_) => AuthProvider(
                authService: auth, usuarioRepository: ApiUsuarioRepository(api))),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const ApiAdminScreen()),
    ));
    await tester.pumpAndSettle();
    for (final tab in [
      'Professores',
      'Demandantes',
      'Denúncias',
      'Demandas',
      'Professores'
    ]) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Nenhum registro encontrado.'), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox());
    api.dispose();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'admin renderiza registros, recupera erro e mantém polling entre abas',
      (tester) async {
    var fail = true;
    var reads = 0;
    final api = ApiClient('https://example.test',
        pollInterval: const Duration(seconds: 15),
        client: MockClient((r) async {
      if (r.url.path == '/teachers/') {
        reads++;
        if (fail) return http.Response('{}', 500);
        return fixtures.json([fixtures.teacher()]);
      }
      if (r.url.path == '/applicants/') {
        return fixtures.json([
          {
            'id': 1,
            'name': 'Associação',
            'email': 'ong@example.test',
            'created_at': '2026-11-04T12:00:00Z',
            'phone': '11999999999',
            'type': 'ong',
            'cpf_cnpj': '12345678000100',
            'address': 'Rua Um',
            'strikes': 0,
            'blocked': false,
          }
        ]);
      }
      if (r.url.path == '/reports') return fixtures.json([]);
      expect(r.url.path, '/demands/');
      return fixtures.json([fixtures.demand()]);
    }))
      ..setToken('jwt');
    final auth = ApiAuthService(api,
        googleToken: () async => null, googleSignOut: () async {});
    addTearDown(auth.dispose);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<AdminRepository>.value(value: ApiAdminRepository(api)),
        Provider<DenunciaRepository>.value(value: ApiDenunciaRepository(api)),
        ChangeNotifierProvider(
            create: (_) => NotificacoesProvider(
                repository: ApiNotificacaoRepository(api))),
        ChangeNotifierProvider(
            create: (_) => AuthProvider(
                authService: auth, usuarioRepository: ApiUsuarioRepository(api))),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const ApiAdminScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Agenda comunitária'), findsOneWidget);
    await tester.tap(find.text('Professores'));
    await tester.pumpAndSettle();
    expect(find.text('Erro no servidor. Tente novamente em alguns instantes.'),
        findsOneWidget);
    fail = false;
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(find.text('Professora'), findsOneWidget);
    await tester.tap(find.text('Demandantes'));
    await tester.pumpAndSettle();
    expect(find.text('Associação'), findsOneWidget);
    await tester.tap(find.text('Demandas'));
    await tester.pumpAndSettle();
    expect(find.text('Agenda comunitária'), findsOneWidget);
    await tester.tap(find.text('Professores'));
    await tester.pumpAndSettle();
    expect(find.text('Professora'), findsOneWidget);
    expect(reads, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
    expect(reads, 2);
    api.dispose();
    await tester.pumpAndSettle();
  });
}
