import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Motivo alegado pelo professor ao denunciar uma demanda.
/// Lista fechada porque alimenta as métricas do painel admin — texto livre
/// tornaria a agregação impossível. A justificativa em texto vai em
/// [Denuncia.descricao].
enum MotivoDenuncia {
  conteudoOfensivo,
  spam,
  foraDoEscopo,
  informacaoFalsa,
  demandaDuplicada,
  outro;

  String get label => switch (this) {
        MotivoDenuncia.conteudoOfensivo => 'Conteúdo ofensivo ou impróprio',
        MotivoDenuncia.spam => 'Spam ou propaganda',
        MotivoDenuncia.foraDoEscopo => 'Fora do escopo do campus',
        MotivoDenuncia.informacaoFalsa => 'Informação falsa ou enganosa',
        MotivoDenuncia.demandaDuplicada => 'Demanda duplicada',
        MotivoDenuncia.outro => 'Outro motivo',
      };

  static MotivoDenuncia from(String? valor) => MotivoDenuncia.values
      .firstWhere((m) => m.name == valor, orElse: () => outro);
}

/// Ciclo de vida da denúncia. `pendente` é o único estado que aparece na fila
/// de trabalho do admin; os outros dois são terminais.
enum StatusDenuncia {
  pendente,
  procedente,
  improcedente;

  String get label => switch (this) {
        StatusDenuncia.pendente => 'Pendente',
        StatusDenuncia.procedente => 'Procedente',
        StatusDenuncia.improcedente => 'Improcedente',
      };

  IconData get icone => switch (this) {
        StatusDenuncia.pendente => Icons.hourglass_empty,
        StatusDenuncia.procedente => Icons.gavel,
        StatusDenuncia.improcedente => Icons.thumb_up_alt_outlined,
      };

  Color get cor => switch (this) {
        StatusDenuncia.pendente => Colors.amber.shade800,
        StatusDenuncia.procedente => AppColors.error,
        StatusDenuncia.improcedente => AppColors.success,
      };

  static StatusDenuncia from(String? valor) => StatusDenuncia.values
      .firstWhere((s) => s.name == valor, orElse: () => pendente);
}

/// Denúncia de uma demanda feita por um professor e julgada por um admin.
///
/// O denunciado é o **demandante** (autor da demanda) — é nele que o strike
/// cai quando a denúncia é julgada procedente. Os nomes vêm desnormalizados
/// para a fila do admin renderizar sem N leituras extras.
class Denuncia {
  final String id;

  // --- alvo ---
  final String demandaId;
  final String tituloDemanda;
  final String demandanteId;
  final String demandanteNome;

  // --- autor da denúncia ---
  final String professorId;
  final String professorNome;

  // --- conteúdo ---
  final MotivoDenuncia motivo;
  final String descricao;

  // --- julgamento ---
  final StatusDenuncia status;
  final DateTime? analisadaEm;
  final String? analisadaPorId;
  final String? analisadaPorNome;
  final String? parecerAdmin;

  /// `true` quando o julgamento procedente resultou em incremento de strike.
  /// Guardado explicitamente para a auditoria: uma denúncia procedente cujo
  /// demandante já estava banido não aplica strike novo.
  final bool strikeAplicado;

  final DateTime criadoEm;

  const Denuncia({
    required this.id,
    required this.demandaId,
    required this.tituloDemanda,
    required this.demandanteId,
    required this.demandanteNome,
    required this.professorId,
    required this.professorNome,
    required this.motivo,
    required this.descricao,
    required this.status,
    required this.criadoEm,
    this.analisadaEm,
    this.analisadaPorId,
    this.analisadaPorNome,
    this.parecerAdmin,
    this.strikeAplicado = false,
  });

  bool get pendente => status == StatusDenuncia.pendente;

  Map<String, dynamic> toMap() => {
        'demandaId': demandaId,
        'tituloDemanda': tituloDemanda,
        'demandanteUid': demandanteId,
        'demandanteNome': demandanteNome,
        'professorUid': professorId,
        'professorNome': professorNome,
        'motivo': motivo.name,
        'descricao': descricao,
        'status': status.name,
        'analisadaEm': analisadaEm?.toIso8601String(),
        'analisadaPorUid': analisadaPorId,
        'analisadaPorNome': analisadaPorNome,
        'parecerAdmin': parecerAdmin,
        'strikeAplicado': strikeAplicado,
        'criadoEm': criadoEm.toIso8601String(),
      };

  factory Denuncia.fromMap(String id, Map<String, dynamic> map) => Denuncia(
        id: id,
        demandaId: map['demandaId'] as String? ?? '',
        tituloDemanda: map['tituloDemanda'] as String? ?? 'Demanda',
        demandanteId: map['demandanteUid'] as String? ?? '',
        demandanteNome: map['demandanteNome'] as String? ?? 'Demandante',
        professorId: map['professorUid'] as String? ?? '',
        professorNome: map['professorNome'] as String? ?? 'Professor',
        motivo: MotivoDenuncia.from(map['motivo'] as String?),
        descricao: map['descricao'] as String? ?? '',
        status: StatusDenuncia.from(map['status'] as String?),
        analisadaEm: DateTime.tryParse(map['analisadaEm'] as String? ?? ''),
        analisadaPorId: map['analisadaPorUid'] as String?,
        analisadaPorNome: map['analisadaPorNome'] as String?,
        parecerAdmin: map['parecerAdmin'] as String?,
        strikeAplicado: map['strikeAplicado'] as bool? ?? false,
        criadoEm: DateTime.tryParse(map['criadoEm'] as String? ?? '') ??
            DateTime.now(),
      );
}
