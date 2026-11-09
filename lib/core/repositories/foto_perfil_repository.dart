/// Contrato de dados independente do backend.
abstract interface class FotoPerfilRepository {
  static const int tamanhoMaximoBytes = 5 * 1024 * 1024;
  static const Set<String> formatosPermitidos = {'jpg', 'jpeg', 'png'};
  Future<String> enviarFoto({
    required String id,
    required String caminhoLocal,
    required String formato,
  });
}
