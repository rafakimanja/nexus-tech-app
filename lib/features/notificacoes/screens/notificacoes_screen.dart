import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../app/app_dependencies.dart';
import '../../admin/screens/api_denuncia_detalhes_screen.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/notificacao.dart';
import '../../../core/providers/auth_provider.dart';
import '../../admin/providers/admin_provider.dart';
import '../../admin/screens/admin_denuncia_detalhes_screen.dart';
import '../../chat/screens/chat_screen.dart';
import '../../demandas/screens/demanda_detalhes_professor_screen.dart';
import '../../demandas/screens/demanda_detalhes_screen.dart';
import '../../demandas/widgets/estado_lista.dart';
import '../providers/notificacoes_provider.dart';

/// Central de notificações in-app.
///
/// Tocar numa notificação faz duas coisas: marca como lida e leva ao lugar
/// onde a ação acontece. O destino sai de [TipoNotificacao.destino] e é
/// traduzido em rota conforme o papel do usuário — a mesma notificação de
/// demanda abre a tela do demandante ou a do professor.
class NotificacoesScreen extends StatelessWidget {
  const NotificacoesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificacoesProvider>();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.primary,
        title: const Text(
          'Notificações',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (provider.temNaoLidas)
            TextButton.icon(
              onPressed: provider.marcarTodasComoLidas,
              icon: const Icon(Icons.done_all, size: 18),
              label: const Text('Marcar todas'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
              ),
            ),
        ],
      ),
      body: SafeArea(
          child: Column(children: [
        if (provider.erro != null && provider.notificacoes.isNotEmpty)
          Padding(
              padding: const EdgeInsets.all(12),
              child: Text(provider.erro!,
                  style: const TextStyle(color: AppColors.error))),
        Expanded(child: _corpo(context, provider)),
      ])),
    );
  }

  Widget _corpo(BuildContext context, NotificacoesProvider provider) {
    if (provider.carregando && provider.notificacoes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.erro != null && provider.notificacoes.isEmpty) {
      return EstadoLista(
        icone: Icons.error_outline,
        titulo: 'Erro ao carregar',
        mensagem: provider.erro!,
      );
    }

    if (provider.notificacoes.isEmpty) {
      return const EstadoLista(
        icone: Icons.notifications_none,
        titulo: 'Nenhuma notificação',
        mensagem: 'Avisos sobre suas demandas, mensagens e decisões da '
            'administração aparecem aqui.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: provider.notificacoes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final n = provider.notificacoes[i];
        return _CartaoNotificacao(
          notificacao: n,
          onTap: () => abrirNotificacao(context, n),
        );
      },
    );
  }

  static Future<void> abrirNotificacao(
      BuildContext context, Notificacao n) async {
    final navigator = Navigator.of(context);
    final auth = context.read<AuthProvider>();
    final admin = context.read<AdminProvider>();
    await context.read<NotificacoesProvider>().marcarComoLida(n);

    if (!context.mounted) return;
    final role = auth.usuario?.role;

    // A API autoriza o professor autor a consultar o parecer, mesmo quando
    // a demanda foi cancelada. O demandante recebe um recurso "demand".
    if (context.read<AppDependencies>().usaApi &&
        n.denunciaId != null &&
        (role == UserRole.administrador || role == UserRole.professor)) {
      navigator.push(MaterialPageRoute<void>(
          builder: (_) => ApiDenunciaDetalhesScreen(id: n.denunciaId!)));
      return;
    }

    switch (n.tipo.destino) {
      case DestinoNotificacao.chat:
        final chatId = n.chatId ?? n.demandaId;
        if (chatId == null) return;
        navigator.push(MaterialPageRoute<void>(
          builder: (_) => ChatScreen(chatId: chatId),
        ));

      case DestinoNotificacao.demanda:
        final demandaId = n.demandaId;
        if (demandaId == null) return;
        navigator.push(MaterialPageRoute<void>(
          builder: (_) => role == UserRole.professor
              ? DemandaDetalhesProfessorScreen(demandaId: demandaId)
              : DemandaDetalhesScreen(demandaId: demandaId),
        ));

      case DestinoNotificacao.denuncia:
        // Só o admin tem tela de julgamento. Para o professor que denunciou,
        // o parecer já está no corpo da notificação; levá-lo à demanda é o
        // próximo passo útil.
        if (role == UserRole.administrador) {
          if (context.read<AppDependencies>().usaApi && n.denunciaId != null) {
            navigator.push(MaterialPageRoute<void>(
                builder: (_) => ApiDenunciaDetalhesScreen(id: n.denunciaId!)));
            return;
          }
          final denuncia =
              n.denunciaId == null ? null : admin.denunciaPorId(n.denunciaId!);
          if (denuncia == null) return;
          navigator.push(MaterialPageRoute<void>(
            builder: (_) => AdminDenunciaDetalhesScreen(denuncia: denuncia),
          ));
          return;
        }
        final demandaId = n.demandaId;
        if (demandaId == null) return;
        navigator.push(MaterialPageRoute<void>(
          builder: (_) => role == UserRole.professor
              ? DemandaDetalhesProfessorScreen(demandaId: demandaId)
              : DemandaDetalhesScreen(demandaId: demandaId),
        ));

      case DestinoNotificacao.perfil:
      case DestinoNotificacao.nenhum:
        // Avisos sobre a própria conta (strike, banimento, ativação) são
        // informativos: o efeito já está aplicado no perfil e no roteamento.
        break;
    }
  }
}

class _CartaoNotificacao extends StatelessWidget {
  final Notificacao notificacao;
  final VoidCallback onTap;

  const _CartaoNotificacao({required this.notificacao, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final n = notificacao;
    final cor = n.tipo.cor;

    return Material(
      color: n.lida ? Colors.white : cor.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: n.lida ? Colors.grey.shade200 : cor.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(n.tipo.icone, size: 20, color: cor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            n.titulo,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight:
                                  n.lida ? FontWeight.w600 : FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (!n.lida)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 8, top: 4),
                            decoration: const BoxDecoration(
                              color: AppColors.error,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      n.corpo,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      formatarQuando(n.criadoEm),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Data relativa curta ("agora", "há 5 min", "ontem", "12/03/2026").
/// Compartilhada com a lista de conversas — o mesmo vocabulário temporal nas
/// duas telas evita que o usuário tenha que interpretar dois formatos.
String formatarQuando(DateTime quando) {
  final diff = DateTime.now().difference(quando);

  if (diff.inMinutes < 1) return 'agora';
  if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'há ${diff.inHours}h';
  if (diff.inDays == 1) return 'ontem';
  if (diff.inDays < 7) return 'há ${diff.inDays} dias';

  final d = quando;
  return '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}
