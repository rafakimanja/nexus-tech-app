/// Representa uma área técnica ou área de interesse.
/// Mesma estrutura para ambas — diferenciamos pela coleção Firestore.
class Area {
  final String id;
  final String nome;
  final DateTime criadoEm;
  final String criadoPor; // id do professor que adicionou

  Area({
    required this.id,
    required this.nome,
    required this.criadoEm,
    required this.criadoPor,
  });

  /// Normaliza o nome: trim, capitaliza primeira letra de cada palavra.
  static String normalizarNome(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';

    return trimmed.split(RegExp(r'\s+')).map((palavra) {
      if (palavra.isEmpty) return palavra;
      return palavra[0].toUpperCase() + palavra.substring(1).toLowerCase();
    }).join(' ');
  }

  /// Chave usada para detectar duplicatas (lowercase, sem espaços extras).
  /// Persistida no Firestore para permitir query indexada.
  String get chave => nome.toLowerCase().trim();

  Map<String, dynamic> toMap() => {
        'nome': nome,
        'chave': chave,
        'criadoEm': criadoEm.toIso8601String(),
        'criadoPor': criadoPor,
      };

  factory Area.fromMap(String id, Map<String, dynamic> map) => Area(
        id: id,
        nome: map['nome'] as String,
        criadoEm: DateTime.parse(map['criadoEm'] as String),
        criadoPor: map['criadoPor'] as String,
      );
}
