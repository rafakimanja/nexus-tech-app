import '../../exceptions/app_exception.dart';
import '../../models/area.dart';
import '../area_repository.dart';
import 'memory_store.dart';

class MemoryAreaRepository implements AreaRepository {
  final MemoryStore store;
  MemoryAreaRepository(this.store);
  @override
  Future<List<Area>> listar(TipoArea tipo) async {
    await store.preparar();
    return store.areas.values.toList()
      ..sort((a, b) => a.nome.compareTo(b.nome));
  }

  @override
  Future<Area> criarSeNaoExiste(
      {required TipoArea tipo,
      required String nomeBruto,
      required String criadoPorId}) async {
    await store.preparar();
    if (store.sessao?.id != criadoPorId) throw const PermissionException();
    final nome = Area.normalizarNome(nomeBruto);
    if (nome.isEmpty)
      throw const ValidationException('Informe o nome da área.');
    final existentes =
        store.areas.values.where((a) => a.chave == nome.toLowerCase());
    if (existentes.isNotEmpty) return existentes.first;
    final id = store.novoId();
    final area = Area(
        id: id, nome: nome, criadoEm: store.agora(), criadoPor: criadoPorId);
    store.areas[id] = area;
    store.notificar();
    return area;
  }
}
