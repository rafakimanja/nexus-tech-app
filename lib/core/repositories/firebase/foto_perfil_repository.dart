import '../foto_perfil_repository.dart';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

import '../../exceptions/app_exception.dart';
import '../../exceptions/firestore_error_handler.dart';

/// Upload da foto de perfil do usuário no Firebase Storage, em
/// `users/{id}/foto_{timestamp}.{ext}`.
///
/// A validação aqui (formato + tamanho) é UX; a regra real está no
/// storage.rules (só o dono escreve, somente imagem, até 5 MB).
class FirebaseFotoPerfilRepository implements FotoPerfilRepository {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  static const int tamanhoMaximoBytes = 5 * 1024 * 1024; // 5 MB
  static const Set<String> formatosPermitidos = {'jpg', 'jpeg', 'png'};

  /// Envia a imagem e retorna a URL pública de download.
  @override
  Future<String> enviarFoto({
    required String id,
    required String caminhoLocal,
    required String formato,
  }) async {
    final fmt = formato.toLowerCase();
    if (!formatosPermitidos.contains(fmt)) {
      throw const ValidationException('Use uma imagem JPG ou PNG.');
    }

    final arquivo = File(caminhoLocal);
    final tamanho = await arquivo.length();
    if (tamanho > tamanhoMaximoBytes) {
      throw const ValidationException('Imagem muito grande. Máximo de 5 MB.');
    }
    if (tamanho <= 0) {
      throw const ValidationException('Imagem vazia ou corrompida.');
    }

    final nome = 'foto_${DateTime.now().millisecondsSinceEpoch}.$fmt';
    final ref = _storage.ref('users/$id/$nome');

    try {
      final task = await ref.putFile(
        arquivo,
        SettableMetadata(
          contentType: fmt == 'png' ? 'image/png' : 'image/jpeg',
          customMetadata: {'enviadoPorUid': id},
        ),
      );
      return await task.ref.getDownloadURL();
    } catch (e) {
      // Best-effort: se o binário subiu mas a URL falhou, tenta limpar.
      try {
        await ref.delete();
      } catch (_) {/* ignore */}
      if (e is AppException) rethrow;
      throw mapFirestoreError(e, recurso: 'Foto de perfil');
    }
  }
}
