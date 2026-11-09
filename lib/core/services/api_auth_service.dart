import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../api/api_client.dart';
import '../api/api_dto.dart';
import '../exceptions/app_exception.dart';
import '../models/sessao_usuario.dart';
import 'auth_service.dart';
import 'api_push_service.dart';

class ApiAuthService implements AuthService {
  final ApiClient client;
  ApiPushService? push;
  final Future<String?> Function() _googleToken;
  final Future<void> Function() _googleSignOut;
  final _changes = StreamController<SessaoUsuario?>.broadcast();
  SessaoUsuario? _user;
  Timer? _expiry;
  bool _disposed = false;
  int _attempt = 0;
  final GoogleSignIn? _google;
  StreamSubscription<GoogleSignInAccount?>? _webSubscription;

  ApiAuthService(this.client,
      {required Future<String?> Function() googleToken,
      required Future<void> Function() googleSignOut,
      GoogleSignIn? google})
      : _googleToken = googleToken,
        _googleSignOut = googleSignOut,
        _google = google {
    client.onUnauthorized = _expire;
  }

  factory ApiAuthService.google(ApiClient client, {String clientId = ''}) {
    final google = GoogleSignIn(
        scopes: ['email', 'profile'],
        clientId: kIsWeb && clientId.isNotEmpty ? clientId : null,
        serverClientId: !kIsWeb && clientId.isNotEmpty ? clientId : null);
    return ApiAuthService(client, googleToken: () async {
      final account = await google.signIn();
      if (account == null) return null;
      final token = (await account.authentication).idToken;
      if (token == null || token.isEmpty) {
        throw const ValidationException(
            'Não foi possível obter a identidade Google. Confira a configuração do login.');
      }
      return token;
    }, googleSignOut: () async {
      await google.signOut();
    }, google: google);
  }

  /// Na Web o botão oficial GIS fornece o ID token; signIn() só autoriza scopes.
  Future<void> prepareWebSignIn() async {
    final google = _google;
    if (google == null) throw const AuthException();
    _webSubscription ??= google.onCurrentUserChanged.listen((account) async {
      if (account == null || _disposed) return;
      final attempt = ++_attempt;
      try {
        final token = (await account.authentication).idToken;
        if (token == null || token.isEmpty) throw const AuthException();
        await _exchange(token, attempt);
      } catch (e, stack) {
        if (!_disposed && attempt == _attempt) _changes.addError(e, stack);
        // Permite tentar novamente com a mesma conta após erro de rede/login.
        try {
          await google.signOut();
        } catch (_) {/* A falha de login já foi informada. */}
      }
    });
    await google.isSignedIn();
  }

  @override
  SessaoUsuario? get currentUser => _user;
  @override
  Stream<SessaoUsuario?> get authStateChanges => Stream.multi((controller) {
        final sub = _changes.stream.listen(controller.add,
            onError: controller.addError, onDone: controller.close);
        controller.add(_user);
        controller.onCancel = sub.cancel;
      });

  @override
  Future<SessaoUsuario?> signInWithGoogle() async {
    final attempt = ++_attempt;
    final token = await _googleToken();
    if (token == null || _disposed || attempt != _attempt) return null;
    return _exchange(token, attempt);
  }

  Future<SessaoUsuario?> _exchange(String token, int attempt) async {
    final result = await client.request('POST', '/login/v2',
        body: {'idToken': token}, authenticated: false) as Map<String, dynamic>;
    if (_disposed || attempt != _attempt) return null;
    final user = apiSession(result['user'] as Map<String, dynamic>);
    final accessToken = result['access_token'] as String;
    final remaining = DateTime.parse(result['expires_at'] as String)
        .difference(DateTime.now());
    if (accessToken.isEmpty ||
        result['token_type'] != 'Bearer' ||
        remaining <= Duration.zero) {
      throw const AuthException();
    }
    client.setToken(accessToken);
    _user = user;
    _expiry?.cancel();
    _expiry = Timer(remaining, _expire);
    _changes.add(user);
    push?.start();
    return user;
  }

  void _clear() {
    _attempt++;
    _expiry?.cancel();
    client.setToken(null);
    _user = null;
    if (!_disposed) _changes.add(null);
  }

  void _expire() {
    _clear();
    unawaited(push?.stop(expired: true).catchError((Object _) {}));
    // A sessão local já foi encerrada mesmo se o provedor estiver offline.
    unawaited(_googleSignOut().catchError((Object _) {}));
  }

  @override
  Future<void> signOut() async {
    await push?.stop();
    _clear();
    await _googleSignOut();
  }

  void dispose() {
    _disposed = true;
    _webSubscription?.cancel();
    _clear();
    client.onUnauthorized = null;
    _changes.close();
  }
}
