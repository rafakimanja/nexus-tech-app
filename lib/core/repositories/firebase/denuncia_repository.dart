import '../denuncia_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../constants/app_constants.dart';
import '../../exceptions/app_exception.dart';
import '../../exceptions/firestore_error_handler.dart';
import '../../models/demanda.dart';
import '../../models/denuncia.dart';
import '../../models/notificacao.dart';
import 'notificacao_repository.dart';

/// Denúncias de demandas (professor denuncia) e seu julgamento (admin decide).
///
/// **Onde mora a regra dos 3 strikes:** em [julgar]. Uma denúncia julgada
/// procedente incrementa `strikes` do demandante e, ao atingir
/// [AppConstants.strikesParaBanimento], marca a conta como banida — tudo na
/// **mesma transação** que muda o status da denúncia. Isso impede os dois
/// estados inconsistentes possíveis: denúncia procedente sem strike, e strike
/// aplicado duas vezes se o admin tocar no botão duas vezes.
class FirebaseDenunciaRepository implements DenunciaRepository {
  final FirebaseFirestore _firestore;
  final FirebaseNotificacaoRepository _notificacoes;

  FirebaseDenunciaRepository({
    FirebaseFirestore? firestore,
    FirebaseNotificacaoRepository? notificacaoRepository,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _notificacoes = notificacaoRepository ??
            FirebaseNotificacaoRepository(firestore: firestore);

  CollectionReference<Map<String, dynamic>> get _denuncias =>
      _firestore.collection(AppConstants.collectionDenuncias);

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection(AppConstants.collectionUsers);

  /// ID determinístico: um professor só tem uma denúncia por demanda.
  ///
  /// Escolha deliberada em vez de ID gerado: torna a criação idempotente
  /// (duplo clique reescreve o mesmo documento) e transforma "já denunciei
  /// isso?" numa leitura pontual barata, sem query nem índice.
  String _idDeterministico(String demandaId, String professorId) =>
      '${demandaId}__$professorId';

  // ! ===========================
  // ! PROFESSOR — DENUNCIAR
  // ! ===========================

  /// Registra a denúncia e avisa os administradores.
  ///
  /// Recusa se o mesmo professor já denunciou a mesma demanda: sem isso, um
  /// professor sozinho poderia empilhar denúncias e derrubar um demandante.
  @override
  Future<String> denunciar({
    required Demanda demanda,
    required String professorId,
    required String professorNome,
    required MotivoDenuncia motivo,
    required String descricao,
    required Set<String> adminIds,
  }) async {
    final texto = descricao.trim();
    if (texto.length < 10) {
      throw const ValidationException(
        'Descreva o problema com pelo menos 10 caracteres.',
      );
    }

    try {
      final id = _idDeterministico(demanda.id, professorId);
      final ref = _denuncias.doc(id);

      final existente = await ref.get();
      if (existente.exists) {
        throw const ConflictException(
          'Você já denunciou esta demanda. A administração está avaliando.',
        );
      }

      final denuncia = Denuncia(
        id: id,
        demandaId: demanda.id,
        tituloDemanda: demanda.titulo,
        demandanteId: demanda.demandanteId,
        demandanteNome: demanda.demandanteNome,
        professorId: professorId,
        professorNome: professorNome,
        motivo: motivo,
        descricao: texto,
        status: StatusDenuncia.pendente,
        criadoEm: DateTime.now(),
      );

      await ref.set(denuncia.toMap());

      // Aviso aos admins (best-effort, um documento por admin: a central de
      // notificações é por destinatário).
      for (final adminId in adminIds) {
        await _notificacoes.enfileirar(
          destinatarioId: adminId,
          autorId: professorId,
          autorNome: professorNome,
          tipo: TipoNotificacao.denunciaRecebida,
          titulo: 'Nova denúncia recebida',
          corpo: '$professorNome denunciou "${demanda.titulo}" — '
              '${motivo.label}.',
          demandaId: demanda.id,
          denunciaId: id,
        );
      }

      return id;
    } catch (e) {
      if (e is AppException) rethrow;
      throw mapFirestoreError(e, recurso: 'Denúncia');
    }
  }

  /// `true` se [professorId] já denunciou [demandaId]. Leitura pontual —
  /// usada para trocar o rótulo do botão na tela de detalhes.
  @override
  Future<bool> jaDenunciou({
    required String demandaId,
    required String professorId,
  }) async {
    try {
      final doc =
          await _denuncias.doc(_idDeterministico(demandaId, professorId)).get();
      return doc.exists;
    } catch (_) {
      // Best-effort: na dúvida mostra o botão; a criação recusa a duplicata.
      return false;
    }
  }

  // ! ===========================
  // ! ADMIN — FILA E JULGAMENTO
  // ! ===========================

  /// Fila do admin em tempo real. [apenasPendentes] é o modo de trabalho;
  /// o histórico completo serve de auditoria.
  /// Exige índice composto (status ASC, criadoEm DESC).
  @override
  Stream<List<Denuncia>> observarTodas({bool apenasPendentes = false}) {
    Query<Map<String, dynamic>> query = _denuncias;
    if (apenasPendentes) {
      query = query.where('status', isEqualTo: StatusDenuncia.pendente.name);
    }
    return query.orderBy('criadoEm', descending: true).snapshots().map((snap) =>
        snap.docs.map((d) => Denuncia.fromMap(d.id, d.data())).toList());
  }

  /// Denúncias feitas por um professor (histórico dele).
  /// Exige índice composto (professorId ASC, criadoEm DESC).
  @override
  Stream<List<Denuncia>> observarDoProfessor(String professorId) {
    return _denuncias
        .where('professorUid', isEqualTo: professorId)
        .orderBy('criadoEm', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Denuncia.fromMap(d.id, d.data())).toList());
  }

  /// Denúncias contra um demandante — mostra o histórico ao decidir o strike.
  /// Exige índice composto (demandanteId ASC, criadoEm DESC).
  @override
  Stream<List<Denuncia>> observarDoDemandante(String demandanteId) {
    return _denuncias
        .where('demandanteUid', isEqualTo: demandanteId)
        .orderBy('criadoEm', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Denuncia.fromMap(d.id, d.data())).toList());
  }

  /// Julga a denúncia.
  ///
  /// Quando [procedente], aplica um strike ao demandante na mesma transação e
  /// bane a conta ao atingir [AppConstants.strikesParaBanimento].
  ///
  /// Retorna o resultado para a UI conseguir dizer exatamente o que aconteceu
  /// ("2º strike aplicado" vs. "conta banida"), sem reler o usuário.
  @override
  Future<ResultadoJulgamento> julgar({
    required Denuncia denuncia,
    required bool procedente,
    required String adminId,
    required String adminNome,
    required String parecer,
  }) async {
    final texto = parecer.trim();
    if (texto.isEmpty) {
      throw const ValidationException(
        'Escreva um parecer justificando a decisão.',
      );
    }

    try {
      late ResultadoJulgamento resultado;

      await _firestore.runTransaction((tx) async {
        final denunciaRef = _denuncias.doc(denuncia.id);
        final denunciaSnap = await tx.get(denunciaRef);
        if (!denunciaSnap.exists) throw const NotFoundException('Denúncia');

        final atual = Denuncia.fromMap(denunciaSnap.id, denunciaSnap.data()!);
        if (!atual.pendente) {
          throw const ConflictException(
            'Esta denúncia já foi analisada por outro administrador.',
          );
        }

        // Lê o denunciado ANTES de qualquer escrita (regra das transações do
        // Firestore: todas as leituras precedem todas as escritas).
        final usuarioRef = _users.doc(atual.demandanteId);
        final usuarioSnap = procedente ? await tx.get(usuarioRef) : null;

        var strikes = 0;
        var banido = false;
        var strikeAplicado = false;

        if (procedente && usuarioSnap != null && usuarioSnap.exists) {
          final dados = usuarioSnap.data()!;
          final strikesAtuais = (dados['strikes'] as num?)?.toInt() ?? 0;
          final jaBanido = dados['banido'] as bool? ?? false;

          if (jaBanido) {
            // Conta já banida: registra o julgamento, mas não empilha strike.
            strikes = strikesAtuais;
            banido = true;
          } else {
            strikes = strikesAtuais + 1;
            banido = strikes >= AppConstants.strikesParaBanimento;
            strikeAplicado = true;

            tx.update(usuarioRef, {
              'strikes': strikes,
              'banido': banido,
              if (banido) 'banidoEm': DateTime.now().toIso8601String(),
              if (banido)
                'motivoBanimento':
                    'Acúmulo de ${AppConstants.strikesParaBanimento} '
                        'advertências por denúncias procedentes.',
            });
          }
        }

        tx.update(denunciaRef, {
          'status': procedente
              ? StatusDenuncia.procedente.name
              : StatusDenuncia.improcedente.name,
          'analisadaEm': DateTime.now().toIso8601String(),
          'analisadaPorUid': adminId,
          'analisadaPorNome': adminNome,
          'parecerAdmin': texto,
          'strikeAplicado': strikeAplicado,
        });

        resultado = ResultadoJulgamento(
          procedente: procedente,
          strikeAplicado: strikeAplicado,
          strikesTotais: strikes,
          contaBanida: banido,
        );
      });

      await _registrarAuditoria(
        denuncia: denuncia,
        adminId: adminId,
        resultado: resultado,
      );
      await _notificarJulgamento(
        denuncia: denuncia,
        adminId: adminId,
        adminNome: adminNome,
        parecer: texto,
        resultado: resultado,
      );

      return resultado;
    } catch (e) {
      if (e is AppException) rethrow;
      throw mapFirestoreError(e, recurso: 'Denúncia');
    }
  }

  // ! ===========================
  // ! EFEITOS COLATERAIS (best-effort)
  // ! ===========================

  Future<void> _notificarJulgamento({
    required Denuncia denuncia,
    required String adminId,
    required String adminNome,
    required String parecer,
    required ResultadoJulgamento resultado,
  }) async {
    // Retorno ao professor que denunciou.
    await _notificacoes.enfileirar(
      destinatarioId: denuncia.professorId,
      autorId: adminId,
      autorNome: adminNome,
      tipo: TipoNotificacao.denunciaAnalisada,
      titulo: resultado.procedente
          ? 'Sua denúncia foi julgada procedente'
          : 'Sua denúncia foi julgada improcedente',
      corpo: 'Demanda "${denuncia.tituloDemanda}": $parecer',
      demandaId: denuncia.demandaId,
      denunciaId: denuncia.id,
    );

    if (!resultado.strikeAplicado) return;

    // Aviso ao demandante advertido/banido.
    if (resultado.contaBanida == true) {
      await _notificacoes.enfileirar(
        destinatarioId: denuncia.demandanteId,
        autorId: adminId,
        autorNome: adminNome,
        tipo: TipoNotificacao.contaBanida,
        titulo: 'Conta suspensa',
        corpo: 'Sua conta acumulou '
            '${AppConstants.strikesParaBanimento} advertências e foi '
            'suspensa. Entre em contato com a administração do campus.',
        demandaId: denuncia.demandaId,
        denunciaId: denuncia.id,
      );
    } else {
      final restantes =
          AppConstants.strikesParaBanimento - resultado.strikesTotais!;
      await _notificacoes.enfileirar(
        destinatarioId: denuncia.demandanteId,
        autorId: adminId,
        autorNome: adminNome,
        tipo: TipoNotificacao.strikeAplicado,
        titulo: 'Advertência ${resultado.strikesTotais} de '
            '${AppConstants.strikesParaBanimento}',
        corpo: 'A demanda "${denuncia.tituloDemanda}" recebeu uma denúncia '
            'procedente. Mais $restantes '
            '${restantes == 1 ? "advertência suspende" : "advertências suspendem"}'
            ' sua conta.',
        demandaId: denuncia.demandaId,
        denunciaId: denuncia.id,
      );
    }
  }

  Future<void> _registrarAuditoria({
    required Denuncia denuncia,
    required String adminId,
    required ResultadoJulgamento resultado,
  }) async {
    try {
      await _firestore.collection(AppConstants.collectionAuditLogs).add({
        'demandaId': denuncia.demandaId,
        'acao': resultado.procedente
            ? 'denuncia_procedente'
            : 'denuncia_improcedente',
        'autorUid': adminId,
        'em': DateTime.now().toIso8601String(),
        'metadados': {
          'denunciaId': denuncia.id,
          'demandanteUid': denuncia.demandanteId,
          'strikeAplicado': resultado.strikeAplicado,
          'strikesTotais': resultado.strikesTotais,
          'contaBanida': resultado.contaBanida,
        },
      });
    } catch (_) {
      // best-effort (§2.5 da arquitetura).
    }
  }
}
