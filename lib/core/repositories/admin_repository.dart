import '../models/demanda.dart';
import '../models/demandante.dart';
import '../models/metricas_professor.dart';
import '../models/professor.dart';

/// Contrato de dados independente do backend.
abstract interface class AdminRepository {
  Stream<List<Professor>> observarProfessores();

  Stream<List<Demandante>> observarDemandantes();

  Stream<List<Demanda>> observarTodasDemandas();

  Stream<MetricasProfessor> observarMetricas(String professorId);

  Stream<List<Demanda>> observarDemandasDoProfessor(String professorId);

  Future<void> definirProfessorAtivo({
    required Professor professor,
    required bool ativo,
    required String adminId,
    required String adminNome,
    String? motivo,
  });

  Future<void> ajustarStrikes({
    required Demandante demandante,
    required int novoTotal,
    required String adminId,
    required String adminNome,
    required String motivo,
  });

  Future<void> reverterBanimento({
    required Demandante demandante,
    required String adminId,
    required String adminNome,
    required String motivo,
  });
}
