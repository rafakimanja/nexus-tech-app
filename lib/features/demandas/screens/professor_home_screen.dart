import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../perfil/screens/perfil_screen.dart';
import '../../../app/theme.dart';
import '../../../app/app_dependencies.dart';
import '../../../core/providers/auth_provider.dart';
import '../../chat/providers/chats_provider.dart';
import '../../chat/screens/chats_screen.dart';
import '../../notificacoes/providers/notificacoes_provider.dart';
import '../../notificacoes/widgets/sino_notificacoes.dart';
import '../providers/professor_demandas_provider.dart';
import 'minhas_demandas_professor_screen.dart';
import 'prateleira_screen.dart';

/// Casca da área do professor. Mantém as abas (Prateleira, Minhas Demandas,
/// Conversas e Perfil) vivas via [IndexedStack] para preservar scroll e estado
/// ao alternar, e dispara a observação de todos os streams globais uma única
/// vez — inclusive os de conversas e notificações, que alimentam badges
/// visíveis de qualquer aba.
class ProfessorHomeScreen extends StatefulWidget {
  const ProfessorHomeScreen({super.key});

  @override
  State<ProfessorHomeScreen> createState() => _ProfessorHomeScreenState();
}

class _ProfessorHomeScreenState extends State<ProfessorHomeScreen> {
  int _aba = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final id = context.read<AuthProvider>().usuario?.id;
      if (id == null) return;
      context.read<ProfessorDemandasProvider>().observar(id);
      if (!context.read<AppDependencies>().usaApi) {
        context.read<ChatsProvider>().observar(id);
      }
      context.read<NotificacoesProvider>().observar(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final naoLidasChat = context.watch<ChatsProvider>().totalNaoLidas;

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _aba,
          children: const [
            PrateleiraScreen(),
            MinhasDemandasProfessorScreen(),
            ChatsScreen(),
            PerfilScreen(comoAba: true), // UC23 — perfil do professor
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _aba,
        onDestinationSelected: (i) => setState(() => _aba = i),
        backgroundColor: AppColors.background,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront, color: AppColors.primary),
            label: 'Prateleira',
          ),
          const NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder, color: AppColors.primary),
            label: 'Minhas Demandas',
          ),
          NavigationDestination(
            icon: comBadge(
              const Icon(Icons.chat_bubble_outline),
              naoLidasChat,
            ),
            selectedIcon: comBadge(
              const Icon(Icons.chat_bubble, color: AppColors.primary),
              naoLidasChat,
            ),
            label: 'Conversas',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: AppColors.primary),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}

/// Envolve um ícone de navegação com a pastilha de contagem quando há algo
/// pendente. Compartilhado entre as barras do professor e do demandante para
/// que o badge se comporte igual nos dois papéis.
Widget comBadge(Widget icone, int valor) {
  if (valor <= 0) return icone;
  return Stack(
    clipBehavior: Clip.none,
    children: [
      icone,
      Positioned(right: -8, top: -4, child: ContadorBadge(valor: valor)),
    ],
  );
}
