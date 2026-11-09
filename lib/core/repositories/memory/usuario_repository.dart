import '../../exceptions/app_exception.dart';
import '../../models/administrador.dart';
import '../../models/area_selecionada.dart';
import '../../models/demandante.dart';
import '../../models/enums.dart';
import '../../models/professor.dart';
import '../../models/usuario.dart';
import '../usuario_repository.dart';
import 'memory_store.dart';

class MemoryUsuarioRepository implements UsuarioRepository {
  final MemoryStore store;
  MemoryUsuarioRepository(this.store);
  @override
  Future<Usuario?> buscarPorId(String id) async {
    await store.preparar();
    return store.usuarios[id];
  }

  @override
  Stream<Usuario?> observarPorId(String id) =>
      store.observar(() => store.usuarios[id]);
  @override
  Future<Set<String>> buscarAdminIds() async =>
      store.usuarios.values.whereType<Administrador>().map((u) => u.id).toSet();

  void _cadastro(Usuario usuario) {
    if (store.sessao?.id != usuario.id || store.sessao?.role != usuario.role)
      throw const PermissionException();
    if (store.usuarios.containsKey(usuario.id))
      throw const ConflictException('Perfil já cadastrado.');
    store.usuarios[usuario.id] = usuario;
    store.notificar();
  }

  void _validarAreas(
      List<AreaSelecionada> tecnicas, List<AreaSelecionada> interesses) {
    if (tecnicas.isEmpty || interesses.isEmpty)
      throw const ValidationException(
          'Selecione áreas técnicas e de interesse.');
    final ids = [...tecnicas, ...interesses].map((a) => a.id).toList();
    if (ids.any((id) => !store.areas.containsKey(id)) ||
        ids.toSet().length != ids.length) {
      throw const ValidationException(
          'Selecione áreas existentes, sem repetir a mesma área entre os tipos.');
    }
  }

  @override
  Future<void> criarProfessor(Professor professor) async {
    await store.preparar();
    _validarAreas(professor.areasTecnicas, professor.areasInteresse);
    _cadastro(professor);
  }

  @override
  Future<void> criarDemandante(Demandante demandante) async {
    await store.preparar();
    _cadastro(demandante);
  }

  @override
  Future<void> atualizarDemandante(
      {required String id,
      required String nome,
      required String telefone,
      required TipoDemandante tipo,
      required String endereco}) async {
    await store.preparar();
    store.exigirUsuario(id: id, role: UserRole.demandante);
    store.atualizarUsuario(id, {
      'nome': nome.trim(),
      'telefone': telefone.replaceAll(RegExp(r'\D'), ''),
      'tipo': tipo.name,
      'endereco': endereco.trim()
    });
    store.notificar();
  }

  @override
  Future<void> atualizarProfessor(
      {required String id,
      required String nome,
      required List<AreaSelecionada> areasTecnicas,
      required List<AreaSelecionada> areasInteresse}) async {
    await store.preparar();
    store.exigirUsuario(id: id, role: UserRole.professor);
    _validarAreas(areasTecnicas, areasInteresse);
    final p = store.usuarios[id]! as Professor;
    store.usuarios[id] = Professor(
        id: id,
        email: p.email,
        nome: nome.trim(),
        criadoEm: p.criadoEm,
        siape: p.siape,
        areasTecnicas: List.unmodifiable(areasTecnicas),
        areasInteresse: List.unmodifiable(areasInteresse),
        ativo: p.ativo,
        fotoUrl: p.fotoUrl,
        desativadoEm: p.desativadoEm,
        motivoDesativacao: p.motivoDesativacao);
    store.notificar();
  }

  @override
  Future<void> atualizarFotoUrl(
      {required String id, required String fotoUrl}) async {
    await store.preparar();
    store.exigirUsuario(id: id);
    store.atualizarUsuario(id, {'fotoUrl': fotoUrl});
    store.notificar();
  }

  @override
  Future<Administrador> criarAdministradorAutomatico(
      {required String id, required String email, required String nome}) async {
    await store.preparar();
    final admin = Administrador(
        id: id, email: email, nome: nome, criadoEm: store.agora());
    _cadastro(admin);
    return admin;
  }
}
