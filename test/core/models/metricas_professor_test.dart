import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_tech/core/models/demanda.dart';
import 'package:nexus_tech/core/models/enums.dart';
import 'package:nexus_tech/core/models/metricas_professor.dart';

/// Base fixa para as datas dos testes. Usar um instante fixo (e não
/// `DateTime.now()`) mantém os cálculos de duração determinísticos.
final _base = DateTime(2026, 3, 10, 9);

Demanda _demanda({
  required String id,
  required StatusDemanda status,
  DateTime? analiseIniciadaEm,
  DateTime? producaoIniciadaEm,
  DateTime? concluidaEm,
}) {
  return Demanda(
    id: id,
    demandanteId: 'dem-1',
    demandanteNome: 'Org Teste',
    demandanteTipo: TipoDemandante.empresa,
    titulo: 'Demanda $id',
    descricao: 'descrição',
    publicoAlvo: 'público',
    impacto: 'impacto',
    status: status,
    criadoEm: _base,
    professorId: 'prof-1',
    professorNome: 'Prof Teste',
    analiseIniciadaEm: analiseIniciadaEm,
    producaoIniciadaEm: producaoIniciadaEm,
    concluidaEm: concluidaEm,
  );
}

void main() {
  group('MetricasProfessor.calcular — contagens por status', () {
    test('classifica cada demanda no balde certo', () {
      final m = MetricasProfessor.calcular(
        professorId: 'prof-1',
        demandas: [
          _demanda(id: '1', status: StatusDemanda.emAnalise),
          _demanda(id: '2', status: StatusDemanda.emProducao),
          _demanda(id: '3', status: StatusDemanda.emProducao),
          _demanda(id: '4', status: StatusDemanda.concluida),
          // Cancelada não conta em nenhum balde de trabalho, mas continua
          // atribuída ao professor.
          _demanda(id: '5', status: StatusDemanda.cancelada),
        ],
      );

      expect(m.totalAtribuidas, 5);
      expect(m.emAnalise, 1);
      expect(m.emProducao, 2);
      expect(m.concluidas, 1);
      expect(m.emAberto, 3, reason: 'em análise + em produção');
    });

    test('lista vazia produz métricas zeradas sem médias', () {
      final m = MetricasProfessor.calcular(
        professorId: 'prof-1',
        demandas: const [],
      );

      expect(m.totalAtribuidas, 0);
      expect(m.tempoMedioEntrega, isNull);
      expect(m.tempoMedioAnalise, isNull);
      expect(m.taxaConclusao, isNull);
      expect(m.ultimaAtividade, isNull);
    });
  });

  group('MetricasProfessor.taxaConclusao', () {
    test('mede sobre o que foi assumido, ignorando o que está só em análise',
        () {
      final m = MetricasProfessor.calcular(
        professorId: 'prof-1',
        demandas: [
          _demanda(id: '1', status: StatusDemanda.concluida),
          _demanda(id: '2', status: StatusDemanda.concluida),
          _demanda(id: '3', status: StatusDemanda.emProducao),
          // Em análise não entra na base: ainda não houve compromisso.
          _demanda(id: '4', status: StatusDemanda.emAnalise),
          _demanda(id: '5', status: StatusDemanda.emAnalise),
        ],
      );

      expect(m.taxaConclusao, closeTo(2 / 3, 0.0001));
    });

    test('é nula quando nada foi assumido', () {
      final m = MetricasProfessor.calcular(
        professorId: 'prof-1',
        demandas: [_demanda(id: '1', status: StatusDemanda.emAnalise)],
      );

      expect(m.taxaConclusao, isNull);
    });
  });

  group('MetricasProfessor — médias de tempo', () {
    test('tempo médio de entrega é a média entre produção e conclusão', () {
      final m = MetricasProfessor.calcular(
        professorId: 'prof-1',
        demandas: [
          _demanda(
            id: '1',
            status: StatusDemanda.concluida,
            producaoIniciadaEm: _base,
            concluidaEm: _base.add(const Duration(days: 2)),
          ),
          _demanda(
            id: '2',
            status: StatusDemanda.concluida,
            producaoIniciadaEm: _base,
            concluidaEm: _base.add(const Duration(days: 4)),
          ),
        ],
      );

      expect(m.tempoMedioEntrega, const Duration(days: 3));
    });

    test('tempo médio de decisão vai da análise ao início da produção', () {
      final m = MetricasProfessor.calcular(
        professorId: 'prof-1',
        demandas: [
          _demanda(
            id: '1',
            status: StatusDemanda.emProducao,
            analiseIniciadaEm: _base,
            producaoIniciadaEm: _base.add(const Duration(hours: 6)),
          ),
        ],
      );

      expect(m.tempoMedioAnalise, const Duration(hours: 6));
    });

    test('descarta durações negativas de datas inconsistentes', () {
      // Conclusão ANTES do início da produção só acontece com dado corrompido
      // (relógio do cliente, migração manual). Entrar na média distorceria
      // permanentemente o indicador, então é descartada.
      final m = MetricasProfessor.calcular(
        professorId: 'prof-1',
        demandas: [
          _demanda(
            id: '1',
            status: StatusDemanda.concluida,
            producaoIniciadaEm: _base,
            concluidaEm: _base.subtract(const Duration(days: 1)),
          ),
        ],
      );

      expect(m.tempoMedioEntrega, isNull);
    });

    test('ignora demandas sem os dois marcos preenchidos', () {
      final m = MetricasProfessor.calcular(
        professorId: 'prof-1',
        demandas: [
          _demanda(
            id: '1',
            status: StatusDemanda.concluida,
            producaoIniciadaEm: _base,
            concluidaEm: _base.add(const Duration(days: 2)),
          ),
          // Concluída legada, sem `producaoIniciadaEm`.
          _demanda(
            id: '2',
            status: StatusDemanda.concluida,
            concluidaEm: _base.add(const Duration(days: 10)),
          ),
        ],
      );

      expect(m.tempoMedioEntrega, const Duration(days: 2));
    });
  });

  group('MetricasProfessor.ultimaAtividade', () {
    test('é o marco mais recente entre todas as demandas', () {
      final m = MetricasProfessor.calcular(
        professorId: 'prof-1',
        demandas: [
          _demanda(
            id: '1',
            status: StatusDemanda.concluida,
            analiseIniciadaEm: _base,
            concluidaEm: _base.add(const Duration(days: 1)),
          ),
          _demanda(
            id: '2',
            status: StatusDemanda.emProducao,
            producaoIniciadaEm: _base.add(const Duration(days: 5)),
          ),
        ],
      );

      expect(m.ultimaAtividade, _base.add(const Duration(days: 5)));
    });
  });

  group('formatarDuracao', () {
    test('escolhe a maior unidade significativa', () {
      expect(formatarDuracao(null), '—');
      expect(formatarDuracao(const Duration(seconds: 30)), '<1min');
      expect(formatarDuracao(const Duration(minutes: 12)), '12min');
      expect(
          formatarDuracao(const Duration(hours: 5, minutes: 20)), '5h 20min');
      expect(formatarDuracao(const Duration(days: 3, hours: 4)), '3d 4h');
    });
  });
}
