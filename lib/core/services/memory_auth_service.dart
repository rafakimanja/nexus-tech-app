import '../exceptions/app_exception.dart';
import '../models/sessao_usuario.dart';
import '../repositories/memory/memory_store.dart';
import 'auth_service.dart';

class MemoryAuthService implements AuthService {
  final MemoryStore store;
  MemoryAuthService(this.store);

  @override
  SessaoUsuario? get currentUser => store.sessao;

  @override
  Stream<SessaoUsuario?> get authStateChanges =>
      store.observar(() => store.sessao).distinct();

  Future<void> entrarComo(String id) async {
    await store.preparar();
    final contas = store.contas.where((c) => c.id == id);
    if (contas.isEmpty) throw const AuthException();
    store.sessao = contas.first;
    store.notificar();
  }

  @override
  Future<SessaoUsuario?> signInWithGoogle() async {
    throw const ValidationException('Escolha uma conta de demonstração.');
  }

  @override
  Future<void> signOut() async {
    store.sessao = null;
    store.notificar();
  }
}
