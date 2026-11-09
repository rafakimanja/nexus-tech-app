import '../../../core/models/area_selecionada.dart';
import 'package:flutter/foundation.dart';

import '../../../core/exceptions/app_exception.dart';
import '../../../core/models/enums.dart';
import '../../../core/repositories/foto_perfil_repository.dart';
import '../../../core/repositories/usuario_repository.dart';

/// Estado da tela de perfil/edição (UC23). Trata o salvamento dos dados e o
/// envio da nova foto de forma independente (cada um com seu flag de loading).
class PerfilProvider extends ChangeNotifier {
  final UsuarioRepository _usuarioRepository;
  final FotoPerfilRepository _fotoRepository;

  PerfilProvider({
    required UsuarioRepository usuarioRepository,
    required FotoPerfilRepository fotoRepository,
  })  : _usuarioRepository = usuarioRepository,
        _fotoRepository = fotoRepository;

  bool _salvando = false;
  bool _enviandoFoto = false;
  String? _erro;

  bool get salvando => _salvando;
  bool get enviandoFoto => _enviandoFoto;
  String? get erro => _erro;

  // ============== dados ==============

  Future<bool> salvarDemandante({
    required String id,
    required String nome,
    required String telefone,
    required TipoDemandante tipo,
    required String endereco,
  }) {
    return _salvar(() => _usuarioRepository.atualizarDemandante(
          id: id,
          nome: nome,
          telefone: telefone,
          tipo: tipo,
          endereco: endereco,
        ));
  }

  Future<bool> salvarProfessor({
    required String id,
    required String nome,
    required List<AreaSelecionada> areasTecnicas,
    required List<AreaSelecionada> areasInteresse,
  }) {
    return _salvar(() => _usuarioRepository.atualizarProfessor(
          id: id,
          nome: nome,
          areasTecnicas: areasTecnicas,
          areasInteresse: areasInteresse,
        ));
  }

  Future<bool> _salvar(Future<void> Function() acao) async {
    if (_salvando) return false;
    _salvando = true;
    _erro = null;
    notifyListeners();
    try {
      await acao();
      _salvando = false;
      notifyListeners();
      return true;
    } on AppException catch (e) {
      _erro = e.message;
      _salvando = false;
      notifyListeners();
      return false;
    } catch (e) {
      _erro = 'Erro inesperado ao salvar o perfil.';
      _salvando = false;
      notifyListeners();
      return false;
    }
  }

  // ============== foto ==============

  /// Envia a nova foto e grava a URL no documento do usuário.
  /// Retorna `true` em sucesso. A tela recarrega o usuário depois para
  /// refletir a nova `fotoUrl`.
  Future<bool> trocarFoto({
    required String id,
    required String caminhoLocal,
    required String formato,
  }) async {
    if (_enviandoFoto) return false;
    _enviandoFoto = true;
    _erro = null;
    notifyListeners();
    try {
      final url = await _fotoRepository.enviarFoto(
        id: id,
        caminhoLocal: caminhoLocal,
        formato: formato,
      );
      await _usuarioRepository.atualizarFotoUrl(id: id, fotoUrl: url);
      _enviandoFoto = false;
      notifyListeners();
      return true;
    } on AppException catch (e) {
      _erro = e.message;
      _enviandoFoto = false;
      notifyListeners();
      return false;
    } catch (e) {
      _erro = 'Erro inesperado ao enviar a foto.';
      _enviandoFoto = false;
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
