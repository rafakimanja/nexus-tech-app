import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/demandante.dart';
import '../../../core/providers/auth_provider.dart';
import '../../demandas/widgets/estado_lista.dart';
import '../providers/admin_provider.dart';
import '../widgets/admin_widgets.dart';
import 'admin_demandante_detalhes_screen.dart';

/// Lista de demandantes com advertências e suspensões visíveis de imediato —
/// é a informação que o admin procura ao abrir esta aba.
class AdminDemandantesScreen extends StatelessWidget {
  const AdminDemandantesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();

    return Column(
      children: [
        AdminHeader(
          titulo: 'Demandantes',
          subtitulo:
              admin.carregandoDemandantes || admin.erroDemandantes != null
                  ? null
                  : admin.demandantesBanidos == 0
                      ? 'Nenhuma conta suspensa'
                      : '${admin.demandantesBanidos} conta(s) suspensa(s)',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
          child: BarraBusca(
            hint: 'Buscar por nome ou e-mail...',
            onChanged: context.read<AdminProvider>().atualizarBuscaDemandantes,
          ),
        ),
        Expanded(child: _lista(context, admin)),
      ],
    );
  }

  Widget _lista(BuildContext context, AdminProvider admin) {
    if (admin.erroDemandantes != null) {
      return AvisoAdmin(admin.erroDemandantes!);
    }
    if (admin.carregandoDemandantes && admin.demandantes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (admin.demandantes.isEmpty) {
      final buscando = admin.buscaDemandantes.isNotEmpty;
      return EstadoLista(
        icone: buscando ? Icons.search_off : Icons.groups_outlined,
        titulo: buscando ? 'Nada encontrado' : 'Nenhum demandante cadastrado',
        mensagem: buscando
            ? 'Nenhum demandante corresponde a "${admin.buscaDemandantes}".'
            : 'Organizações e pessoas aparecem aqui após concluírem o '
                'cadastro.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: admin.demandantes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final d = admin.demandantes[i];
        return _CartaoDemandante(
          demandante: d,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AdminDemandanteDetalhesScreen(demandante: d),
            ),
          ),
        );
      },
    );
  }
}

class _CartaoDemandante extends StatelessWidget {
  final Demandante demandante;
  final VoidCallback onTap;

  const _CartaoDemandante({required this.demandante, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = demandante;

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
              color: d.banido
                  ? AppColors.error.withValues(alpha: 0.4)
                  : Colors.grey.shade200,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: d.banido
                    ? AppColors.error.withValues(alpha: 0.12)
                    : AppColors.primary.withValues(alpha: 0.12),
                child: Icon(
                  d.banido ? Icons.block : Icons.business_outlined,
                  size: 22,
                  color: d.banido ? AppColors.error : AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      d.tipo.label,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (d.banido)
                          const Etiqueta(
                            texto: 'Suspensa',
                            cor: AppColors.error,
                            icone: Icons.block,
                          )
                        else
                          const Etiqueta(
                            texto: 'Ativa',
                            cor: AppColors.success,
                            icone: Icons.check_circle_outline,
                          ),
                        Etiqueta(
                          texto: '${d.strikes}/'
                              '${AppConstants.strikesParaBanimento} '
                              'advertências',
                          cor: d.strikes == 0
                              ? Colors.grey.shade600
                              : Colors.deepOrange.shade700,
                          icone: Icons.warning_amber_outlined,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ação compartilhada entre a lista e a tela de detalhes: ajustar advertências.
/// Fica aqui para as duas telas oferecerem exatamente o mesmo fluxo, com a
/// mesma confirmação e a mesma mensagem de retorno.
Future<void> ajustarStrikesComDialogo(
  BuildContext context, {
  required Demandante demandante,
  required int novoTotal,
}) async {
  final admin = context.read<AuthProvider>().usuario;
  if (admin == null) return;

  final vaiBanir = novoTotal >= AppConstants.strikesParaBanimento;
  final vaiReativar = demandante.banido && !vaiBanir;

  final motivo = await DialogMotivo.mostrar(
    context,
    titulo: vaiBanir
        ? 'Suspender conta'
        : vaiReativar
            ? 'Reativar conta'
            : 'Ajustar advertências',
    descricao: vaiBanir
        ? '${demandante.nome} passará a $novoTotal advertências e a conta '
            'será suspensa. A pessoa perde o acesso ao app até que um admin '
            'reverta.'
        : vaiReativar
            ? 'As advertências de ${demandante.nome} passarão a $novoTotal e a '
                'conta voltará a funcionar normalmente.'
            : 'As advertências de ${demandante.nome} passarão de '
                '${demandante.strikes} para $novoTotal.',
    rotuloConfirmar: vaiBanir
        ? 'Suspender'
        : vaiReativar
            ? 'Reativar'
            : 'Confirmar',
    hint: 'Motivo do ajuste (a pessoa verá este texto).',
    corConfirmar: vaiBanir ? AppColors.error : AppColors.primary,
  );
  if (motivo == null || !context.mounted) return;

  final provider = context.read<AdminProvider>();
  final ok = await provider.ajustarStrikes(
    demandante: demandante,
    novoTotal: novoTotal,
    adminId: admin.id,
    adminNome: admin.nome,
    motivo: motivo,
  );

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        ok
            ? vaiBanir
                ? 'Conta suspensa. O demandante foi notificado.'
                : 'Advertências atualizadas para $novoTotal.'
            : provider.erro ?? 'Não foi possível concluir a ação.',
      ),
      backgroundColor: ok
          ? (vaiBanir ? AppColors.error : AppColors.success)
          : AppColors.error,
    ),
  );
}
