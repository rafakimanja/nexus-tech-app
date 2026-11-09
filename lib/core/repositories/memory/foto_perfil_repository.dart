import 'dart:convert';
import 'dart:io';
import '../../exceptions/app_exception.dart';
import '../foto_perfil_repository.dart';
import 'memory_store.dart';

/// Foto efêmera em memória, sem serviço de armazenamento externo.
class MemoryFotoPerfilRepository implements FotoPerfilRepository {
  final MemoryStore store;
  MemoryFotoPerfilRepository(this.store);
  @override
  Future<String> enviarFoto(
      {required String id,
      required String caminhoLocal,
      required String formato}) async {
    await store.preparar();
    store.exigirUsuario(id: id);
    if (!FotoPerfilRepository.formatosPermitidos
        .contains(formato.toLowerCase()))
      throw const ValidationException('Use uma imagem JPG ou PNG.');
    final file = File(caminhoLocal);
    final size = await file.length();
    if (size == 0 || size > FotoPerfilRepository.tamanhoMaximoBytes)
      throw const ValidationException('Use uma imagem válida de até 5 MB.');
    final bytes = await file.readAsBytes();
    return 'data:image/${formato.toLowerCase() == 'png' ? 'png' : 'jpeg'};base64,${base64Encode(bytes)}';
  }
}
