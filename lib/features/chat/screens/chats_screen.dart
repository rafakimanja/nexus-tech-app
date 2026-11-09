import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../app/app_dependencies.dart';
import '../../../core/widgets/recurso_indisponivel.dart';
import '../../../core/models/chat.dart';
import '../../../core/providers/auth_provider.dart';
import '../../demandas/widgets/estado_lista.dart';
import '../../notificacoes/screens/notificacoes_screen.dart'
    show formatarQuando;
import '../../notificacoes/widgets/sino_notificacoes.dart';
import '../providers/chats_provider.dart';
import 'chat_screen.dart';

/// Lista de conversas do usuário. Usada como aba tanto pelo demandante quanto
/// pelo professor — a única diferença entre os dois é qual nome aparece do
/// outro lado, o que o próprio [Chat] resolve.
class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (context.read<AppDependencies>().usaApi) {
      return const Center(child: RecursoIndisponivel('Conversas'));
    }
    final id = context.watch<AuthProvider>().usuario?.id;
    final provider = context.watch<ChatsProvider>();

    return Column(
      children: [
        _cabecalho(context),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: BarraBusca(
            hint: 'Buscar por demanda ou pessoa...',
            onChanged: context.read<ChatsProvider>().atualizarBusca,
          ),
        ),
        Expanded(child: _lista(context, provider, id)),
      ],
    );
  }

  Widget _cabecalho(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 12, 0),
      child: Row(
        children: [
          Image.asset('assets/images/logo.png', width: 44, height: 44),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Conversas',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
          const SinoNotificacoes(),
        ],
      ),
    );
  }

  Widget _lista(BuildContext context, ChatsProvider provider, String? id) {
    if (provider.carregando && provider.chats.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.erro != null && provider.chats.isEmpty) {
      return EstadoLista(
        icone: Icons.error_outline,
        titulo: 'Erro ao carregar',
        mensagem: provider.erro!,
        acao: ElevatedButton(
          onPressed: () {
            if (id != null) provider.observar(id);
          },
          child: const Text('Tentar novamente'),
        ),
      );
    }

    if (provider.chats.isEmpty) {
      final buscando = provider.busca.isNotEmpty;
      return EstadoLista(
        icone: buscando ? Icons.search_off : Icons.forum_outlined,
        titulo: buscando ? 'Nada encontrado' : 'Nenhuma conversa ainda',
        mensagem: buscando
            ? 'Nenhuma conversa corresponde a "${provider.busca}".'
            : 'A conversa com o professor é aberta automaticamente assim que '
                'uma demanda é aceita.',
      );
    }

    if (id == null) return const SizedBox.shrink();

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: provider.chats.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final chat = provider.chats[i];
        return _CartaoChat(
          chat: chat,
          id: id,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ChatScreen(chatId: chat.id),
            ),
          ),
        );
      },
    );
  }
}

class _CartaoChat extends StatelessWidget {
  final Chat chat;
  final String id;
  final VoidCallback onTap;

  const _CartaoChat({
    required this.chat,
    required this.id,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final naoLidas = chat.naoLidasDe(id);
    final temNaoLidas = naoLidas > 0;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: temNaoLidas
                  ? AppColors.primary.withValues(alpha: 0.4)
                  : Colors.grey.shade200,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: chat.ativo
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : Colors.grey.shade200,
                child: Text(
                  _iniciais(chat.outroNome(id)),
                  style: TextStyle(
                    color:
                        chat.ativo ? AppColors.primary : Colors.grey.shade600,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
                            chat.outroNome(id),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: temNaoLidas
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (chat.ultimaMensagemEm != null)
                          Text(
                            formatarQuando(chat.ultimaMensagemEm!),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      chat.tituloDemanda,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.primary.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (!chat.ativo) ...[
                          Icon(Icons.lock_outline,
                              size: 13, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            chat.ultimaMensagem ?? 'Conversa iniciada',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: temNaoLidas
                                  ? AppColors.textPrimary
                                  : Colors.grey.shade600,
                              fontWeight: temNaoLidas
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (temNaoLidas) ...[
                          const SizedBox(width: 8),
                          ContadorBadge(valor: naoLidas),
                        ],
                      ],
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

  static String _iniciais(String nome) {
    final partes = nome.trim().split(RegExp(r'\s+'));
    if (partes.isEmpty || partes.first.isEmpty) return '?';
    if (partes.length == 1) return partes.first[0].toUpperCase();
    return (partes.first[0] + partes.last[0]).toUpperCase();
  }
}
