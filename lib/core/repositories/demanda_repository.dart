import '../models/criar_demanda.dart';
import '../models/anexo.dart';
import '../models/demanda.dart';

/// Contrato de dados independente do backend.
abstract interface class DemandaRepository {
  Future<String> criar(
    CriarDemanda dados, {
    String? originalCanceladaId,
  });

  Future<void> atualizar({
    required String id,
    required String autorId,
    required String titulo,
    required String descricao,
    required String publicoAlvo,
    required String impacto,
  });

  Future<void> cancelar({
    required String id,
    required String autorId,
    required String motivo,
  });

  Stream<List<Demanda>> listarDoDemandante({
    required String demandanteId,
    StatusDemanda? filtroStatus,
    FiltroPeriodo? filtroPeriodo,
  });

  Stream<Demanda?> observar(String id);

  Stream<List<Demanda>> listarPrateleira();

  Stream<List<Demanda>> listarDoProfessor({
    required String professorId,
    StatusDemanda? filtroStatus,
    FiltroPeriodo? filtroPeriodo,
  });

  Future<void> marcarParaAnalise({
    required String demandaId,
    required String professorId,
    required String professorNome,
  });

  Future<void> rejeitarAnalise({
    required String demandaId,
    required String professorId,
    bool automatico = false,
  });

  Future<void> assumir({
    required String demandaId,
    required String professorId,
  });

  Future<void> concluir({
    required String demandaId,
    required String professorId,
    required String descricaoSolucao,
  });

  Stream<List<Anexo>> listarAnexos(String demandaId);

  Future<List<Anexo>> buscarAnexos(String demandaId);

  Future<int> contarAnexos(String demandaId);
}
