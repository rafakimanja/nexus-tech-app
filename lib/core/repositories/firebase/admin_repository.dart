import '../admin_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../constants/app_constants.dart';
import '../../exceptions/app_exception.dart';
import '../../exceptions/firestore_error_handler.dart';
import '../../models/demanda.dart';
import '../../models/demandante.dart';
import '../../models/metricas_professor.dart';
import '../../models/notificacao.dart';
import '../../models/professor.dart';
import 'notificacao_repository.dart';

/// Operações exclusivas do painel administrativo.
///
/// Todas as escritas daqui dependem de `isAdminEmail()` nas Firestore Rules —
/// o repositório não é a barreira de segurança, só a interface conveniente.
///
/// **Nota de custo (plano Spark):** as métricas por professor são calculadas
/// lendo as demandas dele. É uma query por professor aberto no painel, não uma
/// varredura global — o painel carrega a lista de professores e só busca
/// métricas do que o admin abre. Ver `docs/CLOUD_FUNCTIONS.md` para o caminho
/// de evolução (contadores mantidos por Cloud Function).
class FirebaseAdminRepository implements AdminRepository {
  final FirebaseFirestore _firestore;
  final FirebaseNotificacaoRepository _notificacoes;

  FirebaseAdminRepository({
    FirebaseFirestore? firestore,
    FirebaseNotificacaoRepository? notificacaoRepository,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _notificacoes = notificacaoRepository ??
            FirebaseNotificacaoRepository(firestore: firestore);

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection(AppConstants.collectionUsers);

  CollectionReference<Map<String, dynamic>> get _demandas =>
      _firestore.collection(AppConstants.collectionDemandas);

  // ! ===========================
  // ! LISTAGENS
  // ! ===========================

  /// Professores cadastrados, em tempo real (ativar/desativar reflete na hora).
  ///
  /// Ordenação por nome é feita no cliente de propósito: um `orderBy('nome')`
  /// junto do filtro de role exigiria mais um índice composto para ganhar nada
  /// numa lista do tamanho do corpo docente de um campus.
  @override
  Stream<List<Professor>> observarProfessores() {
    return _users.where('role', isEqualTo: 'professor').snapshots().map((snap) {
      final lista = snap.docs.map((d) => Professor.fromMap(d.data())).toList()
        ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
      return lista;
    });
  }

  /// Demandantes cadastrados, em tempo real (strikes e banimentos ao vivo).
  @override
  Stream<List<Demandante>> observarDemandantes() {
    return _users
        .where('role', isEqualTo: 'demandante')
        .snapshots()
        .map((snap) {
      final lista = snap.docs.map((d) => Demandante.fromMap(d.data())).toList()
        ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
      return lista;
    });
  }

  /// Todas as demandas do sistema, mais recentes primeiro.
  /// Usada na visão geral e na apuração de denúncias.
  @override
  Stream<List<Demanda>> observarTodasDemandas() {
    return _demandas.orderBy('criadoEm', descending: true).snapshots().map(
        (snap) =>
            snap.docs.map((d) => Demanda.fromMap(d.id, d.data())).toList());
  }

  // ! ===========================
  // ! MÉTRICAS DO PROFESSOR
  // ! ===========================

  /// Métricas de um professor, em tempo real.
  ///
  /// [devolvidas] não sai das demandas (a devolução apaga o `professorId`),
  /// então vem da auditoria numa leitura pontual feita antes de abrir o stream.
  /// É um número histórico: não muda enquanto a tela está aberta, e por isso
  /// não justifica um segundo stream.
  @override
  Stream<MetricasProfessor> observarMetricas(String professorId) async* {
    final devolvidas = await _contarDevolvidas(professorId);

    yield* _demandas
        .where('professorUid', isEqualTo: professorId)
        .snapshots()
        .map((snap) {
      final demandas =
          snap.docs.map((d) => Demanda.fromMap(d.id, d.data())).toList();
      return MetricasProfessor.calcular(
        professorId: professorId,
        demandas: demandas,
        devolvidas: devolvidas,
      );
    });
  }

  /// Demandas atribuídas ao professor (lista de apoio da tela de métricas).
  @override
  Stream<List<Demanda>> observarDemandasDoProfessor(String professorId) {
    return _demandas
        .where('professorUid', isEqualTo: professorId)
        .snapshots()
        .map((snap) {
      final lista = snap.docs
          .map((d) => Demanda.fromMap(d.id, d.data()))
          .toList()
        ..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
      return lista;
    });
  }

  /// Conta devoluções (rejeição manual + rollback por expiração) na auditoria.
  /// Best-effort: um erro aqui vira "0 devolvidas", não uma tela quebrada.
  Future<int> _contarDevolvidas(String professorId) async {
    try {
      final snap = await _firestore
          .collection(AppConstants.collectionAuditLogs)
          .where('autorUid', isEqualTo: professorId)
          .where('acao', whereIn: ['rejeitar', 'rollback_analise'])
          .count()
          .get();
      return snap.count ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ! ===========================
  // ! ATIVAR / DESATIVAR PROFESSOR
  // ! ===========================

  /// Liga ou desliga o perfil de um professor (UC04 R01).
  ///
  /// Desativar não mexe nas demandas já assumidas: elas continuam existindo e
  /// aparecendo para o demandante. A recusa a novas ações vem do próprio
  /// `Professor.ativo`, checado na UI, nas transições e nas Rules. Por isso o
  /// painel avisa quando há trabalho em aberto — a decisão de desligar mesmo
  /// assim é do admin, mas ele precisa vê-la.
  @override
  Future<void> definirProfessorAtivo({
    required Professor professor,
    required bool ativo,
    required String adminId,
    required String adminNome,
    String? motivo,
  }) async {
    if (professor.ativo == ativo) return;
    if (!ativo && (motivo == null || motivo.trim().length < 5)) {
      throw const ValidationException(
        'Informe o motivo da desativação (mínimo 5 caracteres).',
      );
    }

    try {
      await _users.doc(professor.id).update({
        'ativo': ativo,
        'desativadoEm': ativo ? null : DateTime.now().toIso8601String(),
        'motivoDesativacao': ativo ? null : motivo!.trim(),
      });

      await _registrarAuditoria(
        acao: ativo ? 'professor_reativado' : 'professor_desativado',
        adminId: adminId,
        metadados: {
          'professorUid': professor.id,
          'professorNome': professor.nome,
          if (!ativo) 'motivo': motivo!.trim(),
        },
      );

      await _notificacoes.enfileirar(
        destinatarioId: professor.id,
        autorId: adminId,
        autorNome: adminNome,
        tipo: ativo
            ? TipoNotificacao.perfilReativado
            : TipoNotificacao.perfilDesativado,
        titulo: ativo ? 'Perfil reativado' : 'Perfil desativado',
        corpo: ativo
            ? 'Seu perfil de professor foi reativado. Você já pode voltar a '
                'atuar nas demandas.'
            : 'Seu perfil de professor foi desativado pela administração. '
                'Motivo: ${motivo!.trim()}',
      );
    } catch (e) {
      if (e is AppException) rethrow;
      throw mapFirestoreError(e, recurso: 'Professor');
    }
  }

  // ! ===========================
  // ! STRIKES E BANIMENTO (DEMANDANTE)
  // ! ===========================

  /// Ajuste manual de strikes fora do fluxo de denúncia.
  ///
  /// Existe porque nem toda advertência nasce de uma denúncia formal (contato
  /// direto com a administração, por exemplo), e porque o admin precisa poder
  /// corrigir um erro de julgamento. Bane automaticamente ao atingir o limite,
  /// pela mesma regra do julgamento — a decisão de banir é sempre derivada da
  /// contagem, nunca de um botão separado.
  @override
  Future<void> ajustarStrikes({
    required Demandante demandante,
    required int novoTotal,
    required String adminId,
    required String adminNome,
    required String motivo,
  }) async {
    if (novoTotal < 0) {
      throw const ValidationException('Strikes não podem ser negativos.');
    }
    if (motivo.trim().length < 5) {
      throw const ValidationException(
        'Informe o motivo do ajuste (mínimo 5 caracteres).',
      );
    }

    final banido = novoTotal >= AppConstants.strikesParaBanimento;

    try {
      await _users.doc(demandante.id).update({
        'strikes': novoTotal,
        'banido': banido,
        'banidoEm': banido
            ? (demandante.banidoEm ?? DateTime.now()).toIso8601String()
            : null,
        'motivoBanimento': banido ? motivo.trim() : null,
      });

      await _registrarAuditoria(
        acao: banido ? 'demandante_banido' : 'strikes_ajustados',
        adminId: adminId,
        metadados: {
          'demandanteUid': demandante.id,
          'de': demandante.strikes,
          'para': novoTotal,
          'motivo': motivo.trim(),
        },
      );

      final voltouAAtiva = demandante.banido && !banido;
      await _notificacoes.enfileirar(
        destinatarioId: demandante.id,
        autorId: adminId,
        autorNome: adminNome,
        tipo: banido
            ? TipoNotificacao.contaBanida
            : TipoNotificacao.strikeAplicado,
        titulo: banido
            ? 'Conta suspensa'
            : voltouAAtiva
                ? 'Conta reativada'
                : 'Advertências atualizadas',
        corpo: banido
            ? 'Sua conta foi suspensa pela administração. Motivo: '
                '${motivo.trim()}'
            : voltouAAtiva
                ? 'Sua conta foi reativada pela administração. '
                    'Advertências: $novoTotal de '
                    '${AppConstants.strikesParaBanimento}.'
                : 'Suas advertências passaram a $novoTotal de '
                    '${AppConstants.strikesParaBanimento}. '
                    'Motivo: ${motivo.trim()}',
      );
    } catch (e) {
      if (e is AppException) rethrow;
      throw mapFirestoreError(e, recurso: 'Demandante');
    }
  }

  /// Reverte um banimento zerando os strikes — atalho de [ajustarStrikes] para
  /// o caso mais comum do painel.
  @override
  Future<void> reverterBanimento({
    required Demandante demandante,
    required String adminId,
    required String adminNome,
    required String motivo,
  }) {
    return ajustarStrikes(
      demandante: demandante,
      novoTotal: 0,
      adminId: adminId,
      adminNome: adminNome,
      motivo: motivo,
    );
  }

  // ! ===========================
  // ! AUDITORIA
  // ! ===========================

  Future<void> _registrarAuditoria({
    required String acao,
    required String adminId,
    Map<String, dynamic>? metadados,
  }) async {
    try {
      await _firestore.collection(AppConstants.collectionAuditLogs).add({
        'acao': acao,
        'autorUid': adminId,
        'em': DateTime.now().toIso8601String(),
        if (metadados != null) 'metadados': metadados,
      });
    } catch (_) {
      // best-effort (§2.5 da arquitetura).
    }
  }
}
