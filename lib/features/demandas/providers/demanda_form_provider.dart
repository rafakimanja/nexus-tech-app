import '../../../core/models/criar_demanda.dart';
import 'package:flutter/foundation.dart';

import '../../../core/exceptions/app_exception.dart';
import '../../../core/models/anexo.dart';
import '../../../core/models/enums.dart';
import '../../../core/repositories/anexo_repository.dart';
import '../../../core/repositories/demanda_repository.dart';

enum DemandaFormStatus { initial, salvando, sucesso, erro }

enum DemandaFormModo { criar, editar }

/// Gerencia o formulário de criação/edição de demanda.
/// Mantém anexos pendentes (selecionados mas não enviados) em memória
/// até o submit — assim evita arquivos órfãos no Storage caso o usuário
/// desista no meio.
class DemandaFormProvider extends ChangeNotifier {
  final DemandaRepository _demandaRepository;
  final AnexoRepository _anexoRepository;

  DemandaFormProvider({
    required DemandaRepository demandaRepository,
    required AnexoRepository anexoRepository,
  })  : _demandaRepository = demandaRepository,
        _anexoRepository = anexoRepository;

  DemandaFormStatus _status = DemandaFormStatus.initial;
  String? _erro;
  String? _idDemandaCriadaOuEditada;

  // Anexos novos selecionados na sessão atual (ainda não enviados).
  final List<AnexoPendente> _anexosPendentes = [];
  // Anexos já existentes (modo edição) — necessário para mostrar na lista.
  List<Anexo> _anexosExistentes = [];

  DemandaFormStatus get status => _status;
  String? get erro => _erro;
  bool get salvando => _status == DemandaFormStatus.salvando;
  String? get idDemandaCriadaOuEditada => _idDemandaCriadaOuEditada;

  List<AnexoPendente> get anexosPendentes =>
      List.unmodifiable(_anexosPendentes);
  List<Anexo> get anexosExistentes => List.unmodifiable(_anexosExistentes);
  int get totalAnexos => _anexosPendentes.length + _anexosExistentes.length;

  // ============== anexos ==============

  /// Tenta adicionar anexo. Retorna mensagem de erro ou null se OK.
  String? adicionarAnexo(AnexoPendente anexo) {
    final erro = AnexoRepository.validar(anexo);
    if (erro != null) return erro;

    // Evita duplicata óbvia (mesmo nome + mesmo tamanho)
    final duplicado = _anexosPendentes.any((a) =>
        a.nomeLocal == anexo.nomeLocal && a.tamanhoBytes == anexo.tamanhoBytes);
    if (duplicado) return 'Este arquivo já foi selecionado';

    _anexosPendentes.add(anexo);
    notifyListeners();
    return null;
  }

  void removerAnexoPendente(int index) {
    if (index < 0 || index >= _anexosPendentes.length) return;
    _anexosPendentes.removeAt(index);
    notifyListeners();
  }

  void carregarAnexosExistentes(List<Anexo> anexos) {
    _anexosExistentes = anexos;
    notifyListeners();
  }

  Future<void> removerAnexoExistente({
    required String demandaId,
    required Anexo anexo,
  }) async {
    try {
      await _anexoRepository.remover(
        demandaId: demandaId,
        anexo: anexo,
      );
      _anexosExistentes.removeWhere((a) => a.id == anexo.id);
      notifyListeners();
    } catch (e) {
      _erro = e is AppException ? e.message : 'Erro ao remover anexo';
      notifyListeners();
    }
  }

  // ============== UC15 - criar ==============

  /// Cria a demanda. Se [originalCanceladaId] for fornecido, marca a
  /// demanda cancelada original com `republicadaComoId` na mesma
  /// transação atômica — impede que o demandante republique a mesma
  /// demanda múltiplas vezes.
  Future<bool> criar({
    required String demandanteId,
    required String demandanteNome,
    required TipoDemandante demandanteTipo,
    required String titulo,
    required String descricao,
    required String publicoAlvo,
    required String impacto,
    String? originalCanceladaId,
  }) async {
    try {
      _status = DemandaFormStatus.salvando;
      _erro = null;
      notifyListeners();

      final demanda = CriarDemanda(
        demandanteId: demandanteId,
        demandanteNome: demandanteNome,
        demandanteTipo: demandanteTipo,
        titulo: titulo.trim(),
        descricao: descricao.trim(),
        publicoAlvo: publicoAlvo.trim(),
        impacto: impacto.trim(),
      );

      final id = await _demandaRepository.criar(
        demanda,
        originalCanceladaId: originalCanceladaId,
      );

      // Upload de anexos pendentes
      // Se um anexo falhar, os outros ainda sobem e a demanda foi criada.
      for (final pendente in _anexosPendentes) {
        try {
          await _anexoRepository.upload(
            demandaId: id,
            id: demandanteId,
            pendente: pendente,
          );
        } catch (e) {
          // Log mas não aborta — demanda já foi criada.
          debugPrint('Falha ao enviar anexo ${pendente.nomeLocal}: $e');
        }
      }

      _idDemandaCriadaOuEditada = id;
      _status = DemandaFormStatus.sucesso;
      _anexosPendentes.clear();
      notifyListeners();
      return true;
    } on AppException catch (e) {
      _erro = e.message;
      _status = DemandaFormStatus.erro;
      notifyListeners();
      return false;
    } catch (e) {
      _erro = 'Erro inesperado ao cadastrar demanda';
      _status = DemandaFormStatus.erro;
      notifyListeners();
      return false;
    }
  }

  // ============== UC17 - editar ==============

  Future<bool> editar({
    required String demandaId,
    required String autorId,
    required String titulo,
    required String descricao,
    required String publicoAlvo,
    required String impacto,
  }) async {
    try {
      _status = DemandaFormStatus.salvando;
      _erro = null;
      notifyListeners();

      await _demandaRepository.atualizar(
        id: demandaId,
        autorId: autorId,
        titulo: titulo.trim(),
        descricao: descricao.trim(),
        publicoAlvo: publicoAlvo.trim(),
        impacto: impacto.trim(),
      );

      // Upload dos anexos pendentes adicionados durante a edição
      for (final pendente in _anexosPendentes) {
        try {
          await _anexoRepository.upload(
            demandaId: demandaId,
            id: autorId,
            pendente: pendente,
          );
        } catch (e) {
          debugPrint('Falha ao enviar anexo ${pendente.nomeLocal}: $e');
        }
      }

      _idDemandaCriadaOuEditada = demandaId;
      _status = DemandaFormStatus.sucesso;
      _anexosPendentes.clear();
      notifyListeners();
      return true;
    } on AppException catch (e) {
      _erro = e.message;
      _status = DemandaFormStatus.erro;
      notifyListeners();
      return false;
    } catch (e) {
      _erro = 'Erro inesperado ao editar demanda';
      _status = DemandaFormStatus.erro;
      notifyListeners();
      return false;
    }
  }

  // ============== UC16 - cancelar ==============

  Future<bool> cancelar({
    required String demandaId,
    required String autorId,
    required String motivo,
  }) async {
    try {
      _status = DemandaFormStatus.salvando;
      _erro = null;
      notifyListeners();

      await _demandaRepository.cancelar(
        id: demandaId,
        autorId: autorId,
        motivo: motivo.trim(),
      );

      _status = DemandaFormStatus.sucesso;
      notifyListeners();
      return true;
    } on AppException catch (e) {
      _erro = e.message;
      _status = DemandaFormStatus.erro;
      notifyListeners();
      return false;
    } catch (e) {
      _erro = 'Erro inesperado ao cancelar demanda';
      _status = DemandaFormStatus.erro;
      notifyListeners();
      return false;
    }
  }

  void resetar() {
    _status = DemandaFormStatus.initial;
    _erro = null;
    _idDemandaCriadaOuEditada = null;
    _anexosPendentes.clear();
    _anexosExistentes = [];
    notifyListeners();
  }
}
