import '../../api/api_client.dart';
import '../../api/api_dto.dart';
import '../../exceptions/app_exception.dart';
import '../../models/area.dart';
import '../area_repository.dart';

class ApiAreaRepository implements AreaRepository {
  final ApiClient client;
  ApiAreaRepository(this.client);
  @override
  Future<List<Area>> listar(TipoArea tipo) async =>
      apiList(await client.request('GET', '/areas/')).map(apiArea).toList()
        ..sort((a, b) => a.nome.compareTo(b.nome));

  @override
  Future<Area> criarSeNaoExiste(
      {required TipoArea tipo,
      required String nomeBruto,
      required String criadoPorId}) async {
    final nome = Area.normalizarNome(nomeBruto);
    if (nome.isEmpty) {
      throw const ValidationException('Informe o nome da área.');
    }
    final areas = await listar(tipo);
    for (final area in areas) {
      if (Area.normalizarNome(area.nome) == nome) return area;
    }
    // A API ainda não garante unicidade entre criações concorrentes.
    final result =
        await client.request('POST', '/areas/', body: {'name': nome});
    // O POST já confirma a persistência e devolve o ID. Uma segunda leitura
    // pode falhar e apresentar como fracassada uma criação que teve sucesso.
    return apiArea({'id': result['areaID'], 'name': nome});
  }
}
