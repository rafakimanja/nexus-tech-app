import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/demandante.dart';
import '../../../core/models/denuncia.dart';
import '../../../core/repositories/denuncia_repository.dart';
import '../../demandas/widgets/demanda_detalhe_widgets.dart';
import '../../notificacoes/screens/notificacoes_screen.dart'
    show formatarQuando;
import '../providers/admin_provider.dart';
import '../widgets/admin_widgets.dart';
import 'admin_demandantes_screen.dart' show ajustarStrikesComDialogo;
import 'admin_denuncia_detalhes_screen.dart';

/// Ficha de um demandante: dados, advertências e histórico de denúncias.
///
/// O botão de suspender não é um interruptor separado: ele apenas leva as
/// advertências ao limite. Manter uma única regra ("banido = strikes >= 3")
/// evita o estado incoerente de uma conta suspensa com uma advertência só.
class AdminDemandanteDetalhesScreen extends StatefulWidget {
  final Demandante demandante;

  const AdminDemandanteDetalhesScreen({super.key, required this.demandante});

  @override
  State<AdminDemandanteDetalhesScreen> createState() =>
      _AdminDemandanteDetalhesScreenState();
}

class _AdminDemandanteDetalhesScreenState
    extends State<AdminDemandanteDetalhesScreen> {
  DenunciaRepository get _denunciaRepository =>
      context.read<DenunciaRepository>();
  late final _denuncias =
      _denunciaRepository.observarDoDemandante(widget.demandante.id);

  /// Versão viva do demandante, vinda do stream do painel — a tela reflete o
  /// efeito das próprias ações sem precisar voltar e reabrir.
  Demandante get _demandante {
    for (final d in context.watch<AdminProvider>().demandantes) {
      if (d.id == widget.demandante.id) return d;
    }
    return widget.demandante;
  }

  @override
  Widget build(BuildContext context) {
    final d = _demandante;
    final processando = context.watch<AdminProvider>().processando(d.id);

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
                      Expanded(
                        child: Text(
                          d.nome,
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
                        texto: d.banido ? 'Suspensa' : 'Ativa',
                        cor: d.banido ? AppColors.error : AppColors.success,
                        icone:
                            d.banido ? Icons.block : Icons.check_circle_outline,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (d.banido) ...[
                    BlocoInfo(
                      cor: AppColors.error,
                      icone: Icons.block,
                      titulo: 'Conta suspensa'
                          '${d.banidoEm != null ? " em ${_data(d.banidoEm!)}" : ""}',
                      conteudo: d.motivoBanimento ??
                          'Acúmulo de advertências por denúncias procedentes.',
                    ),
                    const SizedBox(height: 20),
                  ],
                  _advertencias(d),
                  const SizedBox(height: 24),
                  const Text(
                    'Dados cadastrais',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  LinhaDetalhe(rotulo: 'E-mail', valor: d.email),
                  LinhaDetalhe(rotulo: 'Tipo', valor: d.tipo.label),
                  LinhaDetalhe(rotulo: 'CPF/CNPJ', valor: d.cpfCnpj),
                  LinhaDetalhe(rotulo: 'Telefone', valor: d.telefone),
                  LinhaDetalhe(rotulo: 'Endereço', valor: d.endereco),
                  LinhaDetalhe(
                      rotulo: 'Cadastrado em', valor: _data(d.criadoEm)),
                  const SizedBox(height: 28),
                  _historicoDenuncias(d),
                ],
              ),
            ),
            if (context.watch<AdminProvider>().suportaModeracao)
              _barraAcoes(d, processando)
            else
              const AvisoAdmin(
                  'Alteração de advertências e suspensão de contas ainda não estão disponíveis no servidor.'),
          ],
        ),
      ),
    );
  }

  Widget _advertencias(Demandante d) {
    const limite = AppConstants.strikesParaBanimento;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Advertências',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var i = 0; i < limite; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: i < d.strikes
                        ? (d.banido
                            ? AppColors.error
                            : Colors.deepOrange.shade600)
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Text(
          d.banido
              ? '$limite de $limite — conta suspensa'
              : '${d.strikes} de $limite · faltam ${d.strikesRestantes} '
                  'para a suspensão',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: d.banido ? AppColors.error : Colors.grey.shade700,
          ),
        ),
      ],
    );
  }

  Widget _historicoDenuncias(Demandante d) {
    if (!context.watch<AdminProvider>().suportaModeracao) {
      return const AvisoAdmin(
          'Histórico de denúncias ainda não está disponível no servidor.');
    }
    return SecaoPersistenteAdmin(
        child: StreamBuilder<List<Denuncia>>(
      stream: _denuncias,
      builder: (context, snap) {
        if (snap.hasError) return AvisoAdmin(mensagemErroAdmin(snap.error));
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final denuncias = snap.data ?? const <Denuncia>[];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Denúncias recebidas (${denuncias.length})',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 12),
            if (denuncias.isEmpty)
              Text(
                'Nenhuma denúncia registrada contra este demandante.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              )
            else
              for (final den in denuncias)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              AdminDenunciaDetalhesScreen(denuncia: den),
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    den.tituloDemanda,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Etiqueta(
                                  texto: den.status.label,
                                  cor: den.status.cor,
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${den.motivo.label} · '
                              '${formatarQuando(den.criadoEm)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        );
      },
    ));
  }

  Widget _barraAcoes(Demandante d, bool processando) {
    const limite = AppConstants.strikesParaBanimento;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          if (d.strikes > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: processando
                    ? null
                    : () => ajustarStrikesComDialogo(
                          context,
                          demandante: d,
                          novoTotal: d.banido ? 0 : d.strikes - 1,
                        ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.success,
                  side: const BorderSide(color: AppColors.success),
                  minimumSize: const Size.fromHeight(52),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(d.banido ? Icons.lock_open : Icons.remove, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        d.banido ? 'Reativar conta' : 'Remover advertência',
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (d.strikes > 0 && !d.banido) const SizedBox(width: 12),
          if (!d.banido)
            Expanded(
              child: ElevatedButton(
                onPressed: processando
                    ? null
                    : () => ajustarStrikesComDialogo(
                          context,
                          demandante: d,
                          novoTotal: d.strikes + 1,
                        ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: d.strikes + 1 >= limite
                      ? AppColors.error
                      : Colors.deepOrange.shade700,
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
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              d.strikes + 1 >= limite
                                  ? Icons.block
                                  : Icons.warning_amber_outlined,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              d.strikes + 1 >= limite
                                  ? 'Advertir e suspender'
                                  : 'Advertir',
                              maxLines: 1,
                              softWrap: false,
                            ),
                          ],
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  String _data(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}
