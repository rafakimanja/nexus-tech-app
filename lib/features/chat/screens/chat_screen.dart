import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/exceptions/app_exception.dart';
import '../../../core/models/chat.dart';
import '../../../core/models/enums.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/repositories/chat_repository.dart';
import '../../demandas/screens/demanda_detalhes_professor_screen.dart';
import '../../demandas/screens/demanda_detalhes_screen.dart';
import '../../demandas/widgets/estado_lista.dart';
import '../widgets/balao_mensagem.dart';

/// Conversa entre demandante e professor sobre uma demanda (UC11 R03).
///
/// Consome os streams do repositório direto, no mesmo padrão das telas de
/// detalhe de demanda: o estado desta tela é a conversa aberta, e morre com
/// ela. O que é global — lista de conversas e contador do badge — fica no
/// `ChatsProvider`.
class ChatScreen extends StatefulWidget {
  /// Identificador da conversa, obtido pelo repositório.
  final String chatId;

  const ChatScreen({super.key, required this.chatId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  ChatRepository get _repository => context.read<ChatRepository>();
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  bool _enviando = false;

  /// Quantas mensagens já estavam na tela na última rolagem automática. Rolar
  /// só quando o número cresce evita puxar o usuário para o rodapé enquanto
  /// ele lê o histórico (um rebuild qualquer não deve mexer no scroll).
  int _mensagensVistas = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _marcarLido());
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String? get _id => context.read<AuthProvider>().usuario?.id;

  void _marcarLido() {
    final id = _id;
    if (id == null) return;
    _repository.marcarComoLido(chatId: widget.chatId, id: id);
  }

  void _rolarParaOFim({bool animado = true}) {
    if (!_scroll.hasClients) return;
    final destino = _scroll.position.maxScrollExtent;
    if (animado) {
      _scroll.animateTo(
        destino,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _scroll.jumpTo(destino);
    }
  }

  Future<void> _enviar() async {
    final usuario = context.read<AuthProvider>().usuario;
    if (usuario == null || _enviando) return;

    final texto = _controller.text.trim();
    if (texto.isEmpty) return;

    setState(() => _enviando = true);
    // Limpa o campo otimisticamente: a mensagem reaparece nele se o envio
    // falhar, para o usuário não perder o que digitou.
    _controller.clear();

    try {
      await _repository.enviarMensagem(
        chatId: widget.chatId,
        autorId: usuario.id,
        autorNome: usuario.nome,
        texto: texto,
      );
    } on AppException catch (e) {
      _controller.text = texto;
      _feedback(e.message, AppColors.error);
    } catch (_) {
      _controller.text = texto;
      _feedback('Não foi possível enviar a mensagem.', AppColors.error);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _feedback(String msg, Color cor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: cor),
    );
  }

  void _abrirDemanda(Chat chat) {
    final role = context.read<AuthProvider>().usuario?.role;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => role == UserRole.professor
          ? DemandaDetalhesProfessorScreen(demandaId: chat.demandaId)
          : DemandaDetalhesScreen(demandaId: chat.demandaId),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final id = context.watch<AuthProvider>().usuario?.id;

    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<Chat?>(
          stream: _repository.observarChat(widget.chatId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final chat = snap.data;
            if (chat == null || id == null) {
              return Column(
                children: [
                  _cabecalhoSimples(),
                  const Expanded(
                    child: EstadoLista(
                      icone: Icons.chat_bubble_outline,
                      titulo: 'Conversa indisponível',
                      // Duas causas possíveis, e o usuário não tem como
                      // distinguir: falta de acesso, ou demanda assumida antes
                      // de o chat existir no app (essas não têm conversa
                      // retroativa). A mensagem cobre as duas sem culpar
                      // ninguém.
                      mensagem: 'A conversa é aberta automaticamente quando um '
                          'professor aceita a demanda. Demandas aceitas em '
                          'versões anteriores do app não têm conversa.',
                    ),
                  ),
                ],
              );
            }

            return Column(
              children: [
                _cabecalho(chat, id),
                Expanded(child: _listaMensagens(chat, id)),
                _rodape(chat),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _cabecalhoSimples() => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.primary),
              onPressed: () => Navigator.of(context).pop(),
            ),
            const Text(
              'Conversa',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      );

  Widget _cabecalho(Chat chat, String id) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.primary),
            tooltip: 'Voltar',
            onPressed: () => Navigator.of(context).pop(),
          ),
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            child: Text(
              _iniciais(chat.outroNome(id)),
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chat.outroNome(id),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  chat.tituloDemanda,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.description_outlined,
                color: AppColors.primary),
            tooltip: 'Ver demanda',
            onPressed: () => _abrirDemanda(chat),
          ),
        ],
      ),
    );
  }

  Widget _listaMensagens(Chat chat, String id) {
    return StreamBuilder<List<Mensagem>>(
      stream: _repository.observarMensagens(widget.chatId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final mensagens = snap.data ?? const <Mensagem>[];
        if (mensagens.isEmpty) {
          return const EstadoLista(
            icone: Icons.forum_outlined,
            titulo: 'Nenhuma mensagem ainda',
            mensagem: 'Envie a primeira mensagem para alinhar os detalhes '
                'da demanda.',
          );
        }

        // Chegou mensagem nova: rola para o fim e zera o contador de não lidas
        // — a conversa está aberta, então ela já foi lida de fato.
        if (mensagens.length != _mensagensVistas) {
          final primeiraCarga = _mensagensVistas == 0;
          _mensagensVistas = mensagens.length;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _rolarParaOFim(animado: !primeiraCarga);
            _marcarLido();
          });
        }

        return ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          itemCount: mensagens.length,
          itemBuilder: (context, i) {
            final m = mensagens[i];
            final anterior = i == 0 ? null : mensagens[i - 1];
            final novoDia =
                anterior == null || !_mesmoDia(anterior.enviadaEm, m.enviadaEm);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (novoDia) SeparadorDia(dia: m.enviadaEm),
                BalaoMensagem(
                  mensagem: m,
                  meu: m.autorId == id,
                  // `novoDia` já é verdadeiro quando não há mensagem anterior,
                  // então aqui `anterior` é necessariamente não-nulo.
                  agrupada: !novoDia &&
                      anterior.autorId == m.autorId &&
                      !anterior.sistema &&
                      !m.sistema,
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _rodape(Chat chat) {
    if (!chat.ativo) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          border: Border(top: BorderSide(color: Colors.grey.shade300)),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_outline, size: 18, color: Colors.grey.shade600),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Conversa encerrada. O histórico continua disponível para '
                'consulta.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 5,
              maxLength: AppConstants.maxCaracteresMensagem,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Escreva uma mensagem...',
                counterText: '',
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 2),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 52,
            height: 52,
            child: ElevatedButton(
              onPressed: _enviando ? null : _enviar,
              style: ElevatedButton.styleFrom(
                shape: const CircleBorder(),
                padding: EdgeInsets.zero,
                minimumSize: const Size.square(52),
              ),
              child: _enviando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  static bool _mesmoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _iniciais(String nome) {
    final partes = nome.trim().split(RegExp(r'\s+'));
    if (partes.isEmpty || partes.first.isEmpty) return '?';
    if (partes.length == 1) return partes.first[0].toUpperCase();
    return (partes.first[0] + partes.last[0]).toUpperCase();
  }
}
