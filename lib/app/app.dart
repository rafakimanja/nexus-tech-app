import 'app_dependencies.dart';
import '../core/repositories/admin_repository.dart';
import '../core/repositories/anexo_repository.dart';
import '../core/repositories/area_repository.dart';
import '../core/repositories/chat_repository.dart';
import '../core/repositories/demanda_repository.dart';
import '../core/repositories/denuncia_repository.dart';
import '../core/repositories/foto_perfil_repository.dart';
import '../core/repositories/notificacao_repository.dart';
import '../core/repositories/usuario_repository.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/perfil/providers/perfil_provider.dart';
import '../core/providers/auth_provider.dart';
import '../features/auth/providers/cadastro_provider.dart';
import '../features/demandas/providers/acao_demanda_provider.dart';
import '../features/demandas/providers/demanda_form_provider.dart';
import '../features/demandas/providers/demandas_provider.dart';
import '../features/demandas/providers/professor_demandas_provider.dart';
import '../features/admin/providers/admin_provider.dart';
import '../features/chat/providers/chats_provider.dart';
import '../features/notificacoes/providers/notificacoes_provider.dart';
import 'router.dart';
import '../features/notificacoes/widgets/push_navigation.dart';
import 'theme.dart';

class App extends StatelessWidget {
  final AppDependencies dependencies;
  const App({super.key, required this.dependencies});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppDependencies>(
            lazy: false,
            create: (_) => dependencies,
            dispose: (_, value) => value.dispose()),
        Provider<AdminRepository>.value(value: dependencies.admin),
        Provider<AnexoRepository>.value(value: dependencies.anexo),
        Provider<AreaRepository>.value(value: dependencies.area),
        Provider<ChatRepository>.value(value: dependencies.chat),
        Provider<DemandaRepository>.value(value: dependencies.demanda),
        Provider<DenunciaRepository>.value(value: dependencies.denuncia),
        Provider<FotoPerfilRepository>.value(value: dependencies.fotoPerfil),
        Provider<NotificacaoRepository>.value(value: dependencies.notificacao),
        Provider<UsuarioRepository>.value(value: dependencies.usuario),
        ChangeNotifierProvider(
            create: (_) => AuthProvider(
                authService: dependencies.auth,
                usuarioRepository: dependencies.usuario)),
      ],
      child: Consumer<AuthProvider>(
          builder: (context, auth, _) => MultiProvider(
                key: ValueKey(
                    (auth.sessao?.id, auth.status == AuthStatus.bloqueado)),
                providers: [
                  ChangeNotifierProvider(
                      create: (_) => CadastroProvider(
                          usuarioRepository: dependencies.usuario,
                          areaRepository: dependencies.area)),
                  ChangeNotifierProvider(
                      create: (_) =>
                          DemandasProvider(repository: dependencies.demanda)),
                  ChangeNotifierProvider(
                      create: (_) => DemandaFormProvider(
                          demandaRepository: dependencies.demanda,
                          anexoRepository: dependencies.anexo)),
                  // Sprint 3 — área do professor (UC08–UC12)
                  ChangeNotifierProvider(
                      create: (_) => ProfessorDemandasProvider(
                          repository: dependencies.demanda)),
                  ChangeNotifierProvider(
                      create: (_) => AcaoDemandaProvider(
                          demandaRepository: dependencies.demanda,
                          anexoRepository: dependencies.anexo)),
                  ChangeNotifierProvider(
                      create: (_) => PerfilProvider(
                          usuarioRepository: dependencies.usuario,
                          fotoRepository: dependencies.fotoPerfil)),
                  // Sprint 4 — comunicação, avisos e moderação (UC11 R03, UC-admin).
                  // Globais porque alimentam badges que precisam existir em qualquer
                  // aba, não só na tela que os consome.
                  ChangeNotifierProvider(
                      create: (_) => NotificacoesProvider(
                          repository: dependencies.notificacao)),
                  ChangeNotifierProvider(
                      create: (_) =>
                          ChatsProvider(repository: dependencies.chat)),
                  ChangeNotifierProvider(
                      create: (_) => AdminProvider(
                          suportaModeracao: !dependencies.usaApi,
                          adminRepository: dependencies.admin,
                          denunciaRepository: dependencies.denuncia)),
                ],
                child: MaterialApp(
                  title: 'Nexus Tech',
                  theme: AppTheme.light,
                  debugShowCheckedModeBanner: false,
                  home: const PushNavigation(child: AppRouter()),
                ),
              )),
    );
  }
}
