import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/exceptions/app_exception.dart';
import '../../../core/models/demanda.dart';
import '../../../core/repositories/demanda_repository.dart';

/// Gerencia a lista "Minhas Demandas" do demandante.
/// Mantém os filtros aplicados em memória e re-subscreve no stream
/// quando os filtros mudam.
class DemandasProvider extends ChangeNotifier {
  final DemandaRepository _repository;

  DemandasProvider({required DemandaRepository repository})
      : _repository = repository;

  StreamSubscription<List<Demanda>>? _subscription;
  String? _demandanteIdAtual;

  List<Demanda> _todas = [];
  String _busca = '';
  StatusDemanda? _filtroStatus;
  FiltroPeriodo? _filtroPeriodo;
  bool _carregando = false;
  String? _erro;

  // ============== getters ==============

  bool get carregando => _carregando;
  String? get erro => _erro;
  StatusDemanda? get filtroStatus => _filtroStatus;
  FiltroPeriodo? get filtroPeriodo => _filtroPeriodo;
  String get busca => _busca;

  int get filtrosAtivos {
    var count = 0;
    if (_filtroStatus != null) count++;
    if (_filtroPeriodo != null) count++;
    return count;
  }

  bool get temFiltrosAtivos => filtrosAtivos > 0;

  /// Lista após filtro de busca (busca é client-side; status/período
  /// são server-side).
  List<Demanda> get demandas {
    if (_busca.isEmpty) return _todas;
    final query = _busca.toLowerCase();
    return _todas.where((d) => d.titulo.toLowerCase().contains(query)).toList();
  }

  // ============== ações ==============

  /// Inicia/atualiza a observação. Deve ser chamado quando o usuário
  /// loga ou quando os filtros server-side mudam.
  void observar(String demandanteId) {
    final mudou = _demandanteIdAtual != demandanteId;
    _demandanteIdAtual = demandanteId;
    if (mudou) {
      _todas = [];
    }
    _carregando = true;
    _erro = null;
    notifyListeners();

    _subscription?.cancel();
    _subscription = _repository
        .listarDoDemandante(
      demandanteId: demandanteId,
      filtroStatus: _filtroStatus,
      filtroPeriodo: _filtroPeriodo,
    )
        .listen(
      (lista) {
        _todas = lista;
        _carregando = false;
        _erro = null;
        notifyListeners();
      },
      onError: (Object e) {
        _carregando = false;
        _erro = e is AppException ? e.message : 'Erro ao carregar demandas';
        notifyListeners();
      },
    );
  }

  void atualizarBusca(String texto) {
    _busca = texto.trim();
    notifyListeners();
  }

  void aplicarFiltros({
    StatusDemanda? status,
    FiltroPeriodo? periodo,
  }) {
    _filtroStatus = status;
    _filtroPeriodo = periodo;
    if (_demandanteIdAtual != null) {
      observar(_demandanteIdAtual!);
    } else {
      notifyListeners();
    }
  }

  void limparFiltros() {
    aplicarFiltros(status: null, periodo: null);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
