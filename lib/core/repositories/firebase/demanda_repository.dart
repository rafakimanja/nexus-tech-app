import '../../models/criar_demanda.dart';
import '../demanda_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../constants/app_constants.dart';
import '../../exceptions/app_exception.dart';
import '../../exceptions/firestore_error_handler.dart';
import '../../models/anexo.dart';
import '../../models/demanda.dart';
import '../../models/notificacao.dart';
import 'chat_repository.dart';
import 'notificacao_repository.dart';

class FirebaseDemandaRepository implements DemandaRepository {
  final Set<String> _reconciliando = {};
  final FirebaseFirestore _firestore;

  /// Colaboradores dos efeitos do ciclo de vida: cada transição de status
  /// abre/encerra a conversa e avisa a outra ponta. Injetáveis para teste.
  final FirebaseChatRepository _chats;
  final FirebaseNotificacaoRepository _notificacoes;

  FirebaseDemandaRepository({
    FirebaseFirestore? firestore,
    FirebaseChatRepository? chatRepository,
    FirebaseNotificacaoRepository? notificacaoRepository,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        // Os colaboradores herdam a MESMA instância do Firestore: a criação do
        // chat acontece dentro da transação aberta aqui, e uma transação não
        // atravessa duas instâncias. Sem isso, injetar um emulador no
        // repositório de demandas deixaria o chat apontando para produção.
        _chats = chatRepository ??
            FirebaseChatRepository(
              firestore: firestore,
              notificacaoRepository: notificacaoRepository ??
                  FirebaseNotificacaoRepository(firestore: firestore),
            ),
        _notificacoes = notificacaoRepository ??
            FirebaseNotificacaoRepository(firestore: firestore);

  static const String _collectionDemandas = 'demandas';
  static const String _subcollectionAnexos = 'anexos';
  static const String _collectionAuditLog = 'audit_logs';

  CollectionReference<Map<String, dynamic>> get _demandas =>
      _firestore.collection(_collectionDemandas);

  CollectionReference<Map<String, dynamic>> _anexos(String demandaId) =>
      _demandas.doc(demandaId).collection(_subcollectionAnexos);

  // ! ===========================
  // ! UC15 - CADASTRAR DEMANDA
  // ! ===========================

  /// Cria nova demanda. Retorna ID gerado pelo Firestore.
  /// Status inicial: cadastrada (UC15 R03).
  ///
  /// Se [originalCanceladaId] for fornecido, a operação é uma REPUBLICAÇÃO:
  /// cria a nova demanda E marca a original com `republicadaComoId` na
  /// mesma transação atômica (WriteBatch). Se uma operação falhar, nenhuma
  /// é persistida — impede estados inconsistentes onde a nova demanda
  /// existe mas a original ainda mostra o botão de republicar.
  @override
  Future<String> criar(
    CriarDemanda dados, {
    String? originalCanceladaId,
  }) async {
    try {
      final novaRef = _demandas.doc();
      final demanda =
          dados.materializar(id: novaRef.id, criadoEm: DateTime.now());
      if (originalCanceladaId == null) {
        // ----- fluxo simples: criação normal -----
        await novaRef.set(demanda.toMap());

        // UC15 R05: registro em log de auditoria
        await _registrarAuditoria(
          demandaId: novaRef.id,
          acao: 'criar',
          autorId: demanda.demandanteId,
        );

        return novaRef.id;
      }

      // ----- fluxo de republicação: batch atômica -----
      // Gera referência (e ID) antes de escrever para podermos usá-lo
      // no update da demanda original na mesma batch.
      final originalRef = _demandas.doc(originalCanceladaId);

      final batch = _firestore.batch();
      batch.set(novaRef, demanda.toMap());
      batch.update(originalRef, {'republicadaComoId': novaRef.id});

      await batch.commit();

      await _registrarAuditoria(
        demandaId: novaRef.id,
        acao: 'republicar',
        autorId: demanda.demandanteId,
        metadados: {'originalCanceladaId': originalCanceladaId},
      );

      return novaRef.id;
    } catch (e) {
      throw mapFirestoreError(e, recurso: 'Demanda');
    }
  }

  // ! ===========================
  // ! UC17 - EDITAR DEMANDA
  // ! ===========================

  /// Atualiza dados da demanda. Validação de status acontece no provider/UI;
  /// aqui apenas executa a operação.
  @override
  Future<void> atualizar({
    required String id,
    required String autorId,
    required String titulo,
    required String descricao,
    required String publicoAlvo,
    required String impacto,
  }) async {
    try {
      final agora = DateTime.now().toIso8601String();
      await _demandas.doc(id).update({
        'titulo': titulo,
        'tituloLower': titulo.toLowerCase(),
        'descricao': descricao,
        'publicoAlvo': publicoAlvo,
        'impacto': impacto,
        'atualizadoEm': agora,
      });

      // UC17 R04: log de auditoria
      await _registrarAuditoria(
        demandaId: id,
        acao: 'editar',
        autorId: autorId,
      );
    } catch (e) {
      throw mapFirestoreError(e, recurso: 'Demanda');
    }
  }

  // ! ===========================
  // ! UC16 - CANCELAR DEMANDA
  // ! ===========================

  /// Soft-delete: marca como cancelada e preserva o registro.
  /// Decisão arquitetural: NÃO removemos o documento porque
  /// (a) auditoria precisa do histórico;
  /// (b) o demandante ainda quer ver na lista "Minhas Demandas" (UC21 R02).
  @override
  Future<void> cancelar({
    required String id,
    required String autorId,
    required String motivo,
  }) async {
    try {
      // Lê antes de escrever para saber se havia um professor envolvido — é
      // ele quem precisa ser avisado, e é o chat dele que precisa encerrar.
      final snap = await _demandas.doc(id).get();
      final anterior =
          snap.exists ? Demanda.fromMap(snap.id, snap.data()!) : null;

      final agora = DateTime.now().toIso8601String();
      await _demandas.doc(id).update({
        'status': StatusDemanda.cancelada.name,
        'motivoCancelamento': motivo,
        'canceladoEm': agora,
      });

      await _registrarAuditoria(
        demandaId: id,
        acao: 'cancelar',
        autorId: autorId,
        metadados: {'motivo': motivo},
      );

      if (anterior?.professorId != null) {
        await _notificacoes.enfileirar(
          destinatarioId: anterior!.professorId!,
          autorId: autorId,
          autorNome: anterior.demandanteNome,
          tipo: TipoNotificacao.demandaCancelada,
          titulo: 'Demanda cancelada pelo demandante',
          corpo: '"${anterior.titulo}" foi cancelada. Motivo: $motivo',
          demandaId: id,
        );
        await _chats.encerrar(
          chatId: id,
          motivo: 'Demanda cancelada pelo demandante. '
              'A conversa fica disponível apenas para consulta.',
        );
      }
    } catch (e) {
      throw mapFirestoreError(e, recurso: 'Demanda');
    }
  }

  // ! ===========================
  // ! UC21 - LISTAR DEMANDAS DO DEMANDANTE
  // ! ===========================

  /// Lista demandas do demandante em tempo real.
  /// Snapshots() porque UC21 exige atualização em tempo real quando o
  /// status mudar (ex: professor aceita → demandante vê o status mudar).
  ///
  /// Filtros aplicados server-side via where clauses. Filtros são acumulativos.
  ///
  /// Os filtros compostos exigem índice no Firestore — ver firestore.indexes.json.
  @override
  Stream<List<Demanda>> listarDoDemandante({
    required String demandanteId,
    StatusDemanda? filtroStatus,
    FiltroPeriodo? filtroPeriodo,
  }) {
    Query<Map<String, dynamic>> query =
        _demandas.where('demandanteUid', isEqualTo: demandanteId);

    if (filtroStatus != null) {
      query = query.where('status', isEqualTo: filtroStatus.name);
    }

    if (filtroPeriodo != null) {
      final range = filtroPeriodo.range;
      if (range.inicio != null) {
        query = query.where(
          'criadoEm',
          isGreaterThanOrEqualTo: range.inicio!.toIso8601String(),
        );
      }
      if (range.fim != null) {
        query = query.where(
          'criadoEm',
          isLessThan: range.fim!.toIso8601String(),
        );
      }
    }

    query = query.orderBy('criadoEm', descending: true);

    return query.snapshots().map(
          (snap) =>
              snap.docs.map((d) => Demanda.fromMap(d.id, d.data())).toList(),
        );
  }

  /// Busca uma demanda específica por ID. Stream para tempo real.
  @override
  Stream<Demanda?> observar(String id) {
    return _demandas.doc(id).snapshots().map((doc) {
      if (!doc.exists) return null;
      return Demanda.fromMap(doc.id, doc.data()!);
    });
  }

  // ! ===========================
  // ! UC08 - PRATELEIRA DO PROFESSOR
  // ! ===========================

  /// Lista a prateleira pública (UC08) em tempo real.
  /// UC08 R01: apenas demandas `cadastrada` e `emProducao` são exibidas.
  /// Demandas `emAnalise` somem da prateleira (UC09) por não estarem nesse
  /// conjunto; canceladas/concluídas idem.
  ///
  /// Exige índice composto (status ASC, criadoEm DESC) — ver
  /// firestore.indexes.json. A busca textual (título/descrição) é aplicada
  /// client-side no provider, coerente com a decisão de §7.3 da arquitetura.
  @override
  Stream<List<Demanda>> listarPrateleira() {
    return _demandas
        .where('status', whereIn: [
          StatusDemanda.cadastrada.name,
          StatusDemanda.emProducao.name,
        ])
        .orderBy('criadoEm', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => Demanda.fromMap(d.id, d.data())).toList(),
        );
  }

  /// Lista as demandas atribuídas a um professor ("Minhas Demandas" do
  /// professor — UC09/UC10/UC11/UC12). Em tempo real, pois o status muda
  /// durante a sessão. Filtros server-side acumulativos, espelhando
  /// [listarDoDemandante]. Exige índices compostos por `professorId`.
  @override
  Stream<List<Demanda>> listarDoProfessor({
    required String professorId,
    StatusDemanda? filtroStatus,
    FiltroPeriodo? filtroPeriodo,
  }) {
    Query<Map<String, dynamic>> query =
        _demandas.where('professorUid', isEqualTo: professorId);

    if (filtroStatus != null) {
      query = query.where('status', isEqualTo: filtroStatus.name);
    }

    if (filtroPeriodo != null) {
      final range = filtroPeriodo.range;
      if (range.inicio != null) {
        query = query.where(
          'criadoEm',
          isGreaterThanOrEqualTo: range.inicio!.toIso8601String(),
        );
      }
      if (range.fim != null) {
        query = query.where(
          'criadoEm',
          isLessThan: range.fim!.toIso8601String(),
        );
      }
    }

    query = query.orderBy('criadoEm', descending: true);

    return query.snapshots().map(
      (snap) {
        final lista =
            snap.docs.map((d) => Demanda.fromMap(d.id, d.data())).toList();
        for (final demanda in lista) {
          if (demanda.analiseExpirou && _reconciliando.add(demanda.id)) {
            rejeitarAnalise(
                    demandaId: demanda.id,
                    professorId: professorId,
                    automatico: true)
                .catchError((Object _) {})
                .whenComplete(() => _reconciliando.remove(demanda.id));
          }
        }
        return lista;
      },
    );
  }

  // ! ===========================
  // ! UC09/UC10/UC11/UC12 - TRANSIÇÕES DE STATUS (PROFESSOR)
  // ! ===========================
  //
  // Todas as transições usam runTransaction: lê o estado atual, valida a
  // máquina de estados (StatusDemanda.podeTransicionarPara) e a propriedade
  // sobre a demanda DENTRO da transação, e só então escreve. Isso garante
  // serializabilidade — se dois professores agem ao mesmo tempo, apenas um
  // commit vence; o outro vê o estado já alterado e recebe ConflictException.
  // As Firestore Rules são a camada de segurança equivalente no servidor.

  /// UC09 — Marca a demanda para análise (`cadastrada` -> `emAnalise`),
  /// associa o professor e agenda a janela de 24h ([AppConstants.janelaAnalise]).
  @override
  Future<void> marcarParaAnalise({
    required String demandaId,
    required String professorId,
    required String professorNome,
  }) async {
    try {
      late Demanda emAnalise;
      await _firestore.runTransaction((tx) async {
        final ref = _demandas.doc(demandaId);
        final snap = await tx.get(ref);
        if (!snap.exists) throw const NotFoundException('Demanda');

        final atual = Demanda.fromMap(snap.id, snap.data()!);
        if (!atual.status.podeMarcarAnalise) {
          throw const ConflictException(
            'Esta demanda não está mais disponível para análise.',
          );
        }
        emAnalise = atual;

        final agora = DateTime.now();
        tx.update(ref, {
          'status': StatusDemanda.emAnalise.name,
          'professorUid': professorId,
          'professorNome': professorNome,
          'analiseIniciadaEm': agora.toIso8601String(),
          'analiseExpiraEm':
              agora.add(AppConstants.janelaAnalise).toIso8601String(),
          'atualizadoEm': agora.toIso8601String(),
        });
      });

      await _registrarAuditoria(
        demandaId: demandaId,
        acao: 'marcar_analise',
        autorId: professorId,
      );

      await _notificacoes.enfileirar(
        destinatarioId: emAnalise.demandanteId,
        autorId: professorId,
        autorNome: professorNome,
        tipo: TipoNotificacao.demandaEmAnalise,
        titulo: 'Sua demanda está em análise',
        corpo: '$professorNome está avaliando "${emAnalise.titulo}". '
            'Você será avisado assim que houver uma decisão.',
        demandaId: demandaId,
      );
    } catch (e) {
      if (e is AppException) rethrow;
      throw mapFirestoreError(e, recurso: 'Demanda');
    }
  }

  /// UC10 — Devolve a demanda em análise para a prateleira
  /// (`emAnalise` -> `cadastrada`) e desassocia o professor.
  ///
  /// [automatico] indica rollback por expiração da janela de 24h (UC09 R04),
  /// diferenciado na auditoria. Tanto a rejeição manual quanto o rollback só
  /// podem ser feitos pelo professor associado (ou, no futuro, pela Cloud
  /// Function de expiração via privilégio de admin).
  @override
  Future<void> rejeitarAnalise({
    required String demandaId,
    required String professorId,
    bool automatico = false,
  }) async {
    try {
      late Demanda devolvida;
      await _firestore.runTransaction((tx) async {
        final ref = _demandas.doc(demandaId);
        final snap = await tx.get(ref);
        if (!snap.exists) throw const NotFoundException('Demanda');

        final atual = Demanda.fromMap(snap.id, snap.data()!);
        if (!atual.status.podeRejeitar || atual.professorId != professorId) {
          throw const ConflictException(
            'Esta demanda não está mais em análise por você.',
          );
        }
        devolvida = atual;

        tx.update(ref, {
          'status': StatusDemanda.cadastrada.name,
          'professorUid': null,
          'professorNome': null,
          'analiseIniciadaEm': null,
          'analiseExpiraEm': null,
          'atualizadoEm': DateTime.now().toIso8601String(),
        });
      });

      await _registrarAuditoria(
        demandaId: demandaId,
        acao: automatico ? 'rollback_analise' : 'rejeitar',
        autorId: professorId,
      );

      // O demandante precisa saber que a demanda voltou a ficar disponível —
      // e a mensagem muda conforme a devolução tenha sido decisão do professor
      // ou expiração da janela de 24h, porque a leitura do fato é diferente.
      await _notificacoes.enfileirar(
        destinatarioId: devolvida.demandanteId,
        autorId: professorId,
        autorNome: devolvida.professorNome ?? 'Professor',
        tipo: TipoNotificacao.demandaDevolvida,
        titulo: 'Sua demanda voltou para a prateleira',
        corpo: automatico
            ? '"${devolvida.titulo}" não foi assumida dentro do prazo de '
                'análise e voltou a ficar visível para todos os professores.'
            : '"${devolvida.titulo}" foi devolvida à prateleira e segue '
                'disponível para outros professores.',
        demandaId: demandaId,
      );
    } catch (e) {
      if (e is AppException) rethrow;
      throw mapFirestoreError(e, recurso: 'Demanda');
    }
  }

  /// UC11 — Assume a demanda (`emAnalise` -> `emProducao`).
  ///
  /// Esta é a transição que **abre o canal de comunicação**: a mesma transação
  /// que muda o status cria o documento do chat (UC11 R03). Fazer as duas
  /// coisas juntas elimina o estado em que a demanda está em produção mas o
  /// demandante não tem como falar com o professor — o caso que o usuário
  /// notaria e não teria como resolver sozinho.
  ///
  /// A mensagem de boas-vindas é escrita **depois** do commit, e não dentro
  /// dele: a transação já está criando o documento do chat, e escrever numa
  /// subcoleção de um documento criado na própria transação depende de uma
  /// leitura que ainda não existe. Como a mensagem também é o que dá ao chat
  /// seu primeiro `ultimaMensagemEm` (campo pelo qual a lista ordena), ela é
  /// reenviada de forma idempotente caso falhe — ver `ChatProvider`.
  @override
  Future<void> assumir({
    required String demandaId,
    required String professorId,
  }) async {
    try {
      late Demanda assumida;
      await _firestore.runTransaction((tx) async {
        final ref = _demandas.doc(demandaId);
        final snap = await tx.get(ref);
        if (!snap.exists) throw const NotFoundException('Demanda');

        final atual = Demanda.fromMap(snap.id, snap.data()!);
        if (!atual.status.podeAssumir || atual.professorId != professorId) {
          throw const ConflictException(
            'Esta demanda não está mais em análise por você.',
          );
        }
        assumida = atual;

        final agora = DateTime.now();
        tx.update(ref, {
          'status': StatusDemanda.emProducao.name,
          'producaoIniciadaEm': agora.toIso8601String(),
          // A janela de análise deixa de fazer sentido após a assunção.
          'analiseExpiraEm': null,
          'atualizadoEm': agora.toIso8601String(),
        });

        // UC11 R03 — chat criado junto com a assunção (ver docstring).
        _chats.criarNaTransacao(
          tx,
          demanda: atual,
          professorId: professorId,
          professorNome: atual.professorNome ?? 'Professor',
        );
      });

      await _registrarAuditoria(
        demandaId: demandaId,
        acao: 'assumir',
        autorId: professorId,
      );

      await _chats.registrarMensagemSistema(
        chatId: demandaId,
        texto: '${assumida.professorNome ?? "O professor"} assumiu a demanda '
            '"${assumida.titulo}". Use este canal para alinhar detalhes, '
            'prazos e entregas.',
      );

      // UC11 R04 — aviso ao demandante.
      await _notificacoes.enfileirar(
        destinatarioId: assumida.demandanteId,
        autorId: professorId,
        autorNome: assumida.professorNome ?? 'Professor',
        tipo: TipoNotificacao.demandaEmProducao,
        titulo: 'Sua demanda foi aceita!',
        corpo: '${assumida.professorNome ?? "Um professor"} assumiu '
            '"${assumida.titulo}". O chat com o professor já está disponível.',
        demandaId: demandaId,
        chatId: demandaId,
      );
    } catch (e) {
      if (e is AppException) rethrow;
      throw mapFirestoreError(e, recurso: 'Demanda');
    }
  }

  /// UC12 — Conclui a demanda (`emProducao` -> `concluida`), registrando a
  /// descrição da solução e a data de entrega. Os anexos da entrega são
  /// enviados ANTES desta chamada (são o entregável). Libera a avaliação do
  /// demandante (derivada do status `concluida`) e enfileira a notificação.
  @override
  Future<void> concluir({
    required String demandaId,
    required String professorId,
    required String descricaoSolucao,
  }) async {
    try {
      late Demanda concluida;
      await _firestore.runTransaction((tx) async {
        final ref = _demandas.doc(demandaId);
        final snap = await tx.get(ref);
        if (!snap.exists) throw const NotFoundException('Demanda');

        final atual = Demanda.fromMap(snap.id, snap.data()!);
        if (!atual.status.podeConcluir || atual.professorId != professorId) {
          throw const ConflictException(
            'Apenas o professor responsável pode concluir esta demanda, '
            'e somente enquanto ela estiver em produção.',
          );
        }
        concluida = atual;

        final agora = DateTime.now();
        tx.update(ref, {
          'status': StatusDemanda.concluida.name,
          'descricaoSolucao': descricaoSolucao,
          'concluidaEm': agora.toIso8601String(),
          'atualizadoEm': agora.toIso8601String(),
        });
      });

      await _registrarAuditoria(
        demandaId: demandaId,
        acao: 'concluir',
        autorId: professorId,
      );

      await _notificacoes.enfileirar(
        destinatarioId: concluida.demandanteId,
        autorId: professorId,
        autorNome: concluida.professorNome ?? 'Professor',
        tipo: TipoNotificacao.demandaConcluida,
        titulo: 'Demanda concluída',
        corpo: '${concluida.professorNome ?? "O professor"} entregou '
            '"${concluida.titulo}". Confira a solução e os anexos.',
        demandaId: demandaId,
        chatId: demandaId,
      );

      // A conversa vira histórico: continua legível, deixa de aceitar envios.
      await _chats.encerrar(
        chatId: demandaId,
        motivo: 'Demanda concluída. A conversa fica disponível apenas para '
            'consulta.',
      );
    } catch (e) {
      if (e is AppException) rethrow;
      throw mapFirestoreError(e, recurso: 'Demanda');
    }
  }

  // ! ===========================
  // ! UC20 - ANEXOS (subcoleção)
  // ! ===========================

  @override
  Stream<List<Anexo>> listarAnexos(String demandaId) {
    return _anexos(demandaId)
        .orderBy('enviadoEm', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => Anexo.fromMap(d.id, d.data())).toList(),
        );
  }

  @override
  Future<List<Anexo>> buscarAnexos(String demandaId) async {
    try {
      final snap =
          await _anexos(demandaId).orderBy('enviadoEm', descending: true).get();
      return snap.docs.map((d) => Anexo.fromMap(d.id, d.data())).toList();
    } catch (e) {
      throw mapFirestoreError(e, recurso: 'Anexos');
    }
  }

  /// Conta anexos via aggregation query (mais barato que listar).
  /// Usado pelo card pra mostrar o contador sem baixar metadados.
  @override
  Future<int> contarAnexos(String demandaId) async {
    try {
      final snap = await _anexos(demandaId).count().get();
      return snap.count ?? 0;
    } catch (_) {
      // Best-effort: se contagem falhar, mostra 0 em vez de quebrar o card.
      return 0;
    }
  }

  Future<String> registrarAnexo({
    required String demandaId,
    required Map<String, dynamic> dadosAnexo,
  }) async {
    try {
      final ref = await _anexos(demandaId).add(dadosAnexo);
      return ref.id;
    } catch (e) {
      throw mapFirestoreError(e, recurso: 'Anexo');
    }
  }

  Future<void> removerAnexoMetadata({
    required String demandaId,
    required String anexoId,
  }) async {
    try {
      await _anexos(demandaId).doc(anexoId).delete();
    } catch (e) {
      throw mapFirestoreError(e, recurso: 'Anexo');
    }
  }

  // ! ===========================
  // ! AUDITORIA (privado)
  // ! ===========================

  /// Cria log de auditoria. Best-effort: falha aqui não deve abortar a operação
  /// principal, então capturamos exceções silenciosamente (mas TODO logar).
  Future<void> _registrarAuditoria({
    required String demandaId,
    required String acao,
    required String autorId,
    Map<String, dynamic>? metadados,
  }) async {
    try {
      await _firestore.collection(_collectionAuditLog).add({
        'demandaId': demandaId,
        'acao': acao,
        'autorUid': autorId,
        'em': DateTime.now().toIso8601String(),
        if (metadados != null) 'metadados': metadados,
      });
    } catch (_) {
      // TODO(observabilidade): integrar com Crashlytics/Sentry
    }
  }
}
