import '../models/area.dart';

enum TipoArea { tecnica, interesse }

/// Contrato de dados independente do backend.
abstract interface class AreaRepository {
  Future<List<Area>> listar(TipoArea tipo);

  Future<Area> criarSeNaoExiste({
    required TipoArea tipo,
    required String nomeBruto,
    required String criadoPorId,
  });
}
