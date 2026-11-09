import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/exceptions/app_exception.dart';
import '../../../core/models/chat.dart';
import '../../../core/repositories/chat_repository.dart';

/// Lista de conversas do usuário logado (as duas pontas usam o mesmo provider).
///
/// A conversa em si **não** passa por aqui: a tela de chat consome os streams
/// do repositório direto, no mesmo padrão das telas de detalhe de demanda. O
/// provider global existe pelo que é global de verdade — a lista e o total de
/// mensagens não lidas que alimenta o badge da barra inferior.
class ChatsProvider extends ChangeNotifier {
  final ChatRepository _repository;

  ChatsProvider({required ChatRepository repository})
      : _repository = repository;

  StreamSubscription<List<Chat>>? _sub;
  List<Chat> _chats = const [];
  bool _carregando = false;
  String? _erro;
  String? _id;
  String _busca = '';

  bool get carregando => _carregando;
  String? get erro => _erro;
  String get busca => _busca;

  /// Conversas filtradas pela busca (título da demanda ou nome do interlocutor).
  /// Client-side, coerente com §7.3 da arquitetura: são dezenas de conversas.
  List<Chat> get chats {
    if (_busca.isEmpty) return _chats;
    final q = _busca.toLowerCase();
    final id = _id;
    return _chats.where((c) {
      final outro = id == null ? '' : c.outroNome(id).toLowerCase();
      return c.tituloDemanda.toLowerCase().contains(q) || outro.contains(q);
    }).toList();
  }

  /// Soma das não lidas de todas as conversas — o número do badge.
  int get totalNaoLidas {
    final id = _id;
    if (id == null) return 0;
    return _chats.fold(0, (soma, c) => soma + c.naoLidasDe(id));
  }

  bool get temNaoLidas => totalNaoLidas > 0;

  void observar(String id) {
    if (_id == id && _sub != null) return;
    _id = id;

    _carregando = true;
    _erro = null;
    notifyListeners();

    _sub?.cancel();
    _sub = _repository.observarChats(id).listen(
      (lista) {
        _chats = lista;
        _carregando = false;
        _erro = null;
        notifyListeners();
      },
      onError: (Object e) {
        _carregando = false;
        _erro = e is AppException
            ? e.message
            : 'Não foi possível carregar suas conversas.';
        notifyListeners();
      },
    );
  }

  void atualizarBusca(String texto) {
    _busca = texto.trim();
    notifyListeners();
  }

  void limpar() {
    _sub?.cancel();
    _sub = null;
    _id = null;
    _chats = const [];
    _busca = '';
    _erro = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
