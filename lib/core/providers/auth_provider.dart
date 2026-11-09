import 'dart:async';
import 'package:flutter/foundation.dart';

import '../exceptions/app_exception.dart';
import '../models/demandante.dart';
import '../models/enums.dart';
import '../models/professor.dart';
import '../models/sessao_usuario.dart';
import '../models/usuario.dart';
import '../repositories/usuario_repository.dart';
import '../services/auth_service.dart';

enum AuthStatus {
  initial,
  autenticando,
  naoAutenticado,
  autenticadoSemCadastro,
  autenticado,
  erro
}

class AuthProvider extends ChangeNotifier {
  final AuthService _authService;
  final UsuarioRepository _usuarioRepository;
  late final StreamSubscription<SessaoUsuario?> _subAuth;
  StreamSubscription<Usuario?>? _subUsuario;
  AuthStatus _status = AuthStatus.initial;
  Usuario? _usuario;
  SessaoUsuario? _sessao;
  String? _erro;
  int _geracao = 0;
  bool _disposed = false;

  AuthProvider(
      {required AuthService authService,
      required UsuarioRepository usuarioRepository})
      : _authService = authService,
        _usuarioRepository = usuarioRepository {
    _subAuth =
        _authService.authStateChanges.listen(_onAuthChanged, onError: _onErro);
  }

  AuthStatus get status => _status;
  Usuario? get usuario => _usuario;
  SessaoUsuario? get sessao => _sessao;
  String? get erro => _erro;
  bool get contaBanida =>
      _usuario is Demandante && (_usuario as Demandante).banido;
  bool get professorInativo =>
      _usuario is Professor && !(_usuario as Professor).ativo;
  bool get isProfessor => _sessao?.role == UserRole.professor;

  Future<void> _onAuthChanged(SessaoUsuario? sessao) async {
    final geracao = ++_geracao;
    _sessao = sessao;
    _usuario = null;
    _erro = null;
    _status =
        sessao == null ? AuthStatus.naoAutenticado : AuthStatus.autenticando;
    if (!_disposed) notifyListeners();
    // Desliga a assinatura imediatamente, sem prender a nova sessão à limpeza
    // assíncrona do backend anterior. A geração já descarta eventos atrasados.
    final anterior = _subUsuario;
    _subUsuario = null;
    unawaited(anterior?.cancel());
    if (_disposed || geracao != _geracao) return;
    if (sessao == null) return;
    _subUsuario = _usuarioRepository.observarPorId(sessao.id).listen((usuario) {
      if (_disposed || geracao != _geracao) return;
      _usuario = usuario;
      _status = usuario == null
          ? AuthStatus.autenticadoSemCadastro
          : AuthStatus.autenticado;
      _erro = null;
      notifyListeners();
    }, onError: (Object erro) {
      if (!_disposed && geracao == _geracao) _onErro(erro);
    });
  }

  void _onErro(Object erro) {
    if (_disposed) return;
    _usuario = null;
    _erro = erro is AppException
        ? erro.message
        : 'Falha ao carregar sua sessão. Tente novamente.';
    _status = AuthStatus.erro;
    notifyListeners();
  }

  Future<void> entrarComGoogle() async {
    _status = AuthStatus.autenticando;
    _erro = null;
    notifyListeners();
    try {
      final sessao = await _authService.signInWithGoogle();
      if (sessao == null && !_disposed) {
        _status = AuthStatus.naoAutenticado;
        notifyListeners();
      }
    } catch (e) {
      _onErro(e);
    }
  }

  Future<void> sair() => _authService.signOut();
  Future<void> recarregarUsuario() => _onAuthChanged(_authService.currentUser);

  @override
  void dispose() {
    _disposed = true;
    _geracao++;
    _subAuth.cancel();
    _subUsuario?.cancel();
    super.dispose();
  }
}
