import 'demanda.dart';

/// Indicadores de desempenho de um professor, calculados no cliente a partir
/// das demandas atribuídas a ele.
///
/// **Por que calcular no cliente e não manter contadores desnormalizados?**
/// Contadores exigiriam incremento transacional a cada transição (ou uma Cloud
/// Function). No volume de um campus — dezenas de demandas por professor — uma
/// única query por professor é mais barata que a complexidade de manter
/// contadores consistentes. Quando o volume crescer, a migração natural é uma
/// Cloud Function que mantém `users/{id}.metricas` atualizado; ver
/// `docs/CLOUD_FUNCTIONS.md`.
class MetricasProfessor {
  final String professorId;

  final int totalAtribuidas;
  final int emAnalise;
  final int emProducao;
  final int concluidas;

  /// Demandas que o professor pegou para análise e devolveu à prateleira.
  /// Derivado dos logs de auditoria (`rejeitar` + `rollback_analise`), pois a
  /// demanda devolvida perde o vínculo com o professor.
  final int devolvidas;
  final bool historicoDevolucoesDisponivel;

  /// Média de (concluidaEm - producaoIniciadaEm) sobre as concluídas.
  /// `null` quando não há nenhuma concluída com ambos os marcos preenchidos.
  final Duration? tempoMedioEntrega;

  /// Média de (producaoIniciadaEm - analiseIniciadaEm) — quanto o professor
  /// demora para decidir depois de marcar para análise.
  final Duration? tempoMedioAnalise;

  /// Última transição registrada em qualquer demanda dele.
  final DateTime? ultimaAtividade;

  const MetricasProfessor({
    required this.professorId,
    required this.totalAtribuidas,
    required this.emAnalise,
    required this.emProducao,
    required this.concluidas,
    required this.devolvidas,
    this.historicoDevolucoesDisponivel = true,
    this.tempoMedioEntrega,
    this.tempoMedioAnalise,
    this.ultimaAtividade,
  });

  const MetricasProfessor.vazia(this.professorId)
      : totalAtribuidas = 0,
        emAnalise = 0,
        emProducao = 0,
        concluidas = 0,
        devolvidas = 0,
        historicoDevolucoesDisponivel = true,
        tempoMedioEntrega = null,
        tempoMedioAnalise = null,
        ultimaAtividade = null;

  /// Percentual de demandas assumidas que chegaram à entrega.
  /// Base = concluídas + em produção (as que ele de fato assumiu). Demandas
  /// paradas em análise não contam: ainda não houve compromisso.
  double? get taxaConclusao {
    final assumidas = concluidas + emProducao;
    if (assumidas == 0) return null;
    return concluidas / assumidas;
  }

  /// Carga atual: o que está na mão do professor agora.
  int get emAberto => emAnalise + emProducao;

  /// Constrói as métricas a partir da lista de demandas do professor.
  /// [devolvidas] vem de fora porque não é derivável das demandas atuais
  /// (a devolução apaga o `professorId`) — só a auditoria guarda esse fato.
  factory MetricasProfessor.calcular({
    required String professorId,
    required List<Demanda> demandas,
    int devolvidas = 0,
    bool historicoDevolucoesDisponivel = true,
  }) {
    var emAnalise = 0;
    var emProducao = 0;
    var concluidas = 0;

    final entregas = <Duration>[];
    final analises = <Duration>[];
    DateTime? ultima;

    for (final d in demandas) {
      switch (d.status) {
        case StatusDemanda.emAnalise:
          emAnalise++;
        case StatusDemanda.emProducao:
          emProducao++;
        case StatusDemanda.concluida:
          concluidas++;
        case StatusDemanda.cadastrada:
        case StatusDemanda.cancelada:
          break;
      }

      if (d.concluidaEm != null && d.producaoIniciadaEm != null) {
        final dur = d.concluidaEm!.difference(d.producaoIniciadaEm!);
        if (!dur.isNegative) entregas.add(dur);
      }
      if (d.producaoIniciadaEm != null && d.analiseIniciadaEm != null) {
        final dur = d.producaoIniciadaEm!.difference(d.analiseIniciadaEm!);
        if (!dur.isNegative) analises.add(dur);
      }

      for (final marco in [
        d.analiseIniciadaEm,
        d.producaoIniciadaEm,
        d.concluidaEm,
        d.atualizadoEm,
      ]) {
        if (marco != null && (ultima == null || marco.isAfter(ultima))) {
          ultima = marco;
        }
      }
    }

    return MetricasProfessor(
      professorId: professorId,
      totalAtribuidas: demandas.length,
      emAnalise: emAnalise,
      emProducao: emProducao,
      concluidas: concluidas,
      devolvidas: devolvidas,
      historicoDevolucoesDisponivel: historicoDevolucoesDisponivel,
      tempoMedioEntrega: _media(entregas),
      tempoMedioAnalise: _media(analises),
      ultimaAtividade: ultima,
    );
  }

  static Duration? _media(List<Duration> valores) {
    if (valores.isEmpty) return null;
    final somaMicros = valores.fold<int>(0, (a, d) => a + d.inMicroseconds);
    return Duration(microseconds: somaMicros ~/ valores.length);
  }
}

/// Formata uma duração em texto curto para os cartões de métrica
/// ("3d 4h", "5h 20min", "12min", "—").
String formatarDuracao(Duration? d) {
  if (d == null) return '—';
  if (d.inDays > 0) return '${d.inDays}d ${d.inHours.remainder(24)}h';
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}min';
  if (d.inMinutes > 0) return '${d.inMinutes}min';
  return '<1min';
}
