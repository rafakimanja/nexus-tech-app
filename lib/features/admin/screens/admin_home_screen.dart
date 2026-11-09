import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../notificacoes/providers/notificacoes_provider.dart';
import '../../notificacoes/widgets/sino_notificacoes.dart';
import '../providers/admin_provider.dart';
import 'admin_demandantes_screen.dart';
import 'admin_denuncias_screen.dart';
import 'admin_professores_screen.dart';
import 'admin_visao_geral_screen.dart';

/// Casca do painel administrativo.
///
/// Mesmo padrão da área do professor: [IndexedStack] mantém as quatro abas
/// vivas para preservar scroll e posição de leitura ao alternar, e os streams
/// são disparados uma única vez aqui — não em cada aba.
class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _aba = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AdminProvider>().observar();
      final id = context.read<AuthProvider>().usuario?.id;
      if (id != null) {
        context.read<NotificacoesProvider>().observar(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pendentes = context.watch<AdminProvider>().denunciasPendentes;

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _aba,
          children: const [
            AdminVisaoGeralScreen(),
            AdminDenunciasScreen(),
            AdminProfessoresScreen(),
            AdminDemandantesScreen(),
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
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard, color: AppColors.primary),
            label: 'Visão geral',
          ),
          NavigationDestination(
            // O badge na aba de denúncias é o que faz a fila não ser esquecida:
            // é a única parte do painel com trabalho pendente de verdade.
            icon: _comBadge(const Icon(Icons.flag_outlined), pendentes),
            selectedIcon: _comBadge(
              const Icon(Icons.flag, color: AppColors.primary),
              pendentes,
            ),
            label: 'Denúncias',
          ),
          const NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school, color: AppColors.primary),
            label: 'Professores',
          ),
          const NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups, color: AppColors.primary),
            label: 'Demandantes',
          ),
        ],
      ),
    );
  }

  Widget _comBadge(Widget icone, int valor) {
    if (valor <= 0) return icone;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icone,
        Positioned(right: -8, top: -4, child: ContadorBadge(valor: valor)),
      ],
    );
  }
}
