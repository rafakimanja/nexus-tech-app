import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/exceptions/app_exception.dart';
import '../../../core/models/notificacao.dart';
import '../../../core/repositories/notificacao_repository.dart';

/// Central de notificações in-app.
///
/// Mantém **um único stream** para os dois consumidores — o badge do sino e a
/// tela da central. Abrir a tela não custa leitura nova, e o badge nunca fica
/// dessincronizado da lista, porque ambos derivam da mesma fonte.
class NotificacoesProvider extends ChangeNotifier {
  final NotificacaoRepository _repository;

  NotificacoesProvider({required NotificacaoRepository repository})
      : _repository = repository;

  StreamSubscription<List<Notificacao>>? _sub;
  List<Notificacao> _notificacoes = const [];
  bool _carregando = false;
  String? _erro;
  String? _id;
  bool _disposed = false;

  List<Notificacao> get notificacoes => _notificacoes;
  bool get carregando => _carregando;
  String? get erro => _erro;

  int get naoLidas => _notificacoes.where((n) => !n.lida).length;
  bool get temNaoLidas => naoLidas > 0;

  /// Inicia a observação. Idempotente para o mesmo usuário — chamada dos
  /// `initState` das telas raiz de cada papel.
  void observar(String id) {
    if (_id == id && _sub != null) return;
    _id = id;

    _carregando = true;
    _erro = null;
    if (!_disposed) notifyListeners();

    _sub?.cancel();
    _sub = _repository.observar(id).listen(
      (lista) {
        _notificacoes = lista;
        _carregando = false;
        _erro = null;
        if (!_disposed) notifyListeners();
      },
      onError: (Object e) {
        _carregando = false;
        _erro = e is AppException
            ? e.message
            : 'Não foi possível carregar suas notificações.';
        if (!_disposed) notifyListeners();
      },
    );
  }

  /// Encerra a observação (logout). Zera a lista para que o badge do próximo
  /// usuário não herde a contagem do anterior.
  void limpar() {
    _sub?.cancel();
    _sub = null;
    _id = null;
    _notificacoes = const [];
    _erro = null;
    if (!_disposed) notifyListeners();
  }

  /// Marca como lida. Não faz nada se já estiver lida — evita escrita inútil
  /// a cada toque numa notificação antiga.
  Future<void> marcarComoLida(Notificacao n) async {
    if (n.lida) return;
    try {
      await _repository.marcarComoLida(n.id);
    } on AppException catch (e) {
      _erro = e.message;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> marcarTodasComoLidas() async {
    final id = _id;
    if (id == null || !temNaoLidas) return;
    try {
      await _repository.marcarTodasComoLidas(id);
    } on AppException catch (e) {
      _erro = e.message;
      if (!_disposed) notifyListeners();
    }
  }

  void limparErro() {
    if (_erro == null) return;
    _erro = null;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
