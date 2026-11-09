import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../api/api_client.dart';

abstract interface class PushMessaging {
  Future<bool> requestPermission();
  Future<String?> getToken();
  Future<void> deleteToken();
  Stream<String> get onTokenRefresh;
}

class FirebasePushMessaging implements PushMessaging {
  final FirebaseMessaging messaging = FirebaseMessaging.instance;
  @override
  Future<bool> requestPermission() async =>
      (await messaging.requestPermission()).authorizationStatus ==
      AuthorizationStatus.authorized;
  @override
  Future<String?> getToken() => messaging.getToken();
  @override
  Future<void> deleteToken() => messaging.deleteToken();
  @override
  Stream<String> get onTokenRefresh => messaging.onTokenRefresh;
}

/// Serializa registro e remoção para não vincular um token após o logout.
class ApiPushService extends ChangeNotifier {
  final ApiClient client;
  final PushMessaging messaging;
  ApiPushService(this.client, this.messaging);
  StreamSubscription<String>? _tokens;
  StreamSubscription<RemoteMessage>? _messages;
  StreamSubscription<RemoteMessage>? _opened;
  Timer? _retry;
  Future<void> _pending = Future.value();
  Future<void>? _stopping;
  bool _active = false;
  bool _disposed = false;
  String? _registered;
  Map<String, dynamic>? pendingOpen;

  Future<void> listenFirebase() async {
    _messages = FirebaseMessaging.onMessage.listen((_) => client.refresh());
    _opened = FirebaseMessaging.onMessageOpenedApp.listen((m) => open(m.data));
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null && !_disposed) open(initial.data);
  }

  void open(Map<String, dynamic> data) {
    pendingOpen = data;
    notifyListeners();
  }

  void start() {
    if (_active || _disposed) return;
    final stopping = _stopping;
    if (stopping != null) {
      unawaited(stopping.then((_) => start(), onError: (Object _) {}));
      return;
    }
    _active = true;
    _tokens = messaging.onTokenRefresh
        .listen((_) => _register(), onError: (Object _) {});
    _retry = Timer.periodic(const Duration(seconds: 30), (_) => _register());
    _register();
  }

  void _register() {
    _pending = _pending.then((_) async {
      if (!_active || !await messaging.requestPermission() || !_active) return;
      final token = await messaging.getToken();
      if (!_active || token == null || token == _registered) return;
      await client
          .request('PUT', '/notifications/devices', body: {'token': token});
      _registered = token;
    }).catchError((Object _) {
      // O histórico HTTP continua disponível; o timer tenta novamente.
    });
  }

  Future<void> stop({bool expired = false}) => _stopping ??=
      _stop(expired: expired).whenComplete(() => _stopping = null);

  Future<void> _stop({required bool expired}) async {
    _active = false;
    _retry?.cancel();
    await _tokens?.cancel();
    _tokens = null;
    pendingOpen = null;
    await _pending;
    // Obtém também o token de um PUT cujo resultado ficou incerto por timeout.
    try {
      final token = _registered ?? await messaging.getToken();
      if (token == null) return;
      if (expired) throw StateError('Sessão expirada');
      await client
          .request('DELETE', '/notifications/devices', body: {'token': token});
    } catch (_) {
      await messaging.deleteToken();
    } finally {
      _registered = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _active = false;
    _retry?.cancel();
    _tokens?.cancel();
    _messages?.cancel();
    _opened?.cancel();
    super.dispose();
  }
}
