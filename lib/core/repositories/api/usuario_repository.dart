import '../../api/api_client.dart';
import '../../api/api_dto.dart';
import '../../exceptions/app_exception.dart';
import '../../models/administrador.dart';
import '../../models/area_selecionada.dart';
import '../../models/demandante.dart';
import '../../models/enums.dart';
import '../../models/professor.dart';
import '../../models/usuario.dart';
import '../usuario_repository.dart';

class ApiUsuarioRepository implements UsuarioRepository {
  final ApiClient client;
  ApiUsuarioRepository(this.client);

  @override
  Future<Usuario?> buscarPorId(String id) async {
    final me =
        (await client.request('GET', '/me'))['user'] as Map<String, dynamic>;
    if (apiId(me['id']) != id) throw const PermissionException();
    final role = apiRole(me['role']);
    // Só /me permanece acessível para uma conta bloqueada.
    if (me['blocked'] == true) {
      throw ContaBloqueadaException.fromReason(me['block_reason'] as String?);
    }
    if (me['profile_complete'] != true) return null;
    if (role == UserRole.administrador) {
      return Administrador(
          id: id,
          email: me['email'],
          nome: me['name'],
          fotoUrl: me['photo_url'],
          criadoEm: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    }
    final path = role == UserRole.professor ? '/teachers/' : '/applicants/';
    final data = await client.request('GET', '$path${numericId(id)}')
        as Map<String, dynamic>;
    return role == UserRole.professor ? apiTeacher(data) : apiApplicant(data);
  }

  @override
  Stream<Usuario?> observarPorId(String id) =>
      client.watch(() => buscarPorId(id));
  @override
  Future<Set<String>> buscarAdminIds() async =>
      apiList(await client.request('GET', '/users/'))
          .where((m) => m['role'] == 'admin')
          .map((m) => apiId(m['ID']))
          .toSet();

  Map<String, dynamic> _applicant(Demandante p) => {
        'name': p.nome,
        'photo_url': p.fotoUrl,
        'phone': p.telefone,
        'type': p.tipo.name,
        'cpf_cnpj': p.cpfCnpj,
        'address': p.endereco,
      };
  List<Map<String, dynamic>> _areas(
      List<AreaSelecionada> technical, List<AreaSelecionada> interest) {
    final seen = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final entry in [(technical, 'técnica'), (interest, 'interesse')]) {
      for (final area in entry.$1) {
        final id = area.id;
        if (id == null) {
          throw const ValidationException(
              'Selecione novamente a área pelo catálogo.');
        }
        if (!seen.add(id)) {
          throw const ValidationException(
              'Uma área não pode ser técnica e de interesse ao mesmo tempo.');
        }
        result.add({'areas_id': numericId(id), 'type': entry.$2});
      }
    }
    return result;
  }

  Map<String, dynamic> _teacher(Professor p) => {
        'name': p.nome,
        'photo_url': p.fotoUrl,
        'siape': p.siape,
        'areas': _areas(p.areasTecnicas, p.areasInteresse),
      };

  @override
  Future<void> criarProfessor(Professor professor) async {
    await _completarPerfil('/teachers/', professor.id, _teacher(professor));
  }

  @override
  Future<void> criarDemandante(Demandante demandante) async {
    await _completarPerfil(
        '/applicants/', demandante.id, _applicant(demandante));
  }

  Future<void> _completarPerfil(
      String path, String id, Map<String, dynamic> body) async {
    final me =
        (await client.request('GET', '/me'))['user'] as Map<String, dynamic>;
    if (apiId(me['id']) != id) throw const PermissionException();
    final fields = {...body, 'photo_url': body['photo_url'] ?? me['photo_url']};
    var existe = true;
    try {
      await client.request('GET', '$path${numericId(id)}');
    } on NotFoundException {
      existe = false;
    }
    // /me também pode indicar um perfil existente, mas ainda incompleto.
    await client.request(
        existe ? 'PUT' : 'POST', existe ? '$path${numericId(id)}' : path,
        body: fields);
  }

  @override
  Future<void> atualizarDemandante(
      {required String id,
      required String nome,
      required String telefone,
      required TipoDemandante tipo,
      required String endereco}) async {
    final current = apiApplicant(
        await client.request('GET', '/applicants/${numericId(id)}'));
    await client.request('PUT', '/applicants/${numericId(id)}', body: {
      ..._applicant(current),
      'name': nome,
      'phone': telefone,
      'type': tipo.name,
      'address': endereco
    });
  }

  @override
  Future<void> atualizarProfessor(
      {required String id,
      required String nome,
      required List<AreaSelecionada> areasTecnicas,
      required List<AreaSelecionada> areasInteresse}) async {
    final current =
        apiTeacher(await client.request('GET', '/teachers/${numericId(id)}'));
    await client.request('PUT', '/teachers/${numericId(id)}', body: {
      ..._teacher(current),
      'name': nome,
      'areas': _areas(areasTecnicas, areasInteresse)
    });
  }

  @override
  Future<void> atualizarFotoUrl(
      {required String id, required String fotoUrl}) async {
    final current = await buscarPorId(id);
    if (current is Demandante) {
      await client.request('PUT', '/applicants/${numericId(id)}',
          body: {..._applicant(current), 'photo_url': fotoUrl});
    } else if (current is Professor) {
      await client.request('PUT', '/teachers/${numericId(id)}',
          body: {..._teacher(current), 'photo_url': fotoUrl});
    } else {
      throw const RecursoIndisponivelException('Alteração de foto');
    }
  }

  @override
  Future<Administrador> criarAdministradorAutomatico(
      {required String id, required String email, required String nome}) async {
    throw const RecursoIndisponivelException(
        'Criação automática de administrador pelo aplicativo');
  }
}
