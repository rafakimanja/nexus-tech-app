import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_tech/app/app.dart';
import 'package:nexus_tech/app/app_dependencies.dart';
import 'package:nexus_tech/features/admin/screens/admin_home_screen.dart';
import 'package:nexus_tech/features/auth/screens/cadastro_demandante_screen.dart';
import 'package:nexus_tech/features/auth/screens/cadastro_professor_screen.dart';
import 'package:nexus_tech/features/auth/screens/conta_bloqueada_screen.dart';
import 'package:nexus_tech/features/auth/screens/login_screen.dart';
import 'package:nexus_tech/features/chat/screens/chat_screen.dart';
import 'package:nexus_tech/features/demandas/screens/demanda_detalhes_screen.dart';
import 'package:nexus_tech/features/demandas/screens/minhas_demandas_screen.dart';
import 'package:nexus_tech/features/demandas/screens/professor_home_screen.dart';

void main() {
  testWidgets('inicia sem Firebase e navega por todos os perfis simulados',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final deps = AppDependencies.memory();
    await tester.pumpWidget(App(dependencies: deps));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Demonstração • dados temporários'), findsOneWidget);
    await tester.tap(find.text('Entrar na demonstração'));
    await tester.pumpAndSettle();
    expect(find.byType(MinhasDemandasScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    for (final caso in <(String, Type)>[
      ('2', ProfessorHomeScreen),
      ('3', AdminHomeScreen),
      ('5', CadastroDemandanteScreen),
      ('6', CadastroProfessorScreen),
      ('7', ContaBloqueadaScreen),
      ('8', ContaBloqueadaScreen),
    ]) {
      await deps.auth.signOut();
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      await deps.entrarDemonstracao!(caso.$1);
      debugPrint('Verificando conta ${caso.$1}');
      for (var i = 0; i < 10; i++) { await tester.pump(const Duration(milliseconds: 100)); }
      for (final element in find.byType(CircularProgressIndicator, skipOffstage: false).evaluate()) {
        var nivel = 0;
        element.visitAncestorElements((e) { debugPrint('spinner: ${e.widget.runtimeType}'); return ++nivel < 12; });
      }
      await tester.pumpAndSettle();
      expect(find.byType(caso.$2), findsOneWidget, reason: 'Conta ${caso.$1}');
      expect(tester.takeException(), isNull, reason: 'Conta ${caso.$1}');
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
      'abre conversa pelo ID próprio e logout descarta a navegação antiga',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final deps = AppDependencies.memory();
    await tester.pumpWidget(App(dependencies: deps));
    await tester.pumpAndSettle();
    await deps.entrarDemonstracao!('1');
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(MinhasDemandasScreen));
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const DemandaDetalhesScreen(demandaId: '103')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Conversar com Professor 2'));
    await tester.tap(find.text('Conversar com Professor 2'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(tester.widget<ChatScreen>(find.byType(ChatScreen)).chatId, '9103');
    expect(tester.takeException(), isNull);
    await deps.auth.signOut();
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(ChatScreen), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
