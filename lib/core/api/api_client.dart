import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../exceptions/app_exception.dart';

/// Transporte compartilhado. Nunca envia o token Google aos endpoints de dados.
class ApiClient {
  final Uri baseUrl;
  final http.Client _http;
  final Duration timeout;
  final Duration pollInterval;
  final _changes = StreamController<void>.broadcast();
  String? _token;
  int _session = 0;
  bool _closed = false;
  void Function()? onUnauthorized;
  void Function()? onAccountBlocked;

  ApiClient(String url,
      {http.Client? client,
      this.timeout = const Duration(seconds: 20),
      this.pollInterval = const Duration(seconds: 15)})
      : baseUrl = Uri.parse(url),
        _http = client ?? http.Client() {
    if (!baseUrl.hasAuthority ||
        !{'https', 'http'}.contains(baseUrl.scheme) ||
        baseUrl.userInfo.isNotEmpty ||
        baseUrl.hasQuery ||
        baseUrl.hasFragment) {
      throw const ValidationException('API_BASE_URL inválida.');
    }
  }

  void refresh() {
    if (!_closed) _changes.add(null);
  }

  void setToken(String? token) {
    _token = token;
    _session++;
  }

  Future<dynamic> request(String method, String path,
      {Map<String, dynamic>? body, bool authenticated = true}) async {
    if (_closed) throw const NetworkException();
    final session = _session;
    final token = _token;
    if (authenticated && token == null) throw const AuthException();
    final uri = Uri.parse(
        '${baseUrl.toString().replaceFirst(RegExp(r'/+$'), '')}$path');
    final request = http.Request(method, uri)
      ..followRedirects = false
      ..headers['Accept'] = 'application/json';
    if (authenticated) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    late http.Response response;
    try {
      response = await _http
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
    } on TimeoutException {
      throw const NetworkException();
    } on http.ClientException {
      throw const NetworkException();
    }
    if (authenticated && session != _session) throw const AuthException();
    dynamic data;
    if (response.bodyBytes.isNotEmpty) {
      try {
        data = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          throw const ServerException();
        }
      }
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (method != 'GET' && !_closed) _changes.add(null);
      return data;
    }
    final error = data is Map ? data['error'] : null;
    final message = error is Map ? error['message'] : error;
    switch (response.statusCode) {
      case 400:
        throw const ValidationException(
            'Confira os campos informados e tente novamente.');
      case 401:
        if (authenticated) onUnauthorized?.call();
        throw const AuthException();
      case 403:
        if (message == 'account blocked') {
          onAccountBlocked?.call();
          throw const ContaBloqueadaException(
              'Esta conta está bloqueada. Contate a administração.');
        }
        throw const PermissionException();
      case 404:
        throw const NotFoundException('Registro');
      case 409:
        throw ConflictException(message == 'account requires identity linking'
            ? 'Esta conta precisa ser vinculada ao Google pela administração.'
            : 'O registro já existe ou mudou de estado. Atualize e tente novamente.');
      default:
        throw const ServerException();
    }
  }

  /// Polling enquanto há assinatura, com atualização imediata após mutações.
  /// Falhas são emitidas sem encerrar a observação; não há requisições sobrepostas.
  Stream<T> watch<T>(Future<T> Function() read) {
    late StreamController<T> controller;
    Timer? timer;
    StreamSubscription<void>? changes;
    bool active = true, busy = false, again = false;
    final session = _session;
    Future<void> refresh() async {
      if (!active || _closed || controller.isPaused || session != _session) {
        return;
      }
      if (busy) {
        again = true;
        return;
      }
      busy = true;
      do {
        again = false;
        try {
          final value = await read();
          if (active && !_closed && session == _session) controller.add(value);
        } catch (e, stack) {
          if (active && !_closed && session == _session) {
            controller.addError(e, stack);
          }
        }
      } while (again && active && !_closed && session == _session);
      busy = false;
    }

    controller = StreamController<T>(
        onListen: () {
          changes = _changes.stream.listen((_) => refresh(), onDone: () {
            active = false;
            timer?.cancel();
            controller.close();
          });
          timer = Timer.periodic(pollInterval, (_) => refresh());
          refresh();
        },
        onResume: refresh,
        onCancel: () {
          active = false;
          timer?.cancel();
          return changes?.cancel();
        });
    return controller.stream;
  }

  void dispose() {
    _closed = true;
    _token = null;
    _http.close();
    _changes.close();
  }
}
