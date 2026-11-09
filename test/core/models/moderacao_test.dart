import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_tech/core/constants/app_constants.dart';
import 'package:nexus_tech/core/models/demandante.dart';
import 'package:nexus_tech/core/models/denuncia.dart';
import 'package:nexus_tech/core/models/enums.dart';
import 'package:nexus_tech/core/models/notificacao.dart';

Demandante _demandante({int strikes = 0, bool banido = false}) => Demandante(
      id: 'dem-1',
      email: 'contato@org.com',
      nome: 'Org Teste',
      criadoEm: DateTime(2026, 1, 1),
      telefone: '51999999999',
      tipo: TipoDemandante.ong,
      cpfCnpj: '11222333000181',
      endereco: 'Rua A, 100',
      strikes: strikes,
      banido: banido,
    );

void main() {
  group('Demandante — strikes e banimento', () {
    test('conta quantas advertências faltam para a suspensão', () {
      expect(_demandante().strikesRestantes, AppConstants.strikesParaBanimento);
      expect(_demandante(strikes: 1).strikesRestantes,
          AppConstants.strikesParaBanimento - 1);
      expect(_demandante(strikes: 2).strikesRestantes, 1);
    });

    test('conta banida não tem advertências restantes', () {
      final d = _demandante(
        strikes: AppConstants.strikesParaBanimento,
        banido: true,
      );
      expect(d.strikesRestantes, 0);
    });

    test(
        'nunca devolve valor negativo, mesmo com ajuste manual acima do limite',
        () {
      // O admin pode ajustar strikes manualmente; o contador da UI não pode
      // virar negativo por causa disso.
      final d = _demandante(strikes: 10);
      expect(d.strikesRestantes, greaterThanOrEqualTo(0));
    });

    test('round-trip pelo mapa preserva o estado de moderação', () {
      final original = _demandante(strikes: 2);
      final copia = Demandante.fromMap(original.toMap());

      expect(copia.strikes, 2);
      expect(copia.banido, isFalse);
      expect(copia.cpfCnpj, original.cpfCnpj);
    });

    test('conta legada sem os campos de moderação nasce limpa', () {
      final d = Demandante.fromMap({
        'uid': 'dem-legado',
        'email': 'a@b.com',
        'nome': 'Antigo',
        'role': 'demandante',
        'criadoEm': '2025-01-01T00:00:00.000',
        'telefone': '51999999999',
        'tipo': 'empresa',
        'cpfCnpj': '11222333000181',
        'endereco': 'Rua B',
      });

      expect(d.strikes, 0);
      expect(d.banido, isFalse);
      expect(d.banidoEm, isNull);
    });
  });

  group('StatusDenuncia e MotivoDenuncia', () {
    test('desserializam pelo nome persistido', () {
      expect(StatusDenuncia.from('procedente'), StatusDenuncia.procedente);
      expect(MotivoDenuncia.from('spam'), MotivoDenuncia.spam);
    });

    test('valor desconhecido cai num padrão seguro', () {
      // Um valor gravado por versão futura não pode quebrar a fila do admin.
      expect(StatusDenuncia.from('valor_novo'), StatusDenuncia.pendente);
      expect(StatusDenuncia.from(null), StatusDenuncia.pendente);
      expect(MotivoDenuncia.from('outro_qualquer'), MotivoDenuncia.outro);
    });

    test('todo status e motivo tem label não vazio', () {
      for (final s in StatusDenuncia.values) {
        expect(s.label, isNotEmpty);
      }
      for (final m in MotivoDenuncia.values) {
        expect(m.label, isNotEmpty);
      }
    });
  });

  group('TipoNotificacao', () {
    test('desserializa pelo nome e cai em generica se desconhecido', () {
      expect(
          TipoNotificacao.from('novaMensagem'), TipoNotificacao.novaMensagem);
      expect(
          TipoNotificacao.from('tipo_inexistente'), TipoNotificacao.generica);
      expect(TipoNotificacao.from(null), TipoNotificacao.generica);
    });

    test('cada tipo aponta para o destino de navegação certo', () {
      expect(TipoNotificacao.novaMensagem.destino, DestinoNotificacao.chat);
      expect(TipoNotificacao.demandaEmProducao.destino,
          DestinoNotificacao.demanda);
      expect(
          TipoNotificacao.demandaConcluida.destino, DestinoNotificacao.demanda);
      expect(TipoNotificacao.denunciaRecebida.destino,
          DestinoNotificacao.denuncia);
      expect(TipoNotificacao.contaBanida.destino, DestinoNotificacao.perfil);
      expect(TipoNotificacao.generica.destino, DestinoNotificacao.nenhum);
    });

    test('nenhum tipo fica sem destino definido', () {
      for (final t in TipoNotificacao.values) {
        expect(() => t.destino, returnsNormally);
        expect(() => t.icone, returnsNormally);
        expect(() => t.cor, returnsNormally);
      }
    });
  });

  group('Notificacao.fromMap', () {
    test('desserializa um documento completo', () {
      final n = Notificacao.fromMap('n1', {
        'destinatarioUid': 'dem-1',
        'autorUid': 'prof-1',
        'autorNome': 'Ana Souza',
        'tipo': 'demandaEmProducao',
        'titulo': 'Sua demanda foi aceita!',
        'corpo': 'Ana Souza assumiu "Site".',
        'demandaId': 'd1',
        'chatId': 'd1',
        'lida': false,
        'enviada': false,
        'criadoEm': '2026-03-11T10:00:00.000',
      });

      expect(n.tipo, TipoNotificacao.demandaEmProducao);
      expect(n.lida, isFalse);
      expect(n.chatId, 'd1');
    });

    test('campos ausentes assumem padrões em vez de quebrar', () {
      final n = Notificacao.fromMap('n2', {
        'destinatarioUid': 'dem-1',
        'criadoEm': '2026-03-11T10:00:00.000',
      });

      expect(n.tipo, TipoNotificacao.generica);
      expect(n.lida, isFalse);
      expect(n.enviada, isFalse);
      expect(n.titulo, isNotEmpty);
    });
  });

  group('Denuncia', () {
    test('nasce pendente e round-trip preserva o julgamento', () {
      final julgada = Denuncia(
        id: 'd1__prof1',
        demandaId: 'd1',
        tituloDemanda: 'Site',
        demandanteId: 'dem-1',
        demandanteNome: 'Org',
        professorId: 'prof-1',
        professorNome: 'Ana',
        motivo: MotivoDenuncia.spam,
        descricao: 'Conteúdo repetido em várias demandas.',
        status: StatusDenuncia.procedente,
        criadoEm: DateTime(2026, 3, 10),
        analisadaEm: DateTime(2026, 3, 11),
        analisadaPorId: 'admin-1',
        analisadaPorNome: 'Karen',
        parecerAdmin: 'Confirmado.',
        strikeAplicado: true,
      );

      final copia = Denuncia.fromMap(julgada.id, julgada.toMap());

      expect(copia.pendente, isFalse);
      expect(copia.status, StatusDenuncia.procedente);
      expect(copia.strikeAplicado, isTrue);
      expect(copia.analisadaPorNome, 'Karen');
    });
  });
}
