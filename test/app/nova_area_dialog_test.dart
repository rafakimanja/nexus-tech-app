import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexus_tech/core/api/api_client.dart';
import 'package:nexus_tech/core/models/area_selecionada.dart';
import 'package:nexus_tech/core/repositories/api/area_repository.dart';
import 'package:nexus_tech/core/repositories/api/usuario_repository.dart';
import 'package:nexus_tech/core/repositories/area_repository.dart';
import 'package:nexus_tech/features/auth/providers/cadastro_provider.dart';
import 'package:nexus_tech/features/auth/widgets/nova_area_dialog.dart';

http.Response json(dynamic value, [int status = 200]) =>
    http.Response(jsonEncode(value), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  for (final tipo in TipoArea.values) {
    testWidgets('cria área $tipo com feedback e sem duplicar POST',
        (tester) async {
      final response = Completer<http.Response>();
      final requests = <http.Request>[];
      final api =
          ApiClient('https://example.test', client: MockClient((r) async {
        requests.add(r);
        expect(r.headers['Authorization'], 'Bearer jwt');
        expect(r.url.path, '/areas/');
        if (r.method == 'GET') return json([]);
        expect(jsonDecode(r.body), {'name': 'Nova Área'});
        return response.future;
      }))
            ..setToken('jwt');
      final cadastro = CadastroProvider(
        usuarioRepository: ApiUsuarioRepository(api),
        areaRepository: ApiAreaRepository(api),
      );
      AreaSelecionada? result;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        return Scaffold(
            body: TextButton(
          onPressed: () async {
            result = await showDialog<AreaSelecionada>(
              context: context,
              builder: (_) => NovaAreaDialog(
                  tipo: tipo, criadoPorId: '2', cadastro: cadastro),
            );
          },
          child: const Text('Nova'),
        ));
      })));
      await tester.tap(find.text('Nova'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  nova área  ');
      await tester.tap(find.text('Adicionar'));
      await tester.pump();
      expect(find.text('Salvando…'), findsOneWidget);
      expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'Salvando…'))
              .onPressed,
          isNull);
      response.complete(json({'areaID': 31}, 201));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(result?.id, '31');
      expect(result?.nome, 'Nova Área');
      expect(requests.where((r) => r.method == 'POST').length, 1);
      expect(requests.length, 2); // Sem GET adicional após a confirmação.
      final areas = tipo == TipoArea.tecnica
          ? cadastro.areasTecnicas
          : cadastro.areasInteresse;
      expect(areas.single.id, '31');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      cadastro.dispose();
      api.dispose();
    });
  }

  testWidgets(
      'valida nome, mantém erro de permissão e permite tentar novamente',
      (tester) async {
    var allowed = false;
    var writes = 0;
    final api = ApiClient('https://example.test', client: MockClient((r) async {
      if (r.method == 'GET') return json([]);
      writes++;
      return allowed ? json({'areaID': 32}, 201) : json({}, 403);
    }))
      ..setToken('jwt');
    final cadastro = CadastroProvider(
      usuarioRepository: ApiUsuarioRepository(api),
      areaRepository: ApiAreaRepository(api),
    );
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showDialog<AreaSelecionada>(
                            context: context,
                            builder: (_) => NovaAreaDialog(
                                tipo: TipoArea.tecnica,
                                criadoPorId: '2',
                                cadastro: cadastro),
                          ),
                      child: const Text('Nova')),
                ))));
    await tester.tap(find.text('Nova'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();
    expect(find.text('Informe o nome da área.'), findsOneWidget);
    expect(writes, 0);
    await tester.enterText(find.byType(TextField), 'Robótica');
    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();
    expect(find.text('Você não tem permissão para realizar esta ação.'),
        findsOneWidget);
    expect(find.text('Robótica'), findsOneWidget);
    allowed = true;
    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(cadastro.erro, isNull);
    expect(cadastro.areasTecnicas.single.id, '32');
    await tester.pumpWidget(const SizedBox());
    cadastro.dispose();
    api.dispose();
  });

  test('reutiliza área existente normalizando espaços e caixa', () async {
    final api = ApiClient('https://example.test', client: MockClient((r) async {
      expect(r.method, 'GET');
      return json([
        {'id': 7, 'name': 'Inteligência Artificial'}
      ]);
    }))
      ..setToken('jwt');
    final area = await ApiAreaRepository(api).criarSeNaoExiste(
      tipo: TipoArea.interesse,
      nomeBruto: ' inteligência   ARTIFICIAL ',
      criadoPorId: '2',
    );
    expect(area.id, '7');
    api.dispose();
  });
}
