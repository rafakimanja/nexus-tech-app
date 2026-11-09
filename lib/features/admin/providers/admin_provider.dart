import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/exceptions/app_exception.dart';
import '../../../core/models/demandante.dart';
import '../../../core/models/denuncia.dart';
import '../../../core/models/professor.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/repositories/denuncia_repository.dart';

/// Estado do painel administrativo: as três listas de trabalho do admin
/// (denúncias, professores, demandantes) e as ações que ele executa sobre elas.
///
/// As três listas ficam num provider só porque são a mesma sessão de trabalho:
/// julgar uma denúncia muda os strikes de um demandante e, no terceiro,
/// o banimento — o admin vê o efeito na aba ao lado sem recarregar nada.
class AdminProvider extends ChangeNotifier {
  final AdminRepository _adminRepository;
  final DenunciaRepository _denunciaRepository;
  final bool suportaModeracao;

  AdminProvider({
    required AdminRepository adminRepository,
    required DenunciaRepository denunciaRepository,
    this.suportaModeracao = true,
  })  : _adminRepository = adminRepository,
        _denunciaRepository = denunciaRepository;

  StreamSubscription<List<Denuncia>>? _subDenuncias;
  StreamSubscription<List<Professor>>? _subProfessores;
  StreamSubscription<List<Demandante>>? _subDemandantes;

  List<Denuncia> _denuncias = const [];
  List<Professor> _professores = const [];
  List<Demandante> _demandantes = const [];

  bool _carregandoDenuncias = false;
  bool _carregandoProfessores = false;
  bool _carregandoDemandantes = false;

  String? _erro;
  String? _erroDenuncias;
  String? _erroProfessores;
  String? _erroDemandantes;
  String? _processandoId;
  bool _observando = false;

  String _buscaProfessores = '';
  String _buscaDemandantes = '';
  bool _apenasDenunciasPendentes = true;

  // ============== getters ==============

  String? get erro => _erro;
  String? get erroDenuncias => _erroDenuncias;
  String? get erroProfessores => _erroProfessores;
  String? get erroDemandantes => _erroDemandantes;
  bool processando(String id) => _processandoId == id;
  bool get temAlgoProcessando => _processandoId != null;

  bool get carregandoDenuncias => _carregandoDenuncias;
  bool get carregandoProfessores => _carregandoProfessores;
  bool get carregandoDemandantes => _carregandoDemandantes;

  bool get apenasDenunciasPendentes => _apenasDenunciasPendentes;
  String get buscaProfessores => _buscaProfessores;
  String get buscaDemandantes => _buscaDemandantes;

  /// Fila de denúncias já respeitando o filtro pendentes/histórico.
  /// O filtro é aplicado no cliente porque a lista completa já está no stream —
  /// re-subscrever a cada toque no filtro custaria uma leitura por troca.
  List<Denuncia> get denuncias => _apenasDenunciasPendentes
      ? _denuncias.where((d) => d.pendente).toList()
      : _denuncias;

  int get denunciasPendentes => _denuncias.where((d) => d.pendente).length;

  /// Busca no que já está carregado — usado ao abrir uma denúncia a partir de
  /// uma notificação, sem custar uma leitura extra. `null` quando a denúncia
  /// não está na janela carregada (a tela cai no aviso de "não encontrada").
  Denuncia? denunciaPorId(String id) {
    for (final d in _denuncias) {
      if (d.id == id) return d;
    }
    return null;
  }

  List<Professor> get professores {
    if (_buscaProfessores.isEmpty) return _professores;
    final q = _buscaProfessores.toLowerCase();
    return _professores
        .where((p) =>
            p.nome.toLowerCase().contains(q) ||
            p.email.toLowerCase().contains(q) ||
            p.siape.contains(q))
        .toList();
  }

  List<Demandante> get demandantes {
    if (_buscaDemandantes.isEmpty) return _demandantes;
    final q = _buscaDemandantes.toLowerCase();
    return _demandantes
        .where((d) =>
            d.nome.toLowerCase().contains(q) ||
            d.email.toLowerCase().contains(q))
        .toList();
  }

  int get professoresAtivos => _professores.where((p) => p.ativo).length;
  int get professoresInativos => _professores.where((p) => !p.ativo).length;
  int get demandantesBanidos => _demandantes.where((d) => d.banido).length;

  // ============== ciclo de vida ==============

  /// Assina as três listas. Idempotente: chamada do `initState` da casca do
  /// painel, que pode reconstruir.
  void observar() {
    if (_observando) return;
    _observando = true;

    _carregandoDenuncias = true;
    _carregandoProfessores = true;
    _carregandoDemandantes = true;
    notifyListeners();

    _subDenuncias = _denunciaRepository.observarTodas().listen(
      (lista) {
        _denuncias = lista;
        _erroDenuncias = null;
        _carregandoDenuncias = false;
        notifyListeners();
      },
      onError: (Object e) => _falhaStream(e, 'denúncias', () {
        _carregandoDenuncias = false;
      }),
    );

    _subProfessores = _adminRepository.observarProfessores().listen(
      (lista) {
        _professores = lista;
        _erroProfessores = null;
        _carregandoProfessores = false;
        notifyListeners();
      },
      onError: (Object e) => _falhaStream(e, 'professores', () {
        _carregandoProfessores = false;
      }),
    );

    _subDemandantes = _adminRepository.observarDemandantes().listen(
      (lista) {
        _demandantes = lista;
        _erroDemandantes = null;
        _carregandoDemandantes = false;
        notifyListeners();
      },
      onError: (Object e) => _falhaStream(e, 'demandantes', () {
        _carregandoDemandantes = false;
      }),
    );
  }

  /// Encerra as observações e zera o estado (logout / troca de usuário).
  ///
  /// Sem isso, os streams do painel continuariam vivos depois que um admin sai
  /// — e o próximo usuário do aparelho os manteria abertos como ele mesmo,
  /// colhendo `permission-denied` a cada snapshot.
  void limpar() {
    _subDenuncias?.cancel();
    _subProfessores?.cancel();
    _subDemandantes?.cancel();
    _subDenuncias = null;
    _subProfessores = null;
    _subDemandantes = null;
    _observando = false;

    _denuncias = const [];
    _professores = const [];
    _demandantes = const [];
    _buscaProfessores = '';
    _buscaDemandantes = '';
    _erro = null;
    _erroDenuncias = null;
    _erroProfessores = null;
    _erroDemandantes = null;
    _carregandoDenuncias = false;
    _carregandoProfessores = false;
    _carregandoDemandantes = false;
    _processandoId = null;
    notifyListeners();
  }

  void _falhaStream(Object e, String recurso, VoidCallback desligarLoading) {
    desligarLoading();
    final mensagem = e is AppException
        ? e.message
        : 'Não foi possível carregar a lista de $recurso.';
    switch (recurso) {
      case 'denúncias':
        _erroDenuncias = mensagem;
      case 'professores':
        _erroProfessores = mensagem;
      case 'demandantes':
        _erroDemandantes = mensagem;
    }
    notifyListeners();
  }

  // ============== filtros ==============

  void alternarFiltroDenuncias(bool apenasPendentes) {
    _apenasDenunciasPendentes = apenasPendentes;
    notifyListeners();
  }

  void atualizarBuscaProfessores(String texto) {
    _buscaProfessores = texto.trim();
    notifyListeners();
  }

  void atualizarBuscaDemandantes(String texto) {
    _buscaDemandantes = texto.trim();
    notifyListeners();
  }

  // ============== ações ==============

  /// Julga uma denúncia. Retorna o resultado (strike/banimento) para a tela
  /// dar um retorno preciso; `null` em caso de falha, com [erro] preenchido.
  Future<ResultadoJulgamento?> julgar({
    required Denuncia denuncia,
    required bool procedente,
    required String adminId,
    required String adminNome,
    required String parecer,
  }) async {
    if (_processandoId != null) return null;
    _processandoId = denuncia.id;
    _erro = null;
    notifyListeners();

    try {
      final resultado = await _denunciaRepository.julgar(
        denuncia: denuncia,
        procedente: procedente,
        adminId: adminId,
        adminNome: adminNome,
        parecer: parecer,
      );
      return resultado;
    } on AppException catch (e) {
      _erro = e.message;
      return null;
    } catch (_) {
      _erro = 'Erro inesperado ao registrar a decisão.';
      return null;
    } finally {
      _processandoId = null;
      notifyListeners();
    }
  }

  Future<bool> definirProfessorAtivo({
    required Professor professor,
    required bool ativo,
    required String adminId,
    required String adminNome,
    String? motivo,
  }) {
    return _executar(
      professor.id,
      () => _adminRepository.definirProfessorAtivo(
        professor: professor,
        ativo: ativo,
        adminId: adminId,
        adminNome: adminNome,
        motivo: motivo,
      ),
    );
  }

  Future<bool> ajustarStrikes({
    required Demandante demandante,
    required int novoTotal,
    required String adminId,
    required String adminNome,
    required String motivo,
  }) {
    return _executar(
      demandante.id,
      () => _adminRepository.ajustarStrikes(
        demandante: demandante,
        novoTotal: novoTotal,
        adminId: adminId,
        adminNome: adminNome,
        motivo: motivo,
      ),
    );
  }

  Future<bool> reverterBanimento({
    required Demandante demandante,
    required String adminId,
    required String adminNome,
    required String motivo,
  }) {
    return _executar(
      demandante.id,
      () => _adminRepository.reverterBanimento(
        demandante: demandante,
        adminId: adminId,
        adminNome: adminNome,
        motivo: motivo,
      ),
    );
  }

  Future<bool> _executar(String id, Future<void> Function() acao) async {
    if (_processandoId != null) return false; // evita duplo-clique concorrente
    _processandoId = id;
    _erro = null;
    notifyListeners();

    try {
      await acao();
      return true;
    } on AppException catch (e) {
      _erro = e.message;
      return false;
    } catch (_) {
      _erro = 'Erro inesperado ao executar a ação.';
      return false;
    } finally {
      _processandoId = null;
      notifyListeners();
    }
  }

  void limparErro() {
    if (_erro == null) return;
    _erro = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _subDenuncias?.cancel();
    _subProfessores?.cancel();
    _subDemandantes?.cancel();
    super.dispose();
  }
}
