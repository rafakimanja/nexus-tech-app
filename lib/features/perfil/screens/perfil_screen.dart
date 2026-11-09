import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../app/app_dependencies.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/demanda.dart';
import '../../../core/models/demandante.dart';
import '../../../core/models/professor.dart';
import '../../../core/models/usuario.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/repositories/demanda_repository.dart';
import '../providers/perfil_provider.dart';
import '../widgets/estatisticas_demandas.dart';
import '../widgets/perfil_avatar.dart';
import 'editar_perfil_demandante_screen.dart';
import 'editar_perfil_professor_screen.dart';

/// UC23 — Perfil do usuário (demandante ou professor).
/// Mostra avatar (com troca de foto), dados, painel de estatísticas das
/// demandas e acesso à edição. Usada como ABA (professor) ou como rota
/// empurrada (demandante) — controlado por [comoAba].
class PerfilScreen extends StatefulWidget {
  final bool comoAba;
  const PerfilScreen({super.key, this.comoAba = false});

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  DemandaRepository get _repository => context.read<DemandaRepository>();

  // Cacheia o stream das estatísticas por id para não re-subscrever (e
  // piscar os números) a cada rebuild da tela.
  Stream<List<Demanda>>? _statsStream;
  String? _statsId;

  Stream<List<Demanda>> _streamEstatisticas(Usuario usuario) {
    if (_statsStream != null && _statsId == usuario.id) return _statsStream!;
    _statsId = usuario.id;
    _statsStream = usuario is Professor
        ? _repository.listarDoProfessor(professorId: usuario.id)
        : _repository.listarDoDemandante(demandanteId: usuario.id);
    return _statsStream!;
  }

  void _feedback(String msg, Color cor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: cor),
    );
  }

  Future<void> _trocarFoto(Usuario usuario) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;
    if (!mounted) return;

    final perfil = context.read<PerfilProvider>();
    final auth = context.read<AuthProvider>();

    final ok = await perfil.trocarFoto(
      id: usuario.id,
      caminhoLocal: file.path!,
      formato: (file.extension ?? '').toLowerCase(),
    );

    if (ok) {
      await auth.recarregarUsuario();
      _feedback('Foto de perfil atualizada.', AppColors.success);
    } else if (perfil.erro != null) {
      _feedback(perfil.erro!, AppColors.error);
    }
  }

  void _editar(Usuario usuario) {
    final rota = usuario is Professor
        ? MaterialPageRoute<void>(
            builder: (_) => EditarPerfilProfessorScreen(professor: usuario),
          )
        : MaterialPageRoute<void>(
            builder: (_) =>
                EditarPerfilDemandanteScreen(demandante: usuario as Demandante),
          );
    Navigator.of(context).push(rota);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final usuario = auth.usuario;
    if (usuario == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final enviandoFoto = context.watch<PerfilProvider>().enviandoFoto;

    return Column(
      children: [
        _header(context),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            children: [
              Center(
                child: PerfilAvatar(
                  fotoUrl: usuario.fotoUrl,
                  googlePhotoUrl: auth.sessao?.fotoUrl,
                  nome: usuario.nome,
                  enviando: enviandoFoto,
                  onEditar: context.read<AppDependencies>().usaApi ? null : () => _trocarFoto(usuario),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                usuario.nome,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                usuario.email,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 28),
              _tituloSecao(usuario is Professor
                  ? 'Resumo das minhas demandas'
                  : 'Resumo das demandas'),
              const SizedBox(height: 12),
              _estatisticas(usuario),
              if (usuario is Demandante && usuario.strikes > 0) ...[
                const SizedBox(height: 28),
                _avisoAdvertencias(usuario),
              ],
              const SizedBox(height: 28),
              _tituloSecao('Dados'),
              const SizedBox(height: 12),
              ..._dados(usuario),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _editar(usuario),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar perfil'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Advertências acumuladas pelo demandante.
  ///
  /// Só aparece quando existe pelo menos uma: mostrar "0 de 3" para todo mundo
  /// transformaria uma tela de perfil numa ameaça permanente. Quando existe,
  /// porém, a pessoa tem direito de saber onde está — descobrir a suspensão só
  /// no momento em que ela acontece seria surpresa, não consequência.
  Widget _avisoAdvertencias(Demandante demandante) {
    final restantes = demandante.strikesRestantes;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.deepOrange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.deepOrange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_outlined,
                  size: 20, color: Colors.deepOrange.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Advertências: ${demandante.strikes} de '
                  '${AppConstants.strikesParaBanimento}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepOrange.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < AppConstants.strikesParaBanimento; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: i < demandante.strikes
                          ? Colors.deepOrange.shade600
                          : Colors.deepOrange.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            restantes == 1
                ? 'Mais uma advertência suspende sua conta. Denúncias '
                    'procedentes de professores geram advertências.'
                : 'Faltam $restantes advertências para a suspensão da conta.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Colors.deepOrange.shade900,
            ),
          ),
        ],
      ),
    );
  }

  // ============== estatísticas (contadores em tempo real) ==============

  Widget _estatisticas(Usuario usuario) {
    final ehProfessor = usuario is Professor;

    return StreamBuilder<List<Demanda>>(
      stream: _streamEstatisticas(usuario),
      builder: (context, snap) {
        final lista = snap.data;
        int? contar(StatusDemanda s) =>
            lista?.where((d) => d.status == s).length;

        return EstatisticasDemandas(
          itens: [
            (
              label: 'Em análise',
              valor: contar(StatusDemanda.emAnalise),
              cor: Colors.orange.shade700,
              icone: Icons.search,
            ),
            (
              label: ehProfessor ? 'Produzindo' : 'Em produção',
              valor: contar(StatusDemanda.emProducao),
              cor: Colors.blue.shade700,
              icone: Icons.settings,
            ),
            (
              label: ehProfessor ? 'Entregues' : 'Concluídas',
              valor: contar(StatusDemanda.concluida),
              cor: AppColors.success,
              icone: Icons.check_circle_outline,
            ),
          ],
        );
      },
    );
  }

  // ============== dados específicos por papel ==============

  List<Widget> _dados(Usuario usuario) {
    if (usuario is Demandante) {
      return [
        _InfoLinha(
          icone: Icons.badge_outlined,
          label: 'Tipo',
          valor: usuario.tipo.label,
        ),
        _InfoLinha(
          icone: Icons.phone_outlined,
          label: 'Telefone',
          valor: _formatarTelefone(usuario.telefone),
        ),
        _InfoLinha(
          icone: Icons.assignment_ind_outlined,
          label: 'CPF/CNPJ',
          valor: usuario.cpfCnpj,
        ),
        _InfoLinha(
          icone: Icons.location_on_outlined,
          label: 'Endereço',
          valor: usuario.endereco,
        ),
      ];
    }
    if (usuario is Professor) {
      return [
        _InfoLinha(
          icone: Icons.badge_outlined,
          label: 'SIAPE',
          valor: usuario.siape,
        ),
        _InfoLinha(
          icone: usuario.ativo ? Icons.verified_outlined : Icons.block,
          label: 'Situação',
          valor: usuario.ativo ? 'Ativo' : 'Inativo',
        ),
        _Chips(
            titulo: 'Áreas técnicas',
            itens: usuario.areasTecnicas.map((a) => a.nome).toList()),
        _Chips(
            titulo: 'Áreas de interesse',
            itens: usuario.areasInteresse.map((a) => a.nome).toList()),
      ];
    }
    return const [];
  }

  // ============== header ==============

  Widget _header(BuildContext context) {
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
              const Spacer(),
              if (widget.comoAba)
                IconButton(
                  icon: const Icon(Icons.logout, color: AppColors.primary),
                  tooltip: 'Sair',
                  onPressed: () => context.read<AuthProvider>().sair(),
                ),
            ],
          ),
          if (!widget.comoAba) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: () => Navigator.of(context).pop(),
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
          const SizedBox(height: 8),
          const Text(
            'Perfil',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tituloSecao(String texto) => Text(
        texto,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
        ),
      );

  String _formatarTelefone(String digits) {
    if (digits.length == 11) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2, 7)}-${digits.substring(7)}';
    }
    if (digits.length == 10) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2, 6)}-${digits.substring(6)}';
    }
    return digits;
  }
}

class _InfoLinha extends StatelessWidget {
  final IconData icone;
  final String label;
  final String valor;

  const _InfoLinha({
    required this.icone,
    required this.label,
    required this.valor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 2),
                Text(
                  valor.isEmpty ? '—' : valor,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chips extends StatelessWidget {
  final String titulo;
  final List<String> itens;
  const _Chips({required this.titulo, required this.itens});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          if (itens.isEmpty)
            const Text('—', style: TextStyle(color: AppColors.textPrimary))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: itens
                  .map((a) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          a,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }
}
