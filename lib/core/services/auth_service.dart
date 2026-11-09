import '../models/sessao_usuario.dart';

/// Identidade autenticada, sem expor tipos ou tokens do provedor à interface.
abstract interface class AuthService {
  SessaoUsuario? get currentUser;
  Stream<SessaoUsuario?> get authStateChanges;
  Future<SessaoUsuario?> signInWithGoogle();
  Future<void> signOut();
}
