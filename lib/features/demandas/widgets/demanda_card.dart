import 'package:provider/provider.dart';
import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/models/demanda.dart';
import '../../../core/repositories/demanda_repository.dart';
import 'status_badge.dart';

/// Card de demanda exibido na tela "Minhas Demandas".
///
/// Layout:
/// - Faixa lateral esquerda colorida pelo status (cadastrada=amarelo,
///   emAnalise=laranja, emProducao=azul, concluida=verde, cancelada=vermelho).
/// - Título da demanda + data de criação.
/// - Descrição (2 linhas, com ellipsis).
/// - Linha inferior: badge de status + contador de anexos.
class DemandaCard extends StatelessWidget {
  final Demanda demanda;
  final VoidCallback onTap;

  const DemandaCard({
    super.key,
    required this.demanda,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Faixa lateral colorida por status
              Container(width: 6, color: demanda.status.cor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Título + data
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              demanda.titulo,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatarData(demanda.criadoEm),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Descrição
                      Text(
                        demanda.descricao,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Status + contador de anexos
                      Row(
                        children: [
                          _ContadorAnexos(demandaId: demanda.id),
                          const Spacer(),
                          StatusBadge(status: demanda.status),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatarData(DateTime data) {
    final dd = data.day.toString().padLeft(2, '0');
    final mm = data.month.toString().padLeft(2, '0');
    return '$dd/$mm/${data.year}';
  }
}

/// Contador de anexos. Usa aggregation query do Firestore (count) para evitar
/// baixar a lista inteira de metadados em cada card.
///
/// Decisão: FutureBuilder em vez de StreamBuilder. O número de anexos não muda
/// com tanta frequência que justifique um listener vivo por card. A próxima
/// vez que o card for reconstruído (entrar/sair de filtro, pull-to-refresh,
/// stream principal mudar), o contador é re-buscado naturalmente.
class _ContadorAnexos extends StatelessWidget {
  final String demandaId;

  const _ContadorAnexos({required this.demandaId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: context.read<DemandaRepository>().contarAnexos(demandaId),
      builder: (context, snap) {
        final n = snap.data ?? 0;

        // Enquanto carrega, mostra placeholder discreto pra não fazer o
        // layout pular quando o número chegar.
        final texto =
            snap.connectionState == ConnectionState.waiting ? '—' : '$n';

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.attach_file,
              size: 14,
              color: Colors.grey.shade600,
            ),
            const SizedBox(width: 4),
            Text(
              texto,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        );
      },
    );
  }
}
