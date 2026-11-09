import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../app/app_dependencies.dart';
import '../../../core/models/demanda.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/repositories/admin_repository.dart';
import '../providers/admin_provider.dart';
import '../widgets/admin_widgets.dart';

/// Primeira aba do painel: o retrato do sistema num olhar.
///
/// Os números de demandas vêm de um stream de todas as demandas, agregado no
/// cliente. Numa base de campus isso é uma leitura só; a alternativa —
/// contadores mantidos por Cloud Function — está catalogada em
/// `docs/CLOUD_FUNCTIONS.md` como evolução quando o volume justificar.
class AdminVisaoGeralScreen extends StatefulWidget {
  const AdminVisaoGeralScreen({super.key});

  @override
  State<AdminVisaoGeralScreen> createState() => _AdminVisaoGeralScreenState();
}

class _AdminVisaoGeralScreenState extends State<AdminVisaoGeralScreen> {
  AdminRepository get _repository => context.read<AdminRepository>();
  late final Stream<List<Demanda>> _demandas =
      _repository.observarTodasDemandas();

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();
    final nome = context.watch<AuthProvider>().usuario?.nome ?? '';

    return Column(
      children: [
        AdminHeader(
          titulo: 'Visão geral',
          subtitulo: nome.isEmpty ? null : 'Bem-vindo, $nome',
          acoes: [
            IconButton(
              icon: const Icon(Icons.logout, color: AppColors.primary),
              tooltip: 'Sair',
              onPressed: () => context.read<AuthProvider>().sair(),
            ),
          ],
        ),
        Expanded(
          child: StreamBuilder<List<Demanda>>(
            stream: _demandas,
            builder: (context, snap) {
              final demandas = snap.data ?? const <Demanda>[];
              return ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                children: [
                  _secao('Demandas'),
                  if (snap.hasError)
                    AvisoAdmin(mensagemErroAdmin(snap.error))
                  else if (!snap.hasData)
                    const Center(child: CircularProgressIndicator())
                  else
                    GradeMetricas(
                      cartoes: [
                        CartaoMetrica(
                          valor: '${demandas.length}',
                          label: 'Total',
                          icone: Icons.inbox_outlined,
                          cor: AppColors.primary,
                        ),
                        for (final status in StatusDemanda.values)
                          CartaoMetrica(
                            valor: '${_contar(demandas, status)}',
                            label: status.label,
                            icone: status.icone,
                            cor: status.cor,
                          ),
                      ],
                    ),
                  const SizedBox(height: 28),
                  _secao('Moderação'),
                  if (!admin.suportaModeracao)
                    const AvisoAdmin(
                        'Julgamento e ações de moderação ainda não estão disponíveis no servidor.'),
                  if (admin.erroDenuncias != null)
                    AvisoAdmin(admin.erroDenuncias!),
                  if (admin.erroDemandantes != null)
                    AvisoAdmin(admin.erroDemandantes!),
                  GradeMetricas(
                    colunas: 2,
                    cartoes: [
                      CartaoMetrica(
                        valor: admin.carregandoDenuncias ||
                                admin.erroDenuncias != null
                            ? '—'
                            : '${admin.denunciasPendentes}',
                        label: 'Denúncias pendentes',
                        icone: Icons.flag_outlined,
                        cor: admin.denunciasPendentes > 0
                            ? AppColors.error
                            : AppColors.success,
                      ),
                      CartaoMetrica(
                        valor: admin.carregandoDemandantes ||
                                admin.erroDemandantes != null
                            ? '—'
                            : '${admin.demandantesBanidos}',
                        label: 'Contas suspensas',
                        icone: Icons.block,
                        cor: Colors.deepOrange.shade700,
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  _secao('Corpo docente'),
                  if (admin.erroProfessores != null)
                    AvisoAdmin(admin.erroProfessores!),
                  GradeMetricas(
                    colunas: 2,
                    cartoes: [
                      CartaoMetrica(
                        valor: admin.carregandoProfessores ||
                                admin.erroProfessores != null
                            ? '—'
                            : '${admin.professoresAtivos}',
                        label: 'Professores ativos',
                        icone: Icons.person_outline,
                        cor: AppColors.success,
                      ),
                      CartaoMetrica(
                        valor: admin.carregandoProfessores ||
                                admin.erroProfessores != null
                            ? '—'
                            : '${admin.professoresInativos}',
                        label: 'Professores desativados',
                        icone: Icons.person_off_outlined,
                        cor: Colors.grey.shade600,
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  _rodapeTempoReal(),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _secao(String titulo) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          titulo,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
      );

  Widget _rodapeTempoReal() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.bolt_outlined, size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.read<AppDependencies>().usaApi
                    ? 'Os dados são consultados automaticamente a cada 15 segundos.'
                    : 'Todos os números desta tela são atualizados em tempo real.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
          ],
        ),
      );

  int _contar(List<Demanda> demandas, StatusDemanda status) =>
      demandas.where((d) => d.status == status).length;
}
