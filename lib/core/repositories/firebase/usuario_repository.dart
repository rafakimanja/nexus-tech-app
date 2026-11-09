import '../../models/area_selecionada.dart';
import '../usuario_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../constants/app_constants.dart';
import '../../exceptions/firestore_error_handler.dart';
import '../../models/administrador.dart';
import '../../models/demandante.dart';
import '../../models/enums.dart';
import '../../models/professor.dart';
import '../../models/usuario.dart';

class FirebaseUsuarioRepository implements UsuarioRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection(AppConstants.collectionUsers);

  @override
  Future<Usuario?> buscarPorId(String id) async {
    try {
      final doc = await _users.doc(id).get();
      return await _desserializar(doc.data());
    } catch (e) {
      throw mapFirestoreError(e, recurso: 'Usuário');
    }
  }

  /// Observa o próprio perfil em tempo real.
  ///
  /// Existe para que decisões administrativas cheguem **na sessão aberta**:
  /// quando o admin bane um demandante ou desativa um professor, o app precisa
  /// reagir sem esperar um novo login. Com uma leitura pontual, o usuário
  /// continuaria operando com o perfil antigo até fechar o app.
  ///
  /// Emite `null` quando o documento não existe (primeiro acesso, antes do
  /// cadastro) ou quando o `role` está ausente/corrompido — ambos os casos são
  /// tratados como "precisa cadastrar".
  @override
  Stream<Usuario?> observarPorId(String id) {
    return _users
        .doc(id)
        .snapshots()
        .asyncMap((doc) => _desserializar(doc.data()));
  }

  /// Instancia a subclasse certa a partir do `role` gravado.
  /// `null` para documento inexistente ou com role inválido.
  Future<Usuario?> _desserializar(Map<String, dynamic>? data) async {
    if (data == null) return null;

    final roleStr = data['role'] as String?;
    if (roleStr == null) {
      // Documento corrompido: existe mas sem role válido.
      // Trata como inexistente para forçar novo cadastro.
      return null;
    }

    final role = UserRole.values.where((e) => e.name == roleStr).firstOrNull;
    if (role == null) return null;

    return switch (role) {
      UserRole.professor => await _resolverAreas(Professor.fromMap(data)),
      UserRole.demandante => Demandante.fromMap(data),
      UserRole.administrador => Administrador.fromMap(data),
    };
  }

  /// Perfis antigos guardam nomes. Só associa um ID quando há correspondência
  /// única no catálogo do tipo; entradas ausentes/ambíguas permanecem legadas.
  Future<Professor> _resolverAreas(Professor p) async {
    Future<List<AreaSelecionada>> resolver(
        List<AreaSelecionada> lista, String colecao) async {
      if (lista.isEmpty) return [];
      final snapshot = await _firestore.collection(colecao).get();
      return lista.map((area) {
        final matches =
            snapshot.docs.where((d) => d.data()['nome'] == area.nome).toList();
        return matches.length == 1
            ? AreaSelecionada(id: matches.single.id, nome: area.nome)
            : area;
      }).toList();
    }

    final listas = await Future.wait([
      resolver(p.areasTecnicas, AppConstants.collectionAreasTecnicas),
      resolver(p.areasInteresse, AppConstants.collectionAreasInteresse),
    ]);
    return Professor(
        id: p.id,
        email: p.email,
        nome: p.nome,
        criadoEm: p.criadoEm,
        siape: p.siape,
        areasTecnicas: listas[0],
        areasInteresse: listas[1],
        ativo: p.ativo,
        fotoUrl: p.fotoUrl,
        desativadoEm: p.desativadoEm,
        motivoDesativacao: p.motivoDesativacao);
  }

  /// Ids dos administradores cadastrados — destinatários das denúncias.
  ///
  /// Lê da coleção em vez de derivar de `AppConstants.adminEmails` porque a
  /// notificação precisa de **id**, e o e-mail só vira id depois do primeiro
  /// login do admin. Um admin que nunca entrou no app não recebe notificação
  /// in-app — ele verá a fila de denúncias assim que entrar.
  ///
  /// Best-effort: falhar aqui não pode impedir o registro da denúncia.
  @override
  Future<Set<String>> buscarAdminIds() async {
    try {
      final snap = await _users
          .where('role', isEqualTo: UserRole.administrador.name)
          .get();
      return snap.docs.map((d) => d.id).toSet();
    } catch (_) {
      return const {};
    }
  }

  @override
  Future<void> criarProfessor(Professor professor) async {
    try {
      await _users.doc(professor.id).set(professor.toMap());
    } catch (e) {
      throw mapFirestoreError(e, recurso: 'Professor');
    }
  }

  @override
  Future<void> criarDemandante(Demandante demandante) async {
    try {
      await _users.doc(demandante.id).set(demandante.toMap());
    } catch (e) {
      throw mapFirestoreError(e, recurso: 'Demandante');
    }
  }

  // ! ===========================
  // ! UC23 - EDITAR PERFIL
  // ! ===========================

  @override
  Future<void> atualizarDemandante({
    required String id,
    required String nome,
    required String telefone,
    required TipoDemandante tipo,
    required String endereco,
  }) async {
    try {
      await _users.doc(id).update({
        'nome': nome.trim(),
        'telefone': telefone.replaceAll(RegExp(r'\D'), ''),
        'tipo': tipo.name,
        'endereco': endereco.trim(),
      });
    } catch (e) {
      throw mapFirestoreError(e, recurso: 'Perfil');
    }
  }

  @override
  Future<void> atualizarProfessor({
    required String id,
    required String nome,
    required List<AreaSelecionada> areasTecnicas,
    required List<AreaSelecionada> areasInteresse,
  }) async {
    try {
      await _users.doc(id).update({
        'nome': nome.trim(),
        'areasTecnicas': areasTecnicas.map((a) => a.nome).toList(),
        'areasInteresse': areasInteresse.map((a) => a.nome).toList(),
      });
    } catch (e) {
      throw mapFirestoreError(e, recurso: 'Perfil');
    }
  }

  @override
  Future<void> atualizarFotoUrl({
    required String id,
    required String fotoUrl,
  }) async {
    try {
      await _users.doc(id).update({'fotoUrl': fotoUrl});
    } catch (e) {
      throw mapFirestoreError(e, recurso: 'Foto de perfil');
    }
  }

  /// Cria perfil de administrador automaticamente no primeiro acesso.
  /// Retorna o objeto criado (evita refetch posterior).
  @override
  Future<Administrador> criarAdministradorAutomatico({
    required String id,
    required String email,
    required String nome,
  }) async {
    try {
      final admin = Administrador(
        id: id,
        email: email,
        nome: nome,
        criadoEm: DateTime.now(),
      );
      await _users.doc(id).set(admin.toMap());
      return admin;
    } catch (e) {
      throw mapFirestoreError(e, recurso: 'Administrador');
    }
  }
}

extension _IterableFirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
