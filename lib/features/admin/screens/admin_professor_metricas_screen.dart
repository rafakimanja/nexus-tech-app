import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../core/models/demanda.dart';
import '../../../core/models/metricas_professor.dart';
import '../../../core/models/professor.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../demandas/widgets/demanda_detalhe_widgets.dart';
import '../../demandas/widgets/status_badge.dart';
import '../providers/admin_provider.dart';
import '../widgets/admin_widgets.dart';

/// Métricas de um professor + ação de ligar/desligar o perfil.
///
/// As duas coisas ficam na mesma tela de propósito: desligar um professor é
/// uma decisão que depende do que ele tem em mãos. O aviso de carga em aberto
/// aparece antes da confirmação justamente por isso.
class AdminProfessorMetricasScreen extends StatefulWidget {
  final Professor professor;

  const AdminProfessorMetricasScreen({super.key, required this.professor});

  @override
  State<AdminProfessorMetricasScreen> createState() =>
      _AdminProfessorMetricasScreenState();
}

class _AdminProfessorMetricasScreenState
    extends State<AdminProfessorMetricasScreen> {
  AdminRepository get _repository => context.read<AdminRepository>();

  late final Stream<MetricasProfessor> _metricas =
      _repository.observarMetricas(widget.professor.id);
  late final Stream<List<Demanda>> _demandas =
      _repository.observarDemandasDoProfessor(widget.professor.id);

  /// A instância mais recente do professor.
  ///
  /// Vem do stream global do painel (`AdminProvider`) em vez do parâmetro,
  /// para a tela refletir o resultado da própria ação de ligar/desligar sem
  /// precisar voltar. Cai no parâmetro se a lista ainda não carregou.
  Professor get _professor {
    final lista = context.watch<AdminProvider>().professores;
    for (final p in lista) {
      if (p.id == widget.professor.id) return p;
    }
    return widget.professor;
  }

  void _feedback(String msg, Color cor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: cor),
    );
  }

  Future<void> _alternarAtivo(MetricasProfessor? metricas) async {
    final professor = _professor;
    final admin = context.read<AuthProvider>().usuario;
    if (admin == null) return;

    final provider = context.read<AdminProvider>();

    if (professor.ativo) {
      final emAberto = metricas?.emAberto ?? 0;
      final motivo = await DialogMotivo.mostrar(
        context,
        titulo: 'Desativar ${professor.nome}',
        descricao: emAberto > 0
            ? 'Este professor tem $emAberto demanda(s) em aberto. Desativar '
                'não devolve essas demandas à prateleira — ele apenas deixa de '
                'poder atuar na plataforma. Avalie se elas precisam ser '
                'redistribuídas antes.'
            : 'O professor deixará de acessar a prateleira e de atuar em '
                'demandas. Ele será notificado com o motivo informado.',
        rotuloConfirmar: 'Desativar',
        hint: 'Motivo da desativação (o professor verá este texto).',
        corConfirmar: AppColors.error,
      );
      if (motivo == null || !mounted) return;

      final ok = await provider.definirProfessorAtivo(
        professor: professor,
        ativo: false,
        adminId: admin.id,
        adminNome: admin.nome,
        motivo: motivo,
      );
      _feedback(
        ok
            ? 'Perfil desativado. O professor foi notificado.'
            : provider.erro ?? 'Não foi possível desativar o perfil.',
        ok ? AppColors.success : AppColors.error,
      );
      return;
    }

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Reativar professor'),
        content: Text(
          '${professor.nome} voltará a acessar a prateleira e a atuar em '
          'demandas. O professor será notificado.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              minimumSize: const Size(120, 44),
            ),
            child: const Text('Reativar'),
          ),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    final ok = await provider.definirProfessorAtivo(
      professor: professor,
      ativo: true,
      adminId: admin.id,
      adminNome: admin.nome,
    );
    _feedback(
      ok
          ? 'Perfil reativado. O professor foi notificado.'
          : provider.erro ?? 'Não foi possível reativar o perfil.',
      ok ? AppColors.success : AppColors.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final professor = _professor;
    final processando =
        context.watch<AdminProvider>().processando(professor.id);

    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<MetricasProfessor>(
          stream: _metricas,
          builder: (context, snap) {
            final metricas = snap.data;

            return Column(
              children: [
                const DetalheHeader(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    children: [
                      _identificacao(professor),
                      const SizedBox(height: 24),
                      if (!professor.ativo) ...[
                        BlocoInfo(
                          cor: AppColors.error,
                          icone: Icons.person_off_outlined,
                          titulo: 'Perfil desativado',
                          conteudo: professor.motivoDesativacao ??
                              'Este professor não pode atuar na plataforma.',
                        ),
                        const SizedBox(height: 24),
                      ],
                      if (snap.hasError)
                        AvisoAdmin(mensagemErroAdmin(snap.error))
                      else
                        _blocoMetricas(metricas),
                      const SizedBox(height: 28),
                      _areas(professor),
                      const SizedBox(height: 28),
                      _listaDemandas(),
                    ],
                  ),
                ),
                if (context.watch<AdminProvider>().suportaModeracao)
                  _barraAcao(professor, metricas, processando)
                else
                  const AvisoAdmin(
                      'Ativação e desativação de professores ainda não estão disponíveis no servidor.'),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _identificacao(Professor p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                p.nome,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Etiqueta(
              texto: p.ativo ? 'Ativo' : 'Desativado',
              cor: p.ativo ? AppColors.success : Colors.grey.shade600,
              icone: p.ativo ? Icons.check_circle_outline : Icons.block,
            ),
          ],
        ),
        const SizedBox(height: 16),
        LinhaDetalhe(rotulo: 'E-mail', valor: p.email),
        LinhaDetalhe(rotulo: 'SIAPE', valor: p.siape),
        LinhaDetalhe(rotulo: 'Cadastrado em', valor: _data(p.criadoEm)),
        if (p.desativadoEm != null)
          LinhaDetalhe(
            rotulo: 'Desativado em',
            valor: _data(p.desativadoEm!),
          ),
      ],
    );
  }

  Widget _blocoMetricas(MetricasProfessor? m) {
    if (m == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final taxa = m.taxaConclusao;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Desempenho',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 12),
        GradeMetricas(
          cartoes: [
            CartaoMetrica(
              valor: '${m.totalAtribuidas}',
              label: 'Atribuídas',
              icone: Icons.inbox_outlined,
              cor: AppColors.primary,
            ),
            CartaoMetrica(
              valor: '${m.emAnalise}',
              label: 'Em análise',
              icone: StatusDemanda.emAnalise.icone,
              cor: StatusDemanda.emAnalise.cor,
            ),
            CartaoMetrica(
              valor: '${m.emProducao}',
              label: 'Em produção',
              icone: StatusDemanda.emProducao.icone,
              cor: StatusDemanda.emProducao.cor,
            ),
            CartaoMetrica(
              valor: '${m.concluidas}',
              label: 'Concluídas',
              icone: StatusDemanda.concluida.icone,
              cor: StatusDemanda.concluida.cor,
            ),
            CartaoMetrica(
              valor: m.historicoDevolucoesDisponivel ? '${m.devolvidas}' : '—',
              label: 'Devolvidas',
              icone: Icons.undo,
              cor: Colors.amber.shade800,
            ),
            CartaoMetrica(
              valor: taxa == null ? '—' : '${(taxa * 100).round()}%',
              label: 'Taxa de conclusão',
              icone: Icons.percent,
              cor: AppColors.success,
            ),
          ],
        ),
        if (!m.historicoDevolucoesDisponivel)
          const AvisoAdmin(
              'O servidor não fornece o histórico de demandas devolvidas.'),
        const SizedBox(height: 10),
        GradeMetricas(
          colunas: 2,
          cartoes: [
            CartaoMetrica(
              valor: formatarDuracao(m.tempoMedioEntrega),
              label: 'Tempo médio de entrega',
              icone: Icons.timer_outlined,
              cor: Colors.blue.shade700,
            ),
            CartaoMetrica(
              valor: formatarDuracao(m.tempoMedioAnalise),
              label: 'Tempo médio de decisão',
              icone: Icons.speed_outlined,
              cor: Colors.indigo.shade600,
            ),
          ],
        ),
        if (m.ultimaAtividade != null) ...[
          const SizedBox(height: 12),
          Text(
            'Última atividade em ${_data(m.ultimaAtividade!)}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ],
    );
  }

  Widget _areas(Professor p) {
    Widget grupo(String titulo, List<String> itens) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            if (itens.isEmpty)
              Text(
                'Nenhuma informada',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in itens)
                    Etiqueta(texto: a, cor: AppColors.primary),
                ],
              ),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Áreas',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 12),
        grupo('Técnicas', p.areasTecnicas.map((a) => a.nome).toList()),
        const SizedBox(height: 16),
        grupo('De interesse', p.areasInteresse.map((a) => a.nome).toList()),
      ],
    );
  }

  Widget _listaDemandas() {
    return SecaoPersistenteAdmin(
        child: StreamBuilder<List<Demanda>>(
      stream: _demandas,
      builder: (context, snap) {
        if (snap.hasError) return AvisoAdmin(mensagemErroAdmin(snap.error));
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final demandas = snap.data ?? const <Demanda>[];
        if (demandas.isEmpty) {
          return const AvisoAdmin('Nenhuma demanda atribuída.');
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Demandas atribuídas',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 12),
            for (final d in demandas)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          d.titulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusBadge(status: d.status, fontSize: 10),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ));
  }

  Widget _barraAcao(
    Professor p,
    MetricasProfessor? metricas,
    bool processando,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: p.ativo
            ? OutlinedButton.icon(
                onPressed: processando ? null : () => _alternarAtivo(metricas),
                icon: processando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_off_outlined, size: 20),
                label: const Text('Desativar perfil'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              )
            : ElevatedButton.icon(
                onPressed: processando ? null : () => _alternarAtivo(metricas),
                icon: processando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.person_outline, size: 20),
                label: const Text('Reativar perfil'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
      ),
    );
  }

  String _data(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}
