import '../models/area_selecionada.dart';
import '../models/administrador.dart';
import '../models/demandante.dart';
import '../models/enums.dart';
import '../models/professor.dart';
import '../models/usuario.dart';

/// Contrato de dados independente do backend.
abstract interface class UsuarioRepository {
  Future<Usuario?> buscarPorId(String id);

  Stream<Usuario?> observarPorId(String id);

  Future<Set<String>> buscarAdminIds();

  Future<void> criarProfessor(Professor professor);

  Future<void> criarDemandante(Demandante demandante);

  Future<void> atualizarDemandante({
    required String id,
    required String nome,
    required String telefone,
    required TipoDemandante tipo,
    required String endereco,
  });

  Future<void> atualizarProfessor({
    required String id,
    required String nome,
    required List<AreaSelecionada> areasTecnicas,
    required List<AreaSelecionada> areasInteresse,
  });

  Future<void> atualizarFotoUrl({
    required String id,
    required String fotoUrl,
  });

  Future<Administrador> criarAdministradorAutomatico({
    required String id,
    required String email,
    required String nome,
  });
}
