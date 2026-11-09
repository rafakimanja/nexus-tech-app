import '../models/demanda.dart';
import '../models/denuncia.dart';

/// O que o julgamento produziu — permite à UI dar um retorno preciso.
class ResultadoJulgamento {
  final bool procedente;
  final bool strikeAplicado;
  final int strikesTotais;
  final bool contaBanida;

  const ResultadoJulgamento({
    required this.procedente,
    required this.strikeAplicado,
    required this.strikesTotais,
    required this.contaBanida,
  });
}

/// Contrato de dados independente do backend.
abstract interface class DenunciaRepository {
  Future<String> denunciar({
    required Demanda demanda,
    required String professorId,
    required String professorNome,
    required MotivoDenuncia motivo,
    required String descricao,
    required Set<String> adminIds,
  });

  Future<bool> jaDenunciou({
    required String demandaId,
    required String professorId,
  });

  Stream<List<Denuncia>> observarTodas({bool apenasPendentes = false});

  Stream<List<Denuncia>> observarDoProfessor(String professorId);

  Stream<List<Denuncia>> observarDoDemandante(String demandanteId);

  Future<ResultadoJulgamento> julgar({
    required Denuncia denuncia,
    required bool procedente,
    required String adminId,
    required String adminNome,
    required String parecer,
  });
}
