import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../app/app_dependencies.dart';
import '../../../core/widgets/recurso_indisponivel.dart';
import '../../../core/exceptions/app_exception.dart';
import '../../../core/models/anexo.dart';
import '../../../core/models/demanda.dart';
import '../../../core/models/professor.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/repositories/demanda_repository.dart';
import '../../../core/repositories/denuncia_repository.dart';
import '../../../core/repositories/usuario_repository.dart';
import '../../chat/abrir_chat_demanda.dart';
import '../providers/acao_demanda_provider.dart';
import '../widgets/anexos_visualizacao.dart';
import '../widgets/demanda_detalhe_widgets.dart';
import '../widgets/denunciar_demanda_dialog.dart';
import '../widgets/status_badge.dart';
import 'entrega_demanda_screen.dart';

/// Visão de detalhes da demanda para o PROFESSOR, com a barra de ações do
/// ciclo de vida (UC09 marcar análise · UC10 rejeitar · UC11 assumir ·
/// UC12 concluir). As ações disponíveis derivam do status + propriedade da
/// demanda; o estado em tempo real vem do stream do repositório.
class DemandaDetalhesProfessorScreen extends StatefulWidget {
  final String demandaId;

  const DemandaDetalhesProfessorScreen({super.key, required this.demandaId});

  @override
  State<DemandaDetalhesProfessorScreen> createState() =>
      _DemandaDetalhesProfessorScreenState();
}

class _DemandaDetalhesProfessorScreenState
    extends State<DemandaDetalhesProfessorScreen> {
  DemandaRepository get _repository => context.read<DemandaRepository>();
  DenunciaRepository get _denunciaRepository =>
      context.read<DenunciaRepository>();
  UsuarioRepository get _usuarioRepository => context.read<UsuarioRepository>();

  /// `null` enquanto a checagem não voltou — o botão só aparece depois, para
  /// não oferecer "denunciar" a quem já denunciou e receber um erro no clique.
  bool? _jaDenunciou;
  bool _denunciando = false;

  @override
  void initState() {
    super.initState();
    _verificarDenuncia();
  }

  Future<void> _verificarDenuncia() async {
    if (context.read<AppDependencies>().usaApi) return;
    final prof = context.read<AuthProvider>().usuario;
    if (prof is! Professor) return;
    final ja = await _denunciaRepository.jaDenunciou(
      demandaId: widget.demandaId,
      professorId: prof.id,
    );
    if (mounted) setState(() => _jaDenunciou = ja);
  }

  Professor? get _professor {
    final u = context.read<AuthProvider>().usuario;
    return u is Professor ? u : null;
  }

  void _feedback(String msg, Color cor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: cor),
    );
  }

  bool _exigeProfessorAtivo() {
    final prof = _professor;
    if (prof == null) {
      _feedback(
          'Apenas professores podem executar esta ação.', AppColors.error);
      return false;
    }
    if (!prof.ativo) {
      // UC04 R01: professor inativo não assume/analisa demandas.
      _feedback(
        'Seu perfil está inativo. Procure a administração do campus.',
        AppColors.error,
      );
      return false;
    }
    return true;
  }

  Future<void> _marcarAnalise(Demanda d) async {
    if (!_exigeProfessorAtivo()) return;
    final prof = _professor!;
    final acao = context.read<AcaoDemandaProvider>();
    final ok = await acao.marcarParaAnalise(
      demandaId: d.id,
      professorId: prof.id,
      professorNome: prof.nome,
    );
    if (ok) {
      _feedback(
        'Demanda em análise. Você tem 24h para assumir ou ela volta à prateleira.',
        AppColors.success,
      );
    } else if (acao.erro != null) {
      _feedback(acao.erro!, AppColors.error);
    }
  }

  Future<void> _rejeitar(Demanda d) async {
    final prof = _professor;
    if (prof == null) return;
    final acao = context.read<AcaoDemandaProvider>();
    final ok = await acao.rejeitar(demandaId: d.id, professorId: prof.id);
    if (ok) {
      _feedback('Demanda devolvida à prateleira.', AppColors.success);
      if (mounted) Navigator.of(context).pop();
    } else if (acao.erro != null) {
      _feedback(acao.erro!, AppColors.error);
    }
  }

  Future<void> _assumir(Demanda d) async {
    if (!_exigeProfessorAtivo()) return;
    final prof = _professor!;
    final acao = context.read<AcaoDemandaProvider>();
    final ok = await acao.assumir(demandaId: d.id, professorId: prof.id);
    if (ok) {
      _feedback(
        'Demanda assumida! O demandante foi notificado.',
        AppColors.success,
      );
    } else if (acao.erro != null) {
      _feedback(acao.erro!, AppColors.error);
    }
  }

  /// UC-admin — denúncia de demanda pelo professor.
  ///
  /// Os uids dos admins são buscados na hora porque a notificação precisa de
  /// id, e admins entram na plataforma ao longo do tempo. A falha dessa busca
  /// não impede a denúncia: a fila do painel é lida do Firestore de qualquer
  /// forma, a notificação é só o atalho.
  Future<void> _denunciar(Demanda d) async {
    final prof = _professor;
    if (prof == null || _denunciando) return;

    final dados = await DenunciarDemandaDialog.mostrar(
      context,
      tituloDemanda: d.titulo,
    );
    if (dados == null || !mounted) return;

    setState(() => _denunciando = true);
    try {
      final adminIds = context.read<AppDependencies>().usaApi
          ? <String>{}
          : await _usuarioRepository.buscarAdminIds();
      await _denunciaRepository.denunciar(
        demanda: d,
        professorId: prof.id,
        professorNome: prof.nome,
        motivo: dados.motivo,
        descricao: dados.descricao,
        adminIds: adminIds,
      );
      if (!mounted) return;
      setState(() => _jaDenunciou = true);
      _feedback(
        'Denúncia enviada. A administração vai analisar.',
        AppColors.success,
      );
    } on AppException catch (e) {
      _feedback(e.message, AppColors.error);
    } catch (_) {
      _feedback('Não foi possível registrar a denúncia.', AppColors.error);
    } finally {
      if (mounted) setState(() => _denunciando = false);
    }
  }

  void _abrirChat(Demanda d) {
    abrirChatDaDemanda(context, d.id);
  }

  Future<void> _concluir(Demanda d) async {
    final prof = _professor;
    if (prof == null) return;
    final concluiu = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EntregaDemandaScreen(demanda: d, professorId: prof.id),
      ),
    );
    if (concluiu == true) {
      _feedback('Entrega registrada. Demanda concluída!', AppColors.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<Demanda?>(
          stream: _repository.observar(widget.demandaId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final demanda = snap.data;
            if (demanda == null) {
              return _erro('Demanda não encontrada');
            }
            return _buildConteudo(demanda);
          },
        ),
      ),
    );
  }

  Widget _erro(String msg) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(msg),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Voltar'),
            ),
          ],
        ),
      );

  Widget _buildConteudo(Demanda demanda) {
    final prof = _professor;
    final souResponsavel = prof != null && demanda.professorId == prof.id;

    return Column(
      children: [
        const DetalheHeader(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      demanda.titulo,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _data(demanda.criadoEm),
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                demanda.demandanteNome,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ChipTipoDemandante(tipo: demanda.demandanteTipo.label),
                  const Spacer(),
                  StatusBadge(status: demanda.status),
                ],
              ),
              const SizedBox(height: 24),
              ..._blocosContexto(demanda, souResponsavel),
              SecaoTexto(titulo: 'Descrição', conteudo: demanda.descricao),
              const SizedBox(height: 24),
              SecaoTexto(
                titulo: 'Público-alvo',
                conteudo: '• ${demanda.publicoAlvo}',
              ),
              const SizedBox(height: 24),
              SecaoTexto(
                  titulo: 'Impacto da Demanda', conteudo: demanda.impacto),
              if (demanda.descricaoSolucao != null) ...[
                const SizedBox(height: 24),
                SecaoTexto(
                  titulo: 'Solução entregue',
                  conteudo: demanda.descricaoSolucao!,
                ),
              ],
              if (!context.read<AppDependencies>().usaApi &&
                  _podeConversar(demanda, souResponsavel)) ...[
                const SizedBox(height: 24),
                _botaoConversa(demanda),
              ],
              const SizedBox(height: 24),
              if (context.read<AppDependencies>().usaApi)
                const RecursoIndisponivel('Anexos')
              else
                StreamBuilder<List<Anexo>>(
                  stream: _repository.listarAnexos(demanda.id),
                  builder: (context, s) {
                    if (s.connectionState == ConnectionState.waiting &&
                        !s.hasData) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    return AnexosVisualizacao(anexos: s.data ?? const []);
                  },
                ),
              const SizedBox(height: 24),
              _linkDenuncia(demanda),
            ],
          ),
        ),
        _barraAcoes(demanda, souResponsavel),
      ],
    );
  }

  /// O chat existe a partir do momento em que a demanda é assumida (UC11 R03)
  /// e permanece legível depois da entrega — por isso `concluida` também conta.
  bool _podeConversar(Demanda d, bool souResponsavel) =>
      souResponsavel &&
      (d.status == StatusDemanda.emProducao ||
          d.status == StatusDemanda.concluida);

  Widget _botaoConversa(Demanda d) {
    return OutlinedButton.icon(
      onPressed: () => _abrirChat(d),
      icon: const Icon(Icons.chat_bubble_outline, size: 20),
      label: const Text('Conversar com o demandante'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// Denunciar é uma ação rara e de peso: fica no fim do conteúdo, discreta,
  /// e não disputa espaço com as ações do ciclo de vida na barra inferior.
  Widget _linkDenuncia(Demanda d) {
    if (_jaDenunciou == null && !context.read<AppDependencies>().usaApi) {
      return const SizedBox.shrink();
    }

    if (_jaDenunciou == true) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.flag, size: 16, color: Colors.grey.shade500),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Você denunciou esta demanda. A administração está avaliando.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
        ],
      );
    }

    return Center(
      child: TextButton.icon(
        onPressed: _denunciando ? null : () => _denunciar(d),
        icon: _denunciando
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.flag_outlined, size: 18),
        label: const Text('Denunciar esta demanda'),
        style: TextButton.styleFrom(foregroundColor: AppColors.error),
      ),
    );
  }

  /// Avisos contextuais de acordo com o estado/posse.
  List<Widget> _blocosContexto(Demanda d, bool souResponsavel) {
    final blocos = <Widget>[];

    if (d.status == StatusDemanda.emAnalise &&
        souResponsavel &&
        d.analiseExpiraEm != null) {
      blocos.add(BlocoInfo(
        cor: Colors.orange.shade800,
        icone: Icons.timer_outlined,
        titulo: 'Em análise por você',
        conteudo:
            'Assuma até ${_dataHora(d.analiseExpiraEm!)} ou a demanda volta '
            'automaticamente para a prateleira.',
      ));
    } else if (d.status == StatusDemanda.emProducao && !souResponsavel) {
      blocos.add(BlocoInfo(
        cor: Colors.blue.shade700,
        icone: Icons.engineering_outlined,
        titulo: 'Em produção',
        conteudo:
            'Esta demanda já está sendo desenvolvida por ${d.professorNome ?? "outro professor"}.',
      ));
    } else if (d.status == StatusDemanda.concluida) {
      blocos.add(BlocoInfo(
        cor: AppColors.success,
        icone: Icons.check_circle_outline,
        titulo: 'Concluída',
        conteudo: d.concluidaEm != null
            ? 'Entregue em ${_dataHora(d.concluidaEm!)}.'
            : 'Demanda entregue.',
      ));
    }

    if (blocos.isEmpty) return const [];
    return [...blocos, const SizedBox(height: 24)];
  }

  /// Barra inferior de ações. Some quando não há ação aplicável ao estado/posse.
  Widget _barraAcoes(Demanda d, bool souResponsavel) {
    final acoes = _acoesPara(d, souResponsavel);
    if (acoes.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Consumer<AcaoDemandaProvider>(
        builder: (context, acao, _) {
          final processando = acao.processando(d.id);
          return Row(
            children: [
              for (var i = 0; i < acoes.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                // Largura igual para todos os botões — evita que o "Rejeitar"
                // fique estreito demais e trunque ("R...") em telas pequenas.
                Expanded(child: acoes[i].build(processando)),
              ],
            ],
          );
        },
      ),
    );
  }

  List<_Acao> _acoesPara(Demanda d, bool souResponsavel) {
    if (d.status == StatusDemanda.cadastrada) {
      return [
        _Acao(
          rotulo: 'Marcar para análise',
          icone: Icons.search,
          onTap: () => _marcarAnalise(d),
        ),
      ];
    }
    if (d.status == StatusDemanda.emAnalise && souResponsavel) {
      return [
        _Acao(
          rotulo: 'Rejeitar',
          icone: Icons.close,
          tipo: _TipoBotao.perigoOutline,
          onTap: () => _rejeitar(d),
        ),
        _Acao(
          rotulo: 'Assumir',
          icone: Icons.check,
          onTap: () => _assumir(d),
        ),
      ];
    }
    if (d.status == StatusDemanda.emProducao && souResponsavel) {
      return [
        _Acao(
          rotulo: 'Marcar como concluída',
          icone: Icons.flag_outlined,
          onTap: () => _concluir(d),
        ),
      ];
    }
    return const [];
  }

  String _data(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _dataHora(DateTime d) =>
      '${_data(d)} às ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

enum _TipoBotao { primario, perigoOutline }

/// Descreve um botão de ação da barra inferior.
/// Descreve um botão de ação da barra inferior.
class _Acao {
  final String rotulo;
  final IconData icone;
  final VoidCallback onTap;
  final _TipoBotao tipo;

  const _Acao({
    required this.rotulo,
    required this.icone,
    required this.onTap,
    this.tipo = _TipoBotao.primario,
  });

  Widget build(bool processando) {
    final bool perigo = tipo == _TipoBotao.perigoOutline;
    final Widget conteudo = processando
        ? SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: perigo ? AppColors.error : Colors.white,
            ),
          )
        // FittedBox encolhe ícone + rótulo proporcionalmente quando o botão
        // é estreito, em vez de truncar ("R...") ou quebrar linha. Garante
        // legibilidade em qualquer largura de tela.
        : FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icone, size: 18),
                const SizedBox(width: 8),
                Text(rotulo, maxLines: 1, softWrap: false),
              ],
            ),
          );

    if (perigo) {
      return OutlinedButton(
        onPressed: processando ? null : onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: const BorderSide(color: AppColors.error),
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: conteudo,
      );
    }

    return ElevatedButton(
      onPressed: processando ? null : onTap,
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: conteudo,
    );
  }
}
