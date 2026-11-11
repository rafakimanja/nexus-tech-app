import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/demanda.dart';
import '../../../core/models/denuncia.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/repositories/demanda_repository.dart';
import '../../../core/repositories/denuncia_repository.dart';
import '../../demandas/widgets/demanda_detalhe_widgets.dart';
import '../../demandas/widgets/status_badge.dart';
import '../providers/admin_provider.dart';
import '../widgets/admin_widgets.dart';

/// Tela de julgamento de uma denúncia.
///
/// Reúne num lugar só tudo que a decisão exige: o que foi alegado, o conteúdo
/// real da demanda (em tempo real — ela pode ter sido editada ou cancelada
/// desde a denúncia) e o histórico de denúncias contra o mesmo demandante. Sem
/// esse histórico o admin decidiria o terceiro strike — o que bane a conta —
/// sem saber que é o terceiro.
class AdminDenunciaDetalhesScreen extends StatefulWidget {
  final Denuncia denuncia;

  const AdminDenunciaDetalhesScreen({super.key, required this.denuncia});

  @override
  State<AdminDenunciaDetalhesScreen> createState() =>
      _AdminDenunciaDetalhesScreenState();
}

class _AdminDenunciaDetalhesScreenState
    extends State<AdminDenunciaDetalhesScreen> {
  DemandaRepository get _demandaRepository => context.read<DemandaRepository>();
  DenunciaRepository get _denunciaRepository =>
      context.read<DenunciaRepository>();

  /// A denúncia recebida por parâmetro é um retrato do momento em que a lista
  /// foi lida. Depois de julgar aqui, guardamos a versão atualizada para a
  /// tela refletir a decisão sem depender de voltar e reabrir.
  late Denuncia _denuncia = widget.denuncia;

  void _feedback(String msg, Color cor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: cor),
    );
  }

  Future<void> _julgar(bool procedente) async {
    final admin = context.read<AuthProvider>().usuario;
    if (admin == null) return;

    final parecer = await DialogMotivo.mostrar(
      context,
      titulo: procedente ? 'Julgar procedente' : 'Julgar improcedente',
      descricao: procedente
          ? 'O demandante ${_denuncia.demandanteNome} receberá uma advertência. '
              'Ao acumular ${AppConstants.strikesParaBanimento}, a conta é '
              'suspensa automaticamente.'
          : 'A denúncia será arquivada sem efeito sobre a conta do '
              'demandante. O professor que denunciou será informado.',
      rotuloConfirmar: procedente ? 'Aplicar advertência' : 'Arquivar',
      hint: 'Justifique a decisão. Este texto vai para as duas partes.',
      corConfirmar: procedente ? AppColors.error : AppColors.success,
      minimoCaracteres: 10,
    );
    if (parecer == null || !mounted) return;

    final provider = context.read<AdminProvider>();
    final resultado = await provider.julgar(
      denuncia: _denuncia,
      procedente: procedente,
      adminId: admin.id,
      adminNome: admin.nome,
      parecer: parecer,
    );

    if (!mounted) return;

    if (resultado == null) {
      _feedback(provider.erro ?? 'Não foi possível registrar a decisão.',
          AppColors.error);
      return;
    }

    setState(() {
      _denuncia = Denuncia(
        id: _denuncia.id,
        demandaId: _denuncia.demandaId,
        tituloDemanda: _denuncia.tituloDemanda,
        demandanteId: _denuncia.demandanteId,
        demandanteNome: _denuncia.demandanteNome,
        professorId: _denuncia.professorId,
        professorNome: _denuncia.professorNome,
        motivo: _denuncia.motivo,
        descricao: _denuncia.descricao,
        status: procedente
            ? StatusDenuncia.procedente
            : StatusDenuncia.improcedente,
        criadoEm: _denuncia.criadoEm,
        analisadaEm: DateTime.now(),
        analisadaPorId: admin.id,
        analisadaPorNome: admin.nome,
        parecerAdmin: parecer,
        strikeAplicado: resultado.strikeAplicado,
      );
    });

    _feedback(_mensagemResultado(resultado),
        resultado.contaBanida == true ? AppColors.error : AppColors.success);
  }

  String _mensagemResultado(ResultadoJulgamento r) {
    if (!r.procedente) return 'Denúncia arquivada como improcedente.';
    if (r.contaBanida == true) {
      return 'Advertência aplicada (${r.strikesTotais}/'
          '${AppConstants.strikesParaBanimento}). Conta suspensa.';
    }
    if (!r.strikeAplicado) {
      return 'Denúncia julgada procedente. A conta já estava suspensa.';
    }
    return 'Advertência ${r.strikesTotais} de '
        '${AppConstants.strikesParaBanimento} aplicada.';
  }

  @override
  Widget build(BuildContext context) {
    final processando =
        context.watch<AdminProvider>().processando(_denuncia.id);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const DetalheHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Denúncia',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      Etiqueta(
                        texto: _denuncia.status.label,
                        cor: _denuncia.status.cor,
                        icone: _denuncia.status.icone,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  BlocoInfo(
                    cor: _denuncia.status.cor,
                    icone: Icons.flag_outlined,
                    titulo: _denuncia.motivo.label,
                    conteudo: _denuncia.descricao,
                  ),
                  const SizedBox(height: 20),
                  LinhaDetalhe(
                      rotulo: 'Denunciante', valor: _denuncia.professorNome),
                  LinhaDetalhe(
                      rotulo: 'Denunciado', valor: _denuncia.demandanteNome),
                  LinhaDetalhe(
                    rotulo: 'Recebida em',
                    valor: _dataHora(_denuncia.criadoEm),
                  ),
                  if (_denuncia.analisadaEm != null) ...[
                    LinhaDetalhe(
                      rotulo: 'Analisada em',
                      valor: _dataHora(_denuncia.analisadaEm!),
                    ),
                    LinhaDetalhe(
                      rotulo: 'Analisada por',
                      valor: _denuncia.analisadaPorNome ?? '—',
                    ),
                  ],
                  if (_denuncia.parecerAdmin != null) ...[
                    const SizedBox(height: 12),
                    BlocoInfo(
                      cor: AppColors.primary,
                      icone: Icons.gavel_outlined,
                      titulo: 'Parecer da administração',
                      conteudo: _denuncia.parecerAdmin!,
                    ),
                  ],
                  const SizedBox(height: 28),
                  _historicoDoDemandante(),
                  const SizedBox(height: 28),
                  _demandaDenunciada(),
                ],
              ),
            ),
            if (_denuncia.pendente) _barraDecisao(processando),
          ],
        ),
      ),
    );
  }

  /// Denúncias anteriores contra o mesmo demandante — o contexto que separa
  /// "primeiro deslize" de "reincidência".
  Widget _historicoDoDemandante() {
    return StreamBuilder<List<Denuncia>>(
      stream: _denunciaRepository.observarDoDemandante(_denuncia.demandanteId),
      builder: (context, snap) {
        final todas = snap.data ?? const <Denuncia>[];
        final procedentes =
            todas.where((d) => d.status == StatusDenuncia.procedente).length;
        final pendentes = todas.where((d) => d.pendente).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Histórico do demandante',
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
                  valor: '${todas.length}',
                  label: 'Denúncias recebidas',
                  icone: Icons.flag_outlined,
                  cor: AppColors.textSecondary,
                ),
                CartaoMetrica(
                  valor: '$procedentes',
                  label: 'Procedentes',
                  icone: Icons.gavel,
                  cor: procedentes > 0 ? AppColors.error : AppColors.success,
                ),
                CartaoMetrica(
                  valor: '$pendentes',
                  label: 'Pendentes',
                  icone: Icons.hourglass_empty,
                  cor: Colors.amber.shade800,
                ),
              ],
            ),
            if (procedentes >= AppConstants.strikesParaBanimento - 1 &&
                _denuncia.pendente) ...[
              const SizedBox(height: 12),
              BlocoInfo(
                cor: AppColors.error,
                icone: Icons.warning_amber_outlined,
                titulo: 'Atenção',
                conteudo: 'Este demandante já acumula $procedentes denúncia(s) '
                    'procedente(s). Julgar esta como procedente pode suspender '
                    'a conta.',
              ),
            ],
          ],
        );
      },
    );
  }

  /// A demanda como ela está agora — pode ter sido editada ou cancelada
  /// depois da denúncia, e isso muda a decisão.
  Widget _demandaDenunciada() {
    return StreamBuilder<Demanda?>(
      stream: _demandaRepository.observar(_denuncia.demandaId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final d = snap.data;
        if (d == null) {
          return const BlocoInfo(
            cor: AppColors.textSecondary,
            icone: Icons.help_outline,
            titulo: 'Demanda indisponível',
            conteudo: 'A demanda denunciada não foi encontrada. Ela pode ter '
                'sido removida.',
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Demanda denunciada',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                StatusBadge(status: d.status),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              d.titulo,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            SecaoTexto(titulo: 'Descrição', conteudo: d.descricao),
            const SizedBox(height: 16),
            SecaoTexto(titulo: 'Público-alvo', conteudo: d.publicoAlvo),
            const SizedBox(height: 16),
            SecaoTexto(titulo: 'Impacto', conteudo: d.impacto),
          ],
        );
      },
    );
  }

  Widget _barraDecisao(bool processando) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: processando ? null : () => _julgar(false),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.success,
                side: const BorderSide(color: AppColors.success),
                minimumSize: const Size.fromHeight(52),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.thumb_up_alt_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Improcedente', maxLines: 1, softWrap: false),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: processando ? null : () => _julgar(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                minimumSize: const Size.fromHeight(52),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: processando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.gavel, size: 18),
                          SizedBox(width: 8),
                          Text('Procedente', maxLines: 1, softWrap: false),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _dataHora(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year} às '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}
