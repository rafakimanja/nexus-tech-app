import 'package:flutter/foundation.dart';

import '../../../core/exceptions/app_exception.dart';
import '../../../core/models/anexo.dart';
import '../../../core/repositories/anexo_repository.dart';
import '../../../core/repositories/demanda_repository.dart';

/// Estado transitório das AÇÕES do professor sobre uma demanda
/// (UC09 marcar análise · UC10 rejeitar · UC11 assumir · UC12 concluir).
///
/// As listas em si são atualizadas em tempo real pelos streams do
/// [ProfessorDemandasProvider]; este provider só carrega o estado efêmero da
/// operação (qual demanda está processando + último erro), para a UI mostrar
/// spinner no lugar certo e mensagens de falha.
class AcaoDemandaProvider extends ChangeNotifier {
  final DemandaRepository _demandaRepository;
  final AnexoRepository _anexoRepository;

  AcaoDemandaProvider({
    required DemandaRepository demandaRepository,
    required AnexoRepository anexoRepository,
  })  : _demandaRepository = demandaRepository,
        _anexoRepository = anexoRepository;

  String? _processandoId;
  String? _erro;

  String? get erro => _erro;

  /// `true` se há uma ação em andamento para [demandaId] — usado para
  /// desabilitar botões e mostrar spinner apenas naquela demanda.
  bool processando(String demandaId) => _processandoId == demandaId;

  bool get temAlgoProcessando => _processandoId != null;

  // ============== UC09 — marcar para análise ==============

  Future<bool> marcarParaAnalise({
    required String demandaId,
    required String professorId,
    required String professorNome,
  }) {
    return _executar(
      demandaId,
      () => _demandaRepository.marcarParaAnalise(
        demandaId: demandaId,
        professorId: professorId,
        professorNome: professorNome,
      ),
    );
  }

  // ============== UC10 — rejeitar ==============

  Future<bool> rejeitar({
    required String demandaId,
    required String professorId,
  }) {
    return _executar(
      demandaId,
      () => _demandaRepository.rejeitarAnalise(
        demandaId: demandaId,
        professorId: professorId,
      ),
    );
  }

  // ============== UC11 — assumir ==============

  Future<bool> assumir({
    required String demandaId,
    required String professorId,
  }) {
    return _executar(
      demandaId,
      () => _demandaRepository.assumir(
        demandaId: demandaId,
        professorId: professorId,
      ),
    );
  }

  // ============== UC12 — concluir (com anexos da entrega) ==============

  /// Envia os anexos da entrega e conclui a demanda.
  ///
  /// Os anexos são o entregável (UC12 passo 07 valida antes de concluir),
  /// então sobem ANTES da transição: se algum falhar, abortamos e NÃO
  /// concluímos — o professor corrige e tenta de novo. Cada anexo que sobe
  /// com sucesso é removido de [anexos] (lista mutável vinda da tela), de
  /// modo que um retry não duplique o que já foi enviado.
  ///
  /// UC12 A01: conclusão sem anexos é permitida desde que haja descrição.
  Future<bool> concluir({
    required String demandaId,
    required String professorId,
    required String descricaoSolucao,
    required List<AnexoPendente> anexos,
  }) {
    return _executar(demandaId, () async {
      while (anexos.isNotEmpty) {
        final pendente = anexos.first;
        await _anexoRepository.upload(
          demandaId: demandaId,
          id: professorId,
          pendente: pendente,
        );
        anexos.removeAt(0);
      }

      await _demandaRepository.concluir(
        demandaId: demandaId,
        professorId: professorId,
        descricaoSolucao: descricaoSolucao.trim(),
      );
    });
  }

  // ============== infra ==============

  Future<bool> _executar(String demandaId, Future<void> Function() acao) async {
    if (_processandoId != null) return false; // evita duplo-clique concorrente
    _processandoId = demandaId;
    _erro = null;
    notifyListeners();

    try {
      await acao();
      _processandoId = null;
      notifyListeners();
      return true;
    } on AppException catch (e) {
      _erro = e.message;
      _processandoId = null;
      notifyListeners();
      return false;
    } catch (e) {
      _erro = 'Erro inesperado ao processar a demanda.';
      _processandoId = null;
      notifyListeners();
      return false;
    }
  }

  void limparErro() {
    if (_erro == null) return;
    _erro = null;
    notifyListeners();
  }
}
