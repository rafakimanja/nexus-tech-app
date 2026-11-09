import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../core/models/denuncia.dart';
import '../../demandas/widgets/estado_lista.dart';
import '../../notificacoes/screens/notificacoes_screen.dart'
    show formatarQuando;
import '../providers/admin_provider.dart';
import '../widgets/admin_widgets.dart';
import 'admin_denuncia_detalhes_screen.dart';
import 'api_denuncia_detalhes_screen.dart';
import '../../../app/app_dependencies.dart';

/// Fila de denúncias. Abre em "pendentes" porque é a fila de trabalho; o
/// histórico completo fica a um toque, para consulta e auditoria.
class AdminDenunciasScreen extends StatelessWidget {
  const AdminDenunciasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();

    return Column(
      children: [
        AdminHeader(
          titulo: 'Denúncias',
          subtitulo: admin.denunciasPendentes == 0
              ? 'Nenhuma denúncia aguardando análise'
              : '${admin.denunciasPendentes} aguardando análise',
        ),
        if (admin.suportaModeracao) _filtro(context, admin),
        if (!admin.suportaModeracao)
          const AvisoAdmin(
              'Denúncias registradas. Julgamento ainda não disponível.'),
        Expanded(child: _lista(context, admin)),
      ],
    );
  }

  Widget _filtro(BuildContext context, AdminProvider admin) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      child: SegmentedButton<bool>(
        segments: const [
          ButtonSegment(
            value: true,
            label: Text('Pendentes'),
            icon: Icon(Icons.hourglass_empty, size: 16),
          ),
          ButtonSegment(
            value: false,
            label: Text('Todas'),
            icon: Icon(Icons.history, size: 16),
          ),
        ],
        selected: {admin.apenasDenunciasPendentes},
        onSelectionChanged: (s) =>
            context.read<AdminProvider>().alternarFiltroDenuncias(s.first),
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: AppColors.primary.withValues(alpha: 0.15),
          selectedForegroundColor: AppColors.primary,
        ),
      ),
    );
  }

  Widget _lista(BuildContext context, AdminProvider admin) {
    if (admin.erroDenuncias != null) {
      return AvisoAdmin(admin.erroDenuncias!);
    }
    if (admin.carregandoDenuncias && admin.denuncias.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (admin.denuncias.isEmpty) {
      return EstadoLista(
        icone: admin.apenasDenunciasPendentes
            ? Icons.verified_outlined
            : Icons.flag_outlined,
        titulo: admin.apenasDenunciasPendentes
            ? 'Nada pendente'
            : 'Nenhuma denúncia registrada',
        mensagem: admin.apenasDenunciasPendentes
            ? 'Todas as denúncias recebidas já foram analisadas.'
            : 'Quando um professor denunciar uma demanda, ela aparece aqui.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: admin.denuncias.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final d = admin.denuncias[i];
        return _CartaoDenuncia(
          denuncia: d,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => context.read<AppDependencies>().usaApi
                  ? ApiDenunciaDetalhesScreen(id: d.id)
                  : AdminDenunciaDetalhesScreen(denuncia: d),
            ),
          ),
        );
      },
    );
  }
}

class _CartaoDenuncia extends StatelessWidget {
  final Denuncia denuncia;
  final VoidCallback onTap;

  const _CartaoDenuncia({required this.denuncia, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = denuncia;

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
              color: d.pendente
                  ? d.status.cor.withValues(alpha: 0.4)
                  : Colors.grey.shade200,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      d.tituloDemanda,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Etiqueta(
                    texto: d.status.label,
                    cor: d.status.cor,
                    icone: d.status.icone,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                d.motivo.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                d.descricao,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.person_outline,
                      size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Por ${d.professorNome} · contra ${d.demandanteNome}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatarQuando(d.criadoEm),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
