import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_tech/core/models/chat.dart';

Chat _chat({
  Map<String, int> naoLidas = const {},
  bool ativo = true,
  DateTime? ultimaMensagemEm,
}) {
  return Chat(
    id: 'demanda-1',
    demandaId: 'demanda-1',
    tituloDemanda: 'Site institucional',
    demandanteId: 'dem-1',
    demandanteNome: 'Prefeitura de Osório',
    professorId: 'prof-1',
    professorNome: 'Ana Souza',
    participantes: const ['dem-1', 'prof-1'],
    naoLidas: naoLidas,
    criadoEm: DateTime(2026, 3, 10),
    ultimaMensagemEm: ultimaMensagemEm,
    ativo: ativo,
  );
}

void main() {
  group('Chat — ponto de vista de cada participante', () {
    test('outroNome devolve o interlocutor de quem pergunta', () {
      final chat = _chat();
      expect(chat.outroNome('dem-1'), 'Ana Souza');
      expect(chat.outroNome('prof-1'), 'Prefeitura de Osório');
    });

    test('outroId devolve o id do interlocutor', () {
      final chat = _chat();
      expect(chat.outroId('dem-1'), 'prof-1');
      expect(chat.outroId('prof-1'), 'dem-1');
    });
  });

  group('Chat.naoLidasDe', () {
    test('lê o contador do participante', () {
      final chat = _chat(naoLidas: const {'dem-1': 3, 'prof-1': 0});
      expect(chat.naoLidasDe('dem-1'), 3);
      expect(chat.naoLidasDe('prof-1'), 0);
    });

    test('id ausente do mapa conta zero', () {
      // Chats criados antes de o contador existir não têm o campo. O badge
      // precisa mostrar "nada pendente", não quebrar.
      expect(_chat().naoLidasDe('dem-1'), 0);
    });
  });

  group('Chat.fromMap — tolerância a documentos legados', () {
    test('desserializa um documento completo', () {
      final chat = Chat.fromMap('demanda-9', {
        'demandaId': 'demanda-9',
        'tituloDemanda': 'App de agendamento',
        'demandanteUid': 'dem-9',
        'demandanteNome': 'ONG Mar',
        'professorUid': 'prof-9',
        'professorNome': 'Carlos Lima',
        'participantes': ['dem-9', 'prof-9'],
        'ultimaMensagem': 'Combinado!',
        'ultimaMensagemAutorUid': 'prof-9',
        'ultimaMensagemEm': '2026-03-12T14:30:00.000',
        'naoLidas': {'dem-9': 2, 'prof-9': 0},
        'ativo': false,
        'criadoEm': '2026-03-10T08:00:00.000',
      });

      expect(chat.tituloDemanda, 'App de agendamento');
      expect(chat.ativo, isFalse);
      expect(chat.naoLidasDe('dem-9'), 2);
      expect(chat.ultimaMensagemEm, DateTime(2026, 3, 12, 14, 30));
    });

    test('contadores gravados como num viram int', () {
      // `FieldValue.increment` pode devolver o contador como num.
      final chat = Chat.fromMap('c1', {
        'demandanteUid': 'a',
        'professorUid': 'b',
        'participantes': ['a', 'b'],
        'naoLidas': {'a': 4.0},
        'criadoEm': '2026-03-10T08:00:00.000',
      });

      expect(chat.naoLidasDe('a'), 4);
      expect(chat.naoLidasDe('a'), isA<int>());
    });

    test('documento mínimo assume padrões seguros', () {
      final chat = Chat.fromMap('demanda-x', {
        'demandanteUid': 'a',
        'professorUid': 'b',
        'criadoEm': '2026-03-10T08:00:00.000',
      });

      expect(chat.demandaId, 'demanda-x', reason: 'cai no id do documento');
      expect(chat.ativo, isTrue);
      expect(chat.participantes, isEmpty);
      expect(chat.ultimaMensagem, isNull);
    });

    test('data inválida não derruba a desserialização', () {
      final chat = Chat.fromMap('c1', {
        'demandanteUid': 'a',
        'professorUid': 'b',
        'ultimaMensagemEm': 'não é uma data',
        'criadoEm': '2026-03-10T08:00:00.000',
      });

      expect(chat.ultimaMensagemEm, isNull);
    });
  });

  group('Mensagem.fromMap', () {
    test('marca mensagens de sistema', () {
      final m = Mensagem.fromMap('m1', {
        'autorUid': 'sistema',
        'autorNome': 'Nexus Tech',
        'texto': 'Demanda assumida.',
        'enviadaEm': '2026-03-11T10:00:00.000',
        'sistema': true,
      });

      expect(m.sistema, isTrue);
      expect(m.enviadaEm, DateTime(2026, 3, 11, 10));
    });

    test('mensagem comum não é de sistema por padrão', () {
      final m = Mensagem.fromMap('m2', {
        'autorUid': 'prof-1',
        'autorNome': 'Ana',
        'texto': 'Bom dia!',
        'enviadaEm': '2026-03-11T10:05:00.000',
      });

      expect(m.sistema, isFalse);
      expect(m.texto, 'Bom dia!');
    });
  });
}
