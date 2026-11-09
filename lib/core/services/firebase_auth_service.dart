import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../constants/app_constants.dart';
import '../models/enums.dart';
import '../models/sessao_usuario.dart';
import '../repositories/usuario_repository.dart';
import 'auth_service.dart';

class FirebaseAuthService implements AuthService {
  final UsuarioRepository usuarios;
  final FirebaseAuth _auth;
  final GoogleSignIn _google;

  FirebaseAuthService({required this.usuarios})
      : _auth = FirebaseAuth.instance,
        _google = GoogleSignIn();

  SessaoUsuario? _mapear(User? user) {
    if (user == null) return null;
    final email = user.email ?? '';
    final normalizado = email.toLowerCase();
    final admin =
        AppConstants.adminEmails.any((e) => e.toLowerCase() == normalizado);
    final professor =
        normalizado.endsWith('@${AppConstants.professorEmailDomain}') ||
            AppConstants.professorTestEmails
                .any((e) => e.toLowerCase() == normalizado);
    return SessaoUsuario(
      id: user.uid,
      email: email,
      nome: user.displayName ?? email.split('@').first,
      fotoUrl: user.photoURL,
      role: admin
          ? UserRole.administrador
          : professor
              ? UserRole.professor
              : UserRole.demandante,
    );
  }

  @override
  SessaoUsuario? get currentUser => _mapear(_auth.currentUser);

  @override
  Stream<SessaoUsuario?> get authStateChanges =>
      _auth.authStateChanges().asyncMap((user) async {
        final sessao = _mapear(user);
        // Compatibilidade do Firebase: a futura API será responsável por isso.
        if (sessao != null &&
            sessao.role == UserRole.administrador &&
            await usuarios.buscarPorId(sessao.id) == null) {
          await usuarios.criarAdministradorAutomatico(
            id: sessao.id,
            email: sessao.email,
            nome: sessao.nome,
          );
        }
        return sessao;
      });

  @override
  Future<SessaoUsuario?> signInWithGoogle() async {
    final googleUser = await _google.signIn();
    if (googleUser == null) return null;
    final googleAuth = await googleUser.authentication;
    final result =
        await _auth.signInWithCredential(GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    ));
    return _mapear(result.user);
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    await _google.signOut();
  }
}
