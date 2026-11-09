import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../app/app_dependencies.dart';
import '../../../core/providers/auth_provider.dart';
import '../../notificacoes/widgets/sino_notificacoes.dart';
import '../../chat/providers/chats_provider.dart';
import '../../chat/screens/chats_screen.dart';
import '../../notificacoes/providers/notificacoes_provider.dart';
import '../../perfil/screens/perfil_screen.dart';
import '../providers/demanda_form_provider.dart';
import '../providers/demandas_provider.dart';
import '../widgets/demanda_card.dart';
import '../widgets/filtros_bottom_sheet.dart';
import 'demanda_detalhes_screen.dart';
import 'professor_home_screen.dart' show comBadge;
import 'demanda_form_screen.dart';

class MinhasDemandasScreen extends StatefulWidget {
  const MinhasDemandasScreen({super.key});

  @override
  State<MinhasDemandasScreen> createState() => _MinhasDemandasScreenState();
}

class _MinhasDemandasScreenState extends State<MinhasDemandasScreen> {
  final _buscaController = TextEditingController();

  /// 0 = lista de demandas · 1 = conversas · 2 = perfil. O menu inferior
  /// alterna entre eles mantendo-se sempre visível (mesmo padrão da área do
  /// professor).
  int _aba = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final id = context.read<AuthProvider>().usuario?.id;
      if (id == null) return;
      context.read<DemandasProvider>().observar(id);
      // Conversas e notificações são globais: os badges precisam existir em
      // qualquer aba, não só quando a respectiva tela está aberta.
      if (!context.read<AppDependencies>().usaApi) {
        context.read<ChatsProvider>().observar(id);
      }
      context.read<NotificacoesProvider>().observar(id);
    });
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  void _abrirFiltros() {
    final demandas = context.read<DemandasProvider>();
    FiltrosBottomSheet.mostrar(
      context,
      statusInicial: demandas.filtroStatus,
      periodoInicial: demandas.filtroPeriodo,
      onAplicar: (status, periodo) {
        demandas.aplicarFiltros(status: status, periodo: periodo);
      },
      onLimpar: demandas.limparFiltros,
    );
  }

  void _abrirDetalhes(String id) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DemandaDetalhesScreen(demandaId: id)),
    );
  }

  void _abrirNovaDemanda() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const DemandaFormScreen(modo: DemandaFormModo.criar),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _aba,
          children: [
            Column(
              children: [
                _buildHeader(),
                _buildBuscaEFiltro(),
                Expanded(child: _buildLista()),
              ],
            ),
            const ChatsScreen(),
            const PerfilScreen(comoAba: true),
          ],
        ),
      ),
      // FAB de "nova demanda" só faz sentido na aba de demandas.
      floatingActionButton: _aba == 0
          ? FloatingActionButton(
              backgroundColor: AppColors.primary,
              onPressed: _abrirNovaDemanda,
              child: const Icon(Icons.add, color: Colors.white, size: 32),
            )
          : null,
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset('assets/images/logo.png', width: 56, height: 56),
              const SizedBox(width: 12),
              const Text(
                'Nexus Tech',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const Spacer(),
              const SinoNotificacoes(),
              IconButton(
                icon: const Icon(Icons.logout, color: AppColors.primary),
                tooltip: 'Sair',
                onPressed: () => context.read<AuthProvider>().sair(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Minhas\nDemandas',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBuscaEFiltro() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _buscaController,
              decoration: InputDecoration(
                hintText: 'Buscar demandas por nome...',
                prefixIcon:
                    const Icon(Icons.search, color: AppColors.textSecondary),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              onChanged: (txt) =>
                  context.read<DemandasProvider>().atualizarBusca(txt),
            ),
          ),
          const SizedBox(width: 12),
          Consumer<DemandasProvider>(
            builder: (_, p, __) => _BotaoFiltro(
              filtrosAtivos: p.filtrosAtivos,
              onTap: _abrirFiltros,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLista() {
    return Consumer<DemandasProvider>(
      builder: (context, provider, _) {
        if (provider.carregando && provider.demandas.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.erro != null) {
          return _Estado(
            icone: Icons.error_outline,
            titulo: 'Erro ao carregar',
            mensagem: provider.erro!,
            acao: ElevatedButton(
              onPressed: () {
                final id = context.read<AuthProvider>().usuario?.id;
                if (id != null) provider.observar(id);
              },
              child: const Text('Tentar novamente'),
            ),
          );
        }

        final demandas = provider.demandas;
        if (demandas.isEmpty) {
          final temFiltro =
              provider.temFiltrosAtivos || provider.busca.isNotEmpty;
          return _Estado(
            icone: temFiltro ? Icons.filter_list_off : Icons.inbox_outlined,
            titulo: temFiltro
                ? 'Nenhuma demanda encontrada'
                : 'Você ainda não criou demandas',
            mensagem: temFiltro
                ? 'Tente ajustar os filtros ou a busca'
                : 'Toque no botão + para criar sua primeira demanda',
            acao: temFiltro
                ? TextButton(
                    onPressed: provider.limparFiltros,
                    child: const Text('Limpar filtros'),
                  )
                : null,
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
          itemCount: demandas.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => DemandaCard(
            demanda: demandas[i],
            onTap: () => _abrirDetalhes(demandas[i].id),
          ),
        );
      },
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      // SafeArea(top:false) reserva o espaço da barra de navegação do sistema
      // (gestos/botões), evitando que os ícones fiquem por baixo dela em
      // tablets e aparelhos com gesture bar. Adapta-se a qualquer tela.
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                tooltip: 'Minhas demandas',
                icon: Icon(
                  _aba == 0 ? Icons.home : Icons.home_outlined,
                  color:
                      _aba == 0 ? AppColors.primary : AppColors.textSecondary,
                  size: 28,
                ),
                onPressed: () => setState(() => _aba = 0),
              ),
              IconButton(
                tooltip: 'Conversas',
                icon: comBadge(
                  Icon(
                    _aba == 1 ? Icons.chat_bubble : Icons.chat_bubble_outline,
                    color:
                        _aba == 1 ? AppColors.primary : AppColors.textSecondary,
                    size: 28,
                  ),
                  context.watch<ChatsProvider>().totalNaoLidas,
                ),
                onPressed: () => setState(() => _aba = 1),
              ),
              IconButton(
                tooltip: 'Perfil',
                icon: Icon(
                  _aba == 2 ? Icons.person : Icons.person_outline,
                  color:
                      _aba == 2 ? AppColors.primary : AppColors.textSecondary,
                  size: 28,
                ),
                onPressed: () => setState(() => _aba = 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BotaoFiltro extends StatelessWidget {
  final int filtrosAtivos;
  final VoidCallback onTap;

  const _BotaoFiltro({required this.filtrosAtivos, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Material(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                ),
              ),
              child: const Icon(
                Icons.filter_alt_outlined,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
        if (filtrosAtivos > 0)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              child: Text(
                '$filtrosAtivos',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

class _Estado extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String mensagem;
  final Widget? acao;

  const _Estado({
    required this.icone,
    required this.titulo,
    required this.mensagem,
    this.acao,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icone, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              mensagem,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            if (acao != null) ...[
              const SizedBox(height: 16),
              acao!,
            ],
          ],
        ),
      ),
    );
  }
}
