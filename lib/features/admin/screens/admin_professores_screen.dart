import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../core/models/professor.dart';
import '../../demandas/widgets/estado_lista.dart';
import '../providers/admin_provider.dart';
import '../widgets/admin_widgets.dart';
import 'admin_professor_metricas_screen.dart';

/// Lista do corpo docente com o estado de cada perfil.
/// Tocar num professor abre as métricas dele, onde ficam as ações de
/// ligar/desligar — a decisão de desativar precisa do contexto de carga.
class AdminProfessoresScreen extends StatelessWidget {
  const AdminProfessoresScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();

    return Column(
      children: [
        AdminHeader(
          titulo: 'Professores',
          subtitulo:
              admin.carregandoProfessores || admin.erroProfessores != null
                  ? null
                  : '${admin.professoresAtivos} ativos · '
                      '${admin.professoresInativos} desativados',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
          child: BarraBusca(
            hint: 'Buscar por nome, e-mail ou SIAPE...',
            onChanged: context.read<AdminProvider>().atualizarBuscaProfessores,
          ),
        ),
        Expanded(child: _lista(context, admin)),
      ],
    );
  }

  Widget _lista(BuildContext context, AdminProvider admin) {
    if (admin.erroProfessores != null) {
      return AvisoAdmin(admin.erroProfessores!);
    }
    if (admin.carregandoProfessores && admin.professores.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (admin.professores.isEmpty) {
      final buscando = admin.buscaProfessores.isNotEmpty;
      return EstadoLista(
        icone: buscando ? Icons.search_off : Icons.school_outlined,
        titulo: buscando ? 'Nada encontrado' : 'Nenhum professor cadastrado',
        mensagem: buscando
            ? 'Nenhum professor corresponde a "${admin.buscaProfessores}".'
            : 'Professores aparecem aqui após o primeiro acesso com e-mail '
                'institucional.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: admin.professores.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final p = admin.professores[i];
        return _CartaoProfessor(
          professor: p,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AdminProfessorMetricasScreen(professor: p),
            ),
          ),
        );
      },
    );
  }
}

class _CartaoProfessor extends StatelessWidget {
  final Professor professor;
  final VoidCallback onTap;

  const _CartaoProfessor({required this.professor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = professor;

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
              color: p.ativo ? Colors.grey.shade200 : Colors.grey.shade400,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: p.ativo
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : Colors.grey.shade200,
                child: Icon(
                  p.ativo ? Icons.person : Icons.person_off,
                  color: p.ativo ? AppColors.primary : Colors.grey.shade600,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.nome,
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
                      p.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Etiqueta(
                          texto: p.ativo ? 'Ativo' : 'Desativado',
                          cor: p.ativo
                              ? AppColors.success
                              : Colors.grey.shade600,
                          icone: p.ativo
                              ? Icons.check_circle_outline
                              : Icons.block,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'SIAPE ${p.siape}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
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
