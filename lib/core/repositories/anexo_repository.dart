import '../models/anexo.dart';

/// Contrato de dados independente do backend.
abstract interface class AnexoRepository {
  static const Set<String> formatosPermitidos = {'pdf', 'docx', 'jpg', 'png'};

  /// UC20 R02: tamanho máximo 10MB.
  static const int tamanhoMaximoBytes = 10 * 1024 * 1024;

  /// Valida se um arquivo pendente passa nas regras de negócio.
  /// Retorna mensagem de erro ou null se OK.

  /// IMPORTANTE: a verificação de "antivírus" prevista em UC20 R03
  /// não é executável client-side de forma confiável. Aqui validamos
  /// apenas extensão + MIME inferido + tamanho. A verificação real
  /// deveria ser uma Cloud Function async pós-upload chamando uma
  /// API de scanner (VirusTotal, ClamAV server, etc) — fica como
  /// trabalho futuro de hardening de segurança.
  static String? validar(AnexoPendente anexo) {
    final formatoLower = anexo.formato.toLowerCase();
    if (!formatosPermitidos.contains(formatoLower)) {
      return 'Formato não permitido. Use: '
          '${formatosPermitidos.join(", ").toUpperCase()}';
    }
    if (anexo.tamanhoBytes > tamanhoMaximoBytes) {
      return 'Arquivo muito grande. Máximo 10MB '
          '(este: ${anexo.tamanhoFormatado})';
    }
    if (anexo.tamanhoBytes <= 0) {
      return 'Arquivo vazio ou corrompido';
    }
    return null;
  }

  Future<Anexo> upload({
    required String demandaId,
    required String id,
    required AnexoPendente pendente,
  });

  Future<void> remover({
    required String demandaId,
    required Anexo anexo,
  });
}
