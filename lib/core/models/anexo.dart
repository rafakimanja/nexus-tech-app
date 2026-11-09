/// Anexos vivem na subcoleção `demandas/{id}/anexos` e o arquivo binário
/// no Firebase Storage em `demandas/{demandaId}/anexos/{anexoId}_{nome}`.
class Anexo {
  final String id;
  final String nome;
  final String url;
  final int tamanhoBytes;
  final String formato; // pdf, docx, jpg, png
  final String enviadoPorId;
  final DateTime enviadoEm;

  const Anexo({
    required this.id,
    required this.nome,
    required this.url,
    required this.tamanhoBytes,
    required this.formato,
    required this.enviadoPorId,
    required this.enviadoEm,
  });

  String get tamanhoFormatado {
    if (tamanhoBytes < 1024) return '$tamanhoBytes B';
    if (tamanhoBytes < 1024 * 1024) {
      return '${(tamanhoBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(tamanhoBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Map<String, dynamic> toMap() => {
        'nome': nome,
        'url': url,
        'tamanhoBytes': tamanhoBytes,
        'formato': formato,
        'enviadoPorUid': enviadoPorId,
        'enviadoEm': enviadoEm.toIso8601String(),
      };

  factory Anexo.fromMap(String id, Map<String, dynamic> map) => Anexo(
        id: id,
        nome: map['nome'] as String,
        url: map['url'] as String,
        tamanhoBytes: map['tamanhoBytes'] as int,
        formato: map['formato'] as String,
        enviadoPorId: map['enviadoPorUid'] as String,
        enviadoEm: DateTime.parse(map['enviadoEm'] as String),
      );
}

/// Anexo ainda não enviado — existe só em memória até o submit do form.
/// Mantém o caminho local até o upload acontecer.
class AnexoPendente {
  final String nomeLocal;
  final String caminhoLocal;
  final int tamanhoBytes;
  final String formato;

  const AnexoPendente({
    required this.nomeLocal,
    required this.caminhoLocal,
    required this.tamanhoBytes,
    required this.formato,
  });

  String get tamanhoFormatado {
    if (tamanhoBytes < 1024 * 1024) {
      return '${(tamanhoBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(tamanhoBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
