import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'enums.dart';

/// Status possíveis de uma demanda no fluxo completo do sistema.
///
/// O ciclo de vida completo (demandante + professor) é representado aqui.
/// As transições válidas são declaradas em [_transicoes] — fonte única de
/// verdade da máquina de estados. UI e repositório consultam os getters
/// derivados; nenhum `if (status == X || status == Y)` espalhado.
enum StatusDemanda {
  /// Estado inicial. Visível na prateleira pública (UC08).
  cadastrada,

  /// Professor marcou pra análise (UC09). Tem 24h pra decidir antes do
  /// rollback automático. Sai da prateleira pública e vai para a interface
  /// "Minhas Demandas" do professor.
  emAnalise,

  /// Professor assumiu (UC11). Trabalho em andamento.
  emProducao,

  /// Trabalho entregue (UC12).
  concluida,

  /// Demandante cancelou (UC16). Soft-delete: preserva histórico.
  cancelada;

  String get label => switch (this) {
        StatusDemanda.cadastrada => 'Aguardando',
        StatusDemanda.emAnalise => 'Em análise',
        StatusDemanda.emProducao => 'Em produção',
        StatusDemanda.concluida => 'Concluída',
        StatusDemanda.cancelada => 'Cancelada',
      };

  IconData get icone => switch (this) {
        StatusDemanda.cadastrada => Icons.hourglass_empty,
        StatusDemanda.emAnalise => Icons.search,
        StatusDemanda.emProducao => Icons.settings,
        StatusDemanda.concluida => Icons.check_circle_outline,
        StatusDemanda.cancelada => Icons.cancel_outlined,
      };

  Color get cor => switch (this) {
        StatusDemanda.cadastrada => Colors.amber.shade700,
        StatusDemanda.emAnalise => Colors.orange.shade700,
        StatusDemanda.emProducao => Colors.blue.shade700,
        StatusDemanda.concluida => AppColors.success,
        StatusDemanda.cancelada => AppColors.error,
      };

  // ============== MÁQUINA DE ESTADOS ==============

  /// Transições válidas a partir de cada estado. Estados terminais
  /// (`concluida`, `cancelada`) não têm saída — a republicação de uma
  /// cancelada cria uma demanda NOVA, não é uma transição da original.
  static const Map<StatusDemanda, Set<StatusDemanda>> _transicoes = {
    StatusDemanda.cadastrada: {
      StatusDemanda.emAnalise,
      StatusDemanda.cancelada
    },
    StatusDemanda.emAnalise: {
      StatusDemanda.emProducao,
      StatusDemanda.cadastrada
    },
    StatusDemanda.emProducao: {StatusDemanda.concluida},
    StatusDemanda.concluida: <StatusDemanda>{},
    StatusDemanda.cancelada: <StatusDemanda>{},
  };

  /// Valida no domínio se a transição `this -> novo` é permitida.
  /// É o backstop usado pelas transações do repositório antes de qualquer
  /// escrita; as Firestore Rules são a camada de segurança equivalente.
  bool podeTransicionarPara(StatusDemanda novo) =>
      _transicoes[this]?.contains(novo) ?? false;

  // --- Transições do demandante ---

  /// Demandante só pode editar/cancelar enquanto demanda não foi assumida.
  /// Regra alinhada com UC16 R02 e UC17 R02.
  bool get podeEditarDemandante => this == StatusDemanda.cadastrada;
  bool get podeCancelarDemandante => this == StatusDemanda.cadastrada;

  // --- Transições do professor (Sprint 3) ---

  /// UC09: apenas demandas aguardando podem ser marcadas para análise.
  bool get podeMarcarAnalise => this == StatusDemanda.cadastrada;

  /// UC10: apenas demandas em análise podem ser rejeitadas/devolvidas.
  bool get podeRejeitar => this == StatusDemanda.emAnalise;

  /// UC11: apenas demandas em análise podem ser assumidas.
  bool get podeAssumir => this == StatusDemanda.emAnalise;

  /// UC12: apenas demandas em produção podem ser concluídas.
  bool get podeConcluir => this == StatusDemanda.emProducao;

  /// UC08 R01: a prateleira pública exibe apenas estes status.
  bool get visivelNaPrateleira =>
      this == StatusDemanda.cadastrada || this == StatusDemanda.emProducao;
}

/// Filtro aplicado à lista de demandas.
/// Conforme requisito do produto: filtros são acumulativos (status E período).
enum FiltroPeriodo {
  ultimos7Dias,
  ultimos30Dias,
  todasApos30Dias;

  String get label => switch (this) {
        FiltroPeriodo.ultimos7Dias => 'Últimos 7 dias',
        FiltroPeriodo.ultimos30Dias => 'Últimos 30 dias',
        FiltroPeriodo.todasApos30Dias => 'Todas após 30 dias',
      };

  /// Retorna a data mínima/máxima de criação para esse filtro.
  /// Para `todasApos30Dias`, retorna a data limite SUPERIOR
  /// (demandas criadas há mais de 30 dias).
  ({DateTime? inicio, DateTime? fim}) get range {
    final agora = DateTime.now();
    return switch (this) {
      FiltroPeriodo.ultimos7Dias => (
          inicio: agora.subtract(const Duration(days: 7)),
          fim: null,
        ),
      FiltroPeriodo.ultimos30Dias => (
          inicio: agora.subtract(const Duration(days: 30)),
          fim: null,
        ),
      FiltroPeriodo.todasApos30Dias => (
          inicio: null,
          fim: agora.subtract(const Duration(days: 30)),
        ),
    };
  }
}

class Demanda {
  final String id;

  // --- demandante ---
  final String demandanteId;
  final String demandanteNome;
  final TipoDemandante demandanteTipo;

  // --- conteúdo ---
  final String titulo;
  final String descricao;
  final String publicoAlvo;
  final String impacto;

  // --- estado ---
  final StatusDemanda status;
  final String? motivoCancelamento;

  // --- atribuição (preenchido pelo professor no ciclo de vida — Sprint 3) ---
  final String? professorId;
  final String? professorNome;

  /// Momento em que o professor marcou a demanda para análise (UC09).
  final DateTime? analiseIniciadaEm;

  /// Prazo limite da análise (UC09 R03: 24h). Após esse instante a demanda
  /// deve voltar para `cadastrada` automaticamente. O rollback definitivo
  /// será uma Cloud Function (ver docs/CLOUD_FUNCTIONS.md); enquanto não há
  /// acesso a Functions, o cliente faz reconciliação best-effort.
  final DateTime? analiseExpiraEm;

  /// Momento em que o professor assumiu a demanda (UC11). Usado no cálculo
  /// do tempo médio de entrega (indicadores — UC06).
  final DateTime? producaoIniciadaEm;

  /// Momento da entrega/conclusão (UC12). Também alimenta indicadores.
  final DateTime? concluidaEm;

  /// Descrição da solução entregue pelo professor na conclusão (UC12).
  final String? descricaoSolucao;

  /// Se essa demanda foi cancelada e o demandante usou o botão
  /// "Republicar como nova demanda", este campo guarda o ID da nova.
  /// Serve para duas coisas:
  /// 1. Impedir republicação dupla (UI esconde o botão se != null).
  /// 2. Trilha de auditoria visível: a partir da cancelada dá pra
  ///    chegar à nova (futuro: link clicável).
  /// A Firestore Rule garante que esse campo só pode ser preenchido
  /// UMA vez, evitando reescrita maliciosa.
  final String? republicadaComoId;

  // --- timestamps ---
  final DateTime criadoEm;
  final DateTime? atualizadoEm;
  final DateTime? canceladoEm;

  const Demanda({
    required this.id,
    required this.demandanteId,
    required this.demandanteNome,
    required this.demandanteTipo,
    required this.titulo,
    required this.descricao,
    required this.publicoAlvo,
    required this.impacto,
    required this.status,
    required this.criadoEm,
    this.motivoCancelamento,
    this.professorId,
    this.professorNome,
    this.analiseIniciadaEm,
    this.analiseExpiraEm,
    this.producaoIniciadaEm,
    this.concluidaEm,
    this.descricaoSolucao,
    this.republicadaComoId,
    this.atualizadoEm,
    this.canceladoEm,
  });

  /// `true` quando a janela de análise (UC09 R03) já expirou e a demanda
  /// ainda está `emAnalise` — candidata a rollback automático.
  bool get analiseExpirou =>
      status == StatusDemanda.emAnalise &&
      analiseExpiraEm != null &&
      analiseExpiraEm!.isBefore(DateTime.now());

  Map<String, dynamic> toMap() => {
        'demandanteUid': demandanteId,
        'demandanteNome': demandanteNome,
        'demandanteTipo': demandanteTipo.name,
        'titulo': titulo,
        'tituloLower': titulo.toLowerCase(), // para busca client-side
        'descricao': descricao,
        'publicoAlvo': publicoAlvo,
        'impacto': impacto,
        'status': status.name,
        'motivoCancelamento': motivoCancelamento,
        'professorUid': professorId,
        'professorNome': professorNome,
        'analiseIniciadaEm': analiseIniciadaEm?.toIso8601String(),
        'analiseExpiraEm': analiseExpiraEm?.toIso8601String(),
        'producaoIniciadaEm': producaoIniciadaEm?.toIso8601String(),
        'concluidaEm': concluidaEm?.toIso8601String(),
        'descricaoSolucao': descricaoSolucao,
        'republicadaComoId': republicadaComoId,
        'criadoEm': criadoEm.toIso8601String(),
        'atualizadoEm': atualizadoEm?.toIso8601String(),
        'canceladoEm': canceladoEm?.toIso8601String(),
      };

  factory Demanda.fromMap(String id, Map<String, dynamic> map) => Demanda(
        id: id,
        demandanteId: map['demandanteUid'] as String,
        demandanteNome: map['demandanteNome'] as String,
        demandanteTipo: TipoDemandante.values.firstWhere(
          (t) => t.name == map['demandanteTipo'],
          orElse: () => TipoDemandante.pessoaFisica,
        ),
        titulo: map['titulo'] as String,
        descricao: map['descricao'] as String,
        publicoAlvo: map['publicoAlvo'] as String,
        impacto: map['impacto'] as String,
        status: StatusDemanda.values.firstWhere(
          (s) => s.name == map['status'],
          orElse: () => StatusDemanda.cadastrada,
        ),
        motivoCancelamento: map['motivoCancelamento'] as String?,
        professorId: map['professorUid'] as String?,
        professorNome: map['professorNome'] as String?,
        analiseIniciadaEm: _parseData(map['analiseIniciadaEm']),
        analiseExpiraEm: _parseData(map['analiseExpiraEm']),
        producaoIniciadaEm: _parseData(map['producaoIniciadaEm']),
        concluidaEm: _parseData(map['concluidaEm']),
        descricaoSolucao: map['descricaoSolucao'] as String?,
        // Demandas legadas (criadas antes deste campo existir) retornam null.
        republicadaComoId: map['republicadaComoId'] as String?,
        criadoEm: DateTime.parse(map['criadoEm'] as String),
        atualizadoEm: _parseData(map['atualizadoEm']),
        canceladoEm: _parseData(map['canceladoEm']),
      );

  /// Parse defensivo de datas ISO8601 opcionais. Demandas legadas podem não
  /// ter o campo, e um valor corrompido não deve derrubar a desserialização.
  static DateTime? _parseData(Object? valor) {
    if (valor is! String) return null;
    return DateTime.tryParse(valor);
  }

  Demanda copyWith({
    String? titulo,
    String? descricao,
    String? publicoAlvo,
    String? impacto,
    StatusDemanda? status,
    String? motivoCancelamento,
    String? professorId,
    String? professorNome,
    DateTime? analiseIniciadaEm,
    DateTime? analiseExpiraEm,
    DateTime? producaoIniciadaEm,
    DateTime? concluidaEm,
    String? descricaoSolucao,
    String? republicadaComoId,
    DateTime? atualizadoEm,
    DateTime? canceladoEm,
  }) {
    return Demanda(
      id: id,
      demandanteId: demandanteId,
      demandanteNome: demandanteNome,
      demandanteTipo: demandanteTipo,
      titulo: titulo ?? this.titulo,
      descricao: descricao ?? this.descricao,
      publicoAlvo: publicoAlvo ?? this.publicoAlvo,
      impacto: impacto ?? this.impacto,
      status: status ?? this.status,
      motivoCancelamento: motivoCancelamento ?? this.motivoCancelamento,
      professorId: professorId ?? this.professorId,
      professorNome: professorNome ?? this.professorNome,
      analiseIniciadaEm: analiseIniciadaEm ?? this.analiseIniciadaEm,
      analiseExpiraEm: analiseExpiraEm ?? this.analiseExpiraEm,
      producaoIniciadaEm: producaoIniciadaEm ?? this.producaoIniciadaEm,
      concluidaEm: concluidaEm ?? this.concluidaEm,
      descricaoSolucao: descricaoSolucao ?? this.descricaoSolucao,
      republicadaComoId: republicadaComoId ?? this.republicadaComoId,
      criadoEm: criadoEm,
      atualizadoEm: atualizadoEm ?? this.atualizadoEm,
      canceladoEm: canceladoEm ?? this.canceladoEm,
    );
  }
}
