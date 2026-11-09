import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_tech/core/models/demanda.dart';
import 'package:nexus_tech/core/models/enums.dart';

void main() {
  group('StatusDemanda — transições do demandante', () {
    test('apenas "cadastrada" permite edição pelo demandante', () {
      expect(StatusDemanda.cadastrada.podeEditarDemandante, isTrue);
      expect(StatusDemanda.emAnalise.podeEditarDemandante, isFalse);
      expect(StatusDemanda.emProducao.podeEditarDemandante, isFalse);
      expect(StatusDemanda.concluida.podeEditarDemandante, isFalse);
      expect(StatusDemanda.cancelada.podeEditarDemandante, isFalse);
    });

    test('apenas "cadastrada" permite cancelamento pelo demandante', () {
      expect(StatusDemanda.cadastrada.podeCancelarDemandante, isTrue);
      expect(StatusDemanda.emAnalise.podeCancelarDemandante, isFalse);
      expect(StatusDemanda.emProducao.podeCancelarDemandante, isFalse);
      expect(StatusDemanda.concluida.podeCancelarDemandante, isFalse);
      expect(StatusDemanda.cancelada.podeCancelarDemandante, isFalse);
    });
  });

  group('StatusDemanda — labels exibidos', () {
    test('cada status tem label não-vazio e único', () {
      final labels = StatusDemanda.values.map((s) => s.label).toList();
      expect(labels.toSet().length, equals(labels.length),
          reason: 'labels duplicados quebrariam diferenciação visual');
      expect(labels.every((l) => l.isNotEmpty), isTrue);
    });
  });

  group('FiltroPeriodo.range', () {
    test('ultimos7Dias retorna início ~7 dias atrás, fim nulo', () {
      final range = FiltroPeriodo.ultimos7Dias.range;
      expect(range.fim, isNull);
      expect(range.inicio, isNotNull);
      final diff = DateTime.now().difference(range.inicio!);
      expect(diff.inDays, equals(7));
    });

    test('todasApos30Dias inverte: fim ~30 dias atrás, início nulo', () {
      final range = FiltroPeriodo.todasApos30Dias.range;
      expect(range.inicio, isNull);
      expect(range.fim, isNotNull);
      final diff = DateTime.now().difference(range.fim!);
      expect(diff.inDays, equals(30));
    });
  });

  group('StatusDemanda — máquina de estados (ciclo do professor)', () {
    test('cadastrada só transiciona para emAnalise ou cancelada', () {
      expect(
          StatusDemanda.cadastrada
              .podeTransicionarPara(StatusDemanda.emAnalise),
          isTrue);
      expect(
          StatusDemanda.cadastrada
              .podeTransicionarPara(StatusDemanda.cancelada),
          isTrue);
      expect(
          StatusDemanda.cadastrada
              .podeTransicionarPara(StatusDemanda.emProducao),
          isFalse);
      expect(
          StatusDemanda.cadastrada
              .podeTransicionarPara(StatusDemanda.concluida),
          isFalse);
    });

    test(
        'emAnalise transiciona para emProducao (assumir) ou cadastrada (rejeitar)',
        () {
      expect(
          StatusDemanda.emAnalise
              .podeTransicionarPara(StatusDemanda.emProducao),
          isTrue);
      expect(
          StatusDemanda.emAnalise
              .podeTransicionarPara(StatusDemanda.cadastrada),
          isTrue);
      expect(
          StatusDemanda.emAnalise.podeTransicionarPara(StatusDemanda.concluida),
          isFalse);
    });

    test('emProducao só transiciona para concluida', () {
      expect(
          StatusDemanda.emProducao
              .podeTransicionarPara(StatusDemanda.concluida),
          isTrue);
      expect(
          StatusDemanda.emProducao
              .podeTransicionarPara(StatusDemanda.cadastrada),
          isFalse);
      expect(
          StatusDemanda.emProducao
              .podeTransicionarPara(StatusDemanda.cancelada),
          isFalse);
    });

    test('concluida e cancelada são terminais', () {
      for (final destino in StatusDemanda.values) {
        expect(StatusDemanda.concluida.podeTransicionarPara(destino), isFalse);
        expect(StatusDemanda.cancelada.podeTransicionarPara(destino), isFalse);
      }
    });

    test('getters de ação do professor refletem o estado correto', () {
      expect(StatusDemanda.cadastrada.podeMarcarAnalise, isTrue);
      expect(StatusDemanda.emAnalise.podeMarcarAnalise, isFalse);

      expect(StatusDemanda.emAnalise.podeAssumir, isTrue);
      expect(StatusDemanda.emAnalise.podeRejeitar, isTrue);
      expect(StatusDemanda.emProducao.podeAssumir, isFalse);

      expect(StatusDemanda.emProducao.podeConcluir, isTrue);
      expect(StatusDemanda.concluida.podeConcluir, isFalse);
    });

    test('UC08 R01 — apenas cadastrada e emProducao são visíveis na prateleira',
        () {
      expect(StatusDemanda.cadastrada.visivelNaPrateleira, isTrue);
      expect(StatusDemanda.emProducao.visivelNaPrateleira, isTrue);
      expect(StatusDemanda.emAnalise.visivelNaPrateleira, isFalse);
      expect(StatusDemanda.concluida.visivelNaPrateleira, isFalse);
      expect(StatusDemanda.cancelada.visivelNaPrateleira, isFalse);
    });
  });

  group('Demanda.analiseExpirou (UC09 R04)', () {
    Demanda base({
      required StatusDemanda status,
      DateTime? analiseExpiraEm,
    }) =>
        Demanda(
          id: 'd1',
          demandanteId: 'u1',
          demandanteNome: 'Fulano',
          demandanteTipo: TipoDemandante.empresa,
          titulo: 'Título',
          descricao: 'Descrição',
          publicoAlvo: 'Geral',
          impacto: 'Impacto',
          status: status,
          criadoEm: DateTime(2025, 1, 1),
          analiseExpiraEm: analiseExpiraEm,
        );

    test('expira quando em análise e prazo já passou', () {
      final d = base(
        status: StatusDemanda.emAnalise,
        analiseExpiraEm: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(d.analiseExpirou, isTrue);
    });

    test('não expira quando o prazo ainda está no futuro', () {
      final d = base(
        status: StatusDemanda.emAnalise,
        analiseExpiraEm: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(d.analiseExpirou, isFalse);
    });

    test('não expira fora do estado emAnalise, mesmo com prazo vencido', () {
      final d = base(
        status: StatusDemanda.emProducao,
        analiseExpiraEm: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(d.analiseExpirou, isFalse);
    });
  });
}
