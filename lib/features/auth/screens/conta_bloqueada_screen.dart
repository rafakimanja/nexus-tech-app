import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/demandante.dart';
import '../../../core/models/professor.dart';
import '../../../core/providers/auth_provider.dart';

/// Tela terminal para contas sem permissão de uso.
///
/// Duas situações caem aqui: demandante suspenso por acúmulo de advertências e
/// professor com o perfil desligado pela administração. É uma tela de bloqueio
/// e não uma lista de botões desabilitados porque o estado é do **acesso**, não
/// de uma ação: deixar a pessoa navegar por telas que não funcionam é pior do
/// que dizer com clareza o que aconteceu e o que fazer a respeito.
///
/// O bloqueio aqui é de experiência. A garantia real está nas Firestore Rules,
/// que recusam escrita de conta suspensa mesmo por fora do app.
class ContaBloqueadaScreen extends StatelessWidget {
  const ContaBloqueadaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final usuario = auth.usuario;

    final _Conteudo conteudo = switch (usuario) {
      final Demandante d when d.banido => _Conteudo(
          icone: Icons.block,
          titulo: 'Conta suspensa',
          mensagem: d.motivoBanimento ??
              'Sua conta acumulou ${AppConstants.strikesParaBanimento} '
                  'advertências por denúncias procedentes e foi suspensa.',
          detalhe:
              d.banidoEm == null ? null : 'Suspensa em ${_data(d.banidoEm!)}.',
        ),
      final Professor p when !p.ativo => _Conteudo(
          icone: Icons.person_off_outlined,
          titulo: 'Perfil desativado',
          mensagem: p.motivoDesativacao ??
              'Seu perfil de professor foi desativado pela administração do '
                  'campus.',
          detalhe: p.desativadoEm == null
              ? null
              : 'Desativado em ${_data(p.desativadoEm!)}.',
        ),
      _ => _Conteudo(
          icone: Icons.lock_outline,
          titulo: 'Acesso indisponível',
          mensagem: auth.erro ??
              'Sua conta não está habilitada para usar a plataforma no '
                  'momento.',
          detalhe: null,
        ),
    };

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('assets/images/logo.png', width: 72, height: 72),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(conteudo.icone, size: 48, color: AppColors.error),
                ),
                const SizedBox(height: 24),
                Text(
                  conteudo.titulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  conteudo.mensagem,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: Colors.grey.shade700,
                  ),
                ),
                if (conteudo.detalhe != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    conteudo.detalhe!,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                ],
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.support_agent_outlined,
                          size: 20, color: Colors.grey.shade600),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Para contestar a decisão, procure a administração '
                          'do IFRS Campus Osório.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => context.read<AuthProvider>().sair(),
                    icon: const Icon(Icons.logout, size: 20),
                    label: const Text('Sair'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _data(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}

/// O texto que a tela mostra, escolhido pelo motivo do bloqueio.
class _Conteudo {
  final IconData icone;
  final String titulo;
  final String mensagem;
  final String? detalhe;

  const _Conteudo({
    required this.icone,
    required this.titulo,
    required this.mensagem,
    required this.detalhe,
  });
}
