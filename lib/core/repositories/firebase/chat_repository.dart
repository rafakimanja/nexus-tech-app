import '../chat_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../constants/app_constants.dart';
import '../../exceptions/app_exception.dart';
import '../../exceptions/firestore_error_handler.dart';
import '../../models/chat.dart';
import '../../models/demanda.dart';
import '../../models/notificacao.dart';
import 'notificacao_repository.dart';

/// Chat 1:1 por demanda (UC11 R03).
///
/// **Ciclo de vida:** o chat nasce dentro da mesma transação que move a demanda
/// para `emProducao` ([criarNaTransacao], chamada por `FirebaseDemandaRepository`), e é
/// encerrado quando a demanda termina ([encerrar]). Nunca é criado pela UI —
/// isso garante que não exista conversa sem demanda assumida.
///
/// **Não lidas:** o contador vive no documento do chat (`naoLidas[id]`),
/// escrito na mesma transação da mensagem. Assim o badge da lista não precisa
/// varrer a subcoleção de mensagens.
class FirebaseChatRepository implements ChatRepository {
  @override
  Future<Chat?> buscarPorDemanda(String demandaId) => buscar(demandaId);
  final FirebaseFirestore _firestore;
  final FirebaseNotificacaoRepository _notificacoes;

  FirebaseChatRepository({
    FirebaseFirestore? firestore,
    FirebaseNotificacaoRepository? notificacaoRepository,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _notificacoes = notificacaoRepository ??
            FirebaseNotificacaoRepository(firestore: firestore);

  CollectionReference<Map<String, dynamic>> get _chats =>
      _firestore.collection(AppConstants.collectionChats);

  CollectionReference<Map<String, dynamic>> _mensagens(String chatId) =>
      _chats.doc(chatId).collection(AppConstants.subcollectionMensagens);

  // ! ===========================
  // ! CRIAÇÃO (UC11 R03)
  // ! ===========================

  /// Agenda a criação do chat dentro de uma transação já aberta.
  ///
  /// O ID do chat é o `demandaId`, então `tx.set` é idempotente: se a
  /// transação for repetida pelo SDK (contenção) ou se a demanda for reassumida
  /// depois de uma devolução, o mesmo documento é reescrito em vez de nascer
  /// uma conversa duplicada. `merge: true` preserva o histórico de não lidas
  /// e a última mensagem de uma conversa que já existia.
  ///
  /// Recebe [professorNome] explicitamente porque, no momento em que a demanda
  /// é assumida, o nome já está no documento — evita uma leitura extra do
  /// perfil dentro da transação (transações têm orçamento de leituras).
  void criarNaTransacao(
    Transaction tx, {
    required Demanda demanda,
    required String professorId,
    required String professorNome,
  }) {
    final ref = _chats.doc(demanda.id);
    tx.set(
      ref,
      {
        'demandaId': demanda.id,
        'tituloDemanda': demanda.titulo,
        'demandanteUid': demanda.demandanteId,
        'demandanteNome': demanda.demandanteNome,
        'professorUid': professorId,
        'professorNome': professorNome,
        'participantes': [demanda.demandanteId, professorId],
        'ativo': true,
        'criadoEm': DateTime.now().toIso8601String(),
        // Sem mensagens ainda: a de boas-vindas é escrita logo após o commit
        // (ver `registrarMensagemSistema`), porque uma transação não pode
        // escrever na subcoleção de um documento que ela mesma está criando
        // sem antes tê-lo lido.
        'naoLidas': {demanda.demandanteId: 0, professorId: 0},
      },
      SetOptions(merge: true),
    );
  }

  // ! ===========================
  // ! LEITURA
  // ! ===========================

  /// Conversas em que [id] participa, mais recentes primeiro.
  ///
  /// Ordena por `ultimaMensagemEm` — chats recém-criados têm esse campo nulo e
  /// o Firestore **omite documentos sem o campo do orderBy**. Por isso a
  /// mensagem de sistema de boas-vindas é obrigatória na criação: ela garante
  /// que todo chat tenha `ultimaMensagemEm` e apareça na lista.
  ///
  /// Exige índice composto (participantes ARRAY, ultimaMensagemEm DESC).
  @override
  Stream<List<Chat>> observarChats(String id) {
    return _chats
        .where('participantes', arrayContains: id)
        .orderBy('ultimaMensagemEm', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Chat.fromMap(d.id, d.data())).toList());
  }

  /// Observa um chat específico (cabeçalho da conversa, estado ativo/inativo).
  @override
  Stream<Chat?> observarChat(String chatId) {
    return _chats
        .doc(chatId)
        .snapshots()
        .map((doc) => doc.exists ? Chat.fromMap(doc.id, doc.data()!) : null);
  }

  /// Mensagens em ordem cronológica crescente (a mais antiga primeiro), que é
  /// a ordem em que a lista renderiza. O `limit` pega as N mais recentes —
  /// por isso a query desce por data e a lista é revertida na saída.
  @override
  Stream<List<Mensagem>> observarMensagens(String chatId) {
    return _mensagens(chatId)
        .orderBy('enviadaEm', descending: true)
        .limit(AppConstants.limiteMensagensChat)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Mensagem.fromMap(d.id, d.data()))
            .toList()
            .reversed
            .toList());
  }

  /// Busca pontual de um chat (usado ao abrir a conversa a partir da demanda).
  @override
  Future<Chat?> buscar(String chatId) async {
    try {
      final doc = await _chats.doc(chatId).get();
      if (!doc.exists) return null;
      return Chat.fromMap(doc.id, doc.data()!);
    } catch (e) {
      throw mapFirestoreError(e, recurso: 'Conversa');
    }
  }

  // ! ===========================
  // ! ENVIO
  // ! ===========================

  /// Envia uma mensagem.
  ///
  /// Tudo acontece numa transação: grava a mensagem, atualiza a prévia e o
  /// contador de não lidas do destinatário. Se falhar no meio, nada fica
  /// inconsistente (mensagem visível sem badge, ou badge sem mensagem).
  ///
  /// A notificação in-app só é criada quando o destinatário **não tinha** nada
  /// não lido nesse chat. Numa conversa ativa, avisar a cada mensagem entope a
  /// central; avisar na primeira de uma rajada dá o mesmo sinal sem o ruído.
  /// Ela sai fora da transação por ser best-effort (§2.5).
  @override
  Future<void> enviarMensagem({
    required String chatId,
    required String autorId,
    required String autorNome,
    required String texto,
  }) async {
    final conteudo = texto.trim();
    if (conteudo.isEmpty) {
      throw const ValidationException('Digite uma mensagem antes de enviar.');
    }
    if (conteudo.length > AppConstants.maxCaracteresMensagem) {
      throw const ValidationException(
        'Mensagem muito longa (máximo '
        '${AppConstants.maxCaracteresMensagem} caracteres).',
      );
    }

    try {
      String? destinatarioId;
      var precisaNotificar = false;
      var tituloDemanda = 'sua demanda';

      await _firestore.runTransaction((tx) async {
        final chatRef = _chats.doc(chatId);
        final snap = await tx.get(chatRef);
        if (!snap.exists) throw const NotFoundException('Conversa');

        final chat = Chat.fromMap(snap.id, snap.data()!);
        if (!chat.participantes.contains(autorId)) {
          throw const PermissionException();
        }
        if (!chat.ativo) {
          throw const ConflictException(
            'Esta conversa foi encerrada e não aceita novas mensagens.',
          );
        }

        final destino = chat.outroId(autorId);
        destinatarioId = destino;
        tituloDemanda = chat.tituloDemanda;
        precisaNotificar = chat.naoLidasDe(destino) == 0;

        final agora = DateTime.now();
        tx.set(_mensagens(chatId).doc(), {
          'autorUid': autorId,
          'autorNome': autorNome,
          'texto': conteudo,
          'enviadaEm': agora.toIso8601String(),
          'sistema': false,
        });

        tx.update(chatRef, {
          'ultimaMensagem': conteudo,
          'ultimaMensagemAutorUid': autorId,
          'ultimaMensagemEm': agora.toIso8601String(),
          // Valor calculado (e não FieldValue.increment) porque já lemos o
          // documento nesta transação: mantém a Rule capaz de validar o
          // resultado e evita depender de operador de servidor.
          'naoLidas.$destino': chat.naoLidasDe(destino) + 1,
          'naoLidas.$autorId': 0,
        });
      });

      if (precisaNotificar && destinatarioId != null) {
        await _notificacoes.enfileirar(
          destinatarioId: destinatarioId!,
          autorId: autorId,
          autorNome: autorNome,
          tipo: TipoNotificacao.novaMensagem,
          titulo: 'Nova mensagem sobre "$tituloDemanda"',
          corpo: '$autorNome: '
              '${conteudo.length > 90 ? "${conteudo.substring(0, 90)}…" : conteudo}',
          demandaId: chatId,
          chatId: chatId,
        );
      }
    } catch (e) {
      if (e is AppException) rethrow;
      throw mapFirestoreError(e, recurso: 'Mensagem');
    }
  }

  /// Escreve uma mensagem de sistema (marco na conversa) e atualiza a prévia.
  ///
  /// Best-effort por natureza: é decoração de um evento que já aconteceu
  /// (chat criado, demanda concluída). Não usa transação porque não há
  /// contador a incrementar — mensagens de sistema não geram não lidas.
  @override
  Future<void> registrarMensagemSistema({
    required String chatId,
    required String texto,
  }) async {
    try {
      final agora = DateTime.now();
      final batch = _firestore.batch();
      batch.set(_mensagens(chatId).doc(), {
        'autorUid': 'sistema',
        'autorNome': 'Nexus Tech',
        'texto': texto,
        'enviadaEm': agora.toIso8601String(),
        'sistema': true,
      });
      batch.update(_chats.doc(chatId), {
        'ultimaMensagem': texto,
        'ultimaMensagemAutorUid': 'sistema',
        'ultimaMensagemEm': agora.toIso8601String(),
      });
      await batch.commit();
    } catch (_) {
      // best-effort — ver docstring.
    }
  }

  // ! ===========================
  // ! LEITURA / ENCERRAMENTO
  // ! ===========================

  /// Zera o contador de não lidas de [id]. Chamado ao abrir a conversa.
  /// Best-effort: falhar aqui só deixa o badge desatualizado até a próxima
  /// abertura, e não vale interromper a leitura da conversa com um erro.
  @override
  Future<void> marcarComoLido({
    required String chatId,
    required String id,
  }) async {
    try {
      await _chats.doc(chatId).update({'naoLidas.$id': 0});
    } catch (_) {
      // best-effort — ver docstring.
    }
  }

  /// Congela a conversa (histórico continua legível, envio bloqueado).
  /// Chamado quando a demanda é concluída ou cancelada.
  @override
  Future<void> encerrar({
    required String chatId,
    required String motivo,
  }) async {
    try {
      await _chats.doc(chatId).update({'ativo': false});
      await registrarMensagemSistema(chatId: chatId, texto: motivo);
    } catch (_) {
      // best-effort: o encerramento é consequência de uma transição de status
      // que já foi commitada; as Rules impedem escrita indevida de qualquer forma.
    }
  }
}
