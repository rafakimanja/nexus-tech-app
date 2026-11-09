import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/texto_botao.dart';
import '../../../app/theme.dart';
import '../../../app/app_dependencies.dart';
import '../../../core/widgets/recurso_indisponivel.dart';
import '../../../core/models/anexo.dart';
import '../../../core/models/demanda.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/repositories/demanda_repository.dart';
import '../../chat/abrir_chat_demanda.dart';
import '../providers/demanda_form_provider.dart';
import '../widgets/anexos_visualizacao.dart';
import '../widgets/cancelar_demanda_dialog.dart';
import '../widgets/status_badge.dart';
import 'demanda_form_screen.dart';

class DemandaDetalhesScreen extends StatefulWidget {
  final String demandaId;

  const DemandaDetalhesScreen({super.key, required this.demandaId});

  @override
  State<DemandaDetalhesScreen> createState() => _DemandaDetalhesScreenState();
}

class _DemandaDetalhesScreenState extends State<DemandaDetalhesScreen> {
  DemandaRepository get _repository => context.read<DemandaRepository>();

  Future<void> _editar(Demanda demanda) async {
    final atualizou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DemandaFormScreen(
          modo: DemandaFormModo.editar,
          demandaExistente: demanda,
        ),
      ),
    );
    if (atualizou == true && mounted) {
      // Stream do repositório vai atualizar sozinho. Nada a fazer aqui.
    }
  }

  Future<void> _cancelar(Demanda demanda) async {
    final motivo = await CancelarDemandaDialog.mostrar(context);
    if (motivo == null || !mounted) return;

    final auth = context.read<AuthProvider>();
    final form = context.read<DemandaFormProvider>();
    final id = auth.usuario?.id;
    if (id == null) return;

    final ok = await form.cancelar(
      demandaId: demanda.id,
      autorId: id,
      motivo: motivo,
    );

    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Demanda cancelada'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.of(context).pop();
    } else if (form.erro != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(form.erro!),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  /// Cria uma nova demanda pré-preenchida a partir de uma cancelada.
  /// A demanda original NÃO é alterada no conteúdo — preserva histórico.
  /// Anexos não são copiados; o demandante pode reanexar se quiser.
  /// O repositório marca a original com `republicadaComoId` na mesma
  /// transação para impedir republicação dupla.
  void _republicar(Demanda demanda) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DemandaFormScreen(
          modo: DemandaFormModo.criar,
          valoresIniciais: demanda,
        ),
      ),
    );
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
    final podeEditar = demanda.status.podeEditarDemandante;
    final podeCancelar = demanda.status.podeCancelarDemandante;

    return Column(
      children: [
        _header(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // Título + ações
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
                    _formatarData(demanda.criadoEm),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      demanda.demandanteNome,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  if (podeCancelar)
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.error),
                      tooltip: 'Cancelar demanda',
                      onPressed: () => _cancelar(demanda),
                    ),
                  if (podeEditar)
                    IconButton(
                      icon: const Icon(Icons.edit_outlined,
                          color: AppColors.success),
                      tooltip: 'Editar demanda',
                      onPressed: () => _editar(demanda),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _ChipTipoDemandante(tipo: demanda.demandanteTipo.label),
                  const Spacer(),
                  StatusBadge(status: demanda.status),
                ],
              ),
              const SizedBox(height: 24),

              if (demanda.status == StatusDemanda.cancelada) ...[
                if (demanda.motivoCancelamento != null) ...[
                  _BlocoInfo(
                    cor: AppColors.error,
                    titulo: 'Motivo do cancelamento',
                    conteudo: demanda.motivoCancelamento!,
                  ),
                  const SizedBox(height: 16),
                ],
                // Botão de republicar OU aviso de já-republicada — mutuamente
                // exclusivos. O campo `republicadaComoId` é setado de forma
                // atômica junto com a criação da nova demanda (ver
                // DemandaRepository.criar), então este check é fonte
                // confiável de verdade.
                if (context.read<AppDependencies>().usaApi)
                  const RecursoIndisponivel('Republicação')
                else if (demanda.republicadaComoId == null)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _republicar(demanda),
                      child: const TextoBotao(
                        ('Republicar como nova demanda'),
                        icone: Icons.replay,
                      ),
                    ),
                  )
                else
                  _BlocoInfo(
                    cor: AppColors.textSecondary,
                    titulo: 'Já republicada',
                    conteudo:
                        'Você já republicou esta demanda. A nova versão está '
                        'em "Minhas Demandas".',
                  ),
                const SizedBox(height: 24),
              ],

              _Secao(titulo: 'Descrição', conteudo: demanda.descricao),
              const SizedBox(height: 24),
              _Secao(
                titulo: 'Público-alvo',
                conteudo: '• ${demanda.publicoAlvo}',
              ),
              const SizedBox(height: 24),
              _Secao(titulo: 'Impacto da Demanda', conteudo: demanda.impacto),

              if (demanda.descricaoSolucao != null) ...[
                const SizedBox(height: 24),
                _Secao(
                  titulo: 'Solução entregue',
                  conteudo: demanda.descricaoSolucao!,
                ),
              ],

              // O canal com o professor nasce quando a demanda é aceita
              // (UC11 R03) e continua legível depois da entrega.
              if (!context.read<AppDependencies>().usaApi && demanda.professorId != null &&
                  (demanda.status == StatusDemanda.emProducao ||
                      demanda.status == StatusDemanda.concluida)) ...[
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => abrirChatDaDemanda(context, demanda.id),
                  icon: const Icon(Icons.chat_bubble_outline, size: 20),
                  label: Text(
                    'Conversar com ${demanda.professorNome ?? "o professor"}',
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),
              if (context.read<AppDependencies>().usaApi)
                const RecursoIndisponivel('Anexos')
              else StreamBuilder<List<Anexo>>(
                stream: _repository.listarAnexos(demanda.id),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting &&
                      !snap.hasData) {
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
                  return AnexosVisualizacao(anexos: snap.data ?? const []);
                },
              ),

              if (demanda.professorNome != null) ...[
                const SizedBox(height: 24),
                _Secao(
                  titulo: 'Professor responsável',
                  conteudo: demanda.professorNome!,
                ),
              ],

              if (demanda.atualizadoEm != null) ...[
                const SizedBox(height: 24),
                Text(
                  'Atualizada em ${_formatarDataHora(demanda.atualizadoEm!)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _header() {
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
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.arrow_back, color: AppColors.primary),
                  SizedBox(width: 8),
                  Text(
                    'Voltar',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatarData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _formatarDataHora(DateTime d) =>
      '${_formatarData(d)} às ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _ChipTipoDemandante extends StatelessWidget {
  final String tipo;
  const _ChipTipoDemandante({required this.tipo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.success,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        tipo,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _Secao extends StatelessWidget {
  final String titulo;
  final String conteudo;
  const _Secao({required this.titulo, required this.conteudo});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            conteudo,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade800,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _BlocoInfo extends StatelessWidget {
  final Color cor;
  final String titulo;
  final String conteudo;

  const _BlocoInfo({
    required this.cor,
    required this.titulo,
    required this.conteudo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: cor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            conteudo,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
