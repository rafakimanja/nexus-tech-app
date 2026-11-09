import './area_selecionada.dart';
import 'enums.dart';
import 'usuario.dart';

class Professor extends Usuario {
  final String siape;
  final List<AreaSelecionada> areasTecnicas;
  final List<AreaSelecionada> areasInteresse;

  /// Perfil habilitado a atuar na plataforma (UC04 R01). O admin liga/desliga
  /// pelo painel; um professor desativado não vê a prateleira nem executa
  /// transições de demanda.
  final bool ativo;

  final DateTime? desativadoEm;
  final String? motivoDesativacao;

  Professor({
    required super.id,
    required super.email,
    required super.nome,
    required super.criadoEm,
    required this.siape,
    required this.areasTecnicas,
    required this.areasInteresse,
    this.ativo = true,
    this.desativadoEm,
    this.motivoDesativacao,
    super.fotoUrl,
  }) : super(role: UserRole.professor);

  @override
  Map<String, dynamic> toMap() => {
        'uid': id,
        'email': email,
        'nome': nome,
        'role': role.name,
        'criadoEm': criadoEm.toIso8601String(),
        'siape': siape,
        'areasTecnicas': areasTecnicas.map((a) => a.nome).toList(),
        'areasInteresse': areasInteresse.map((a) => a.nome).toList(),
        'ativo': ativo,
        'desativadoEm': desativadoEm?.toIso8601String(),
        'motivoDesativacao': motivoDesativacao,
        'fotoUrl': fotoUrl,
      };

  factory Professor.fromMap(Map<String, dynamic> map) => Professor(
        id: map['uid'] as String,
        email: map['email'] as String,
        nome: map['nome'] as String,
        criadoEm: DateTime.parse(map['criadoEm'] as String),
        siape: map['siape'] as String,
        areasTecnicas: List<String>.from(map['areasTecnicas'] ?? const [])
            .map(AreaSelecionada.legada)
            .toList(),
        areasInteresse: List<String>.from(map['areasInteresse'] ?? const [])
            .map(AreaSelecionada.legada)
            .toList(),
        ativo: map['ativo'] as bool? ?? true,
        desativadoEm: DateTime.tryParse(map['desativadoEm'] as String? ?? ''),
        motivoDesativacao: map['motivoDesativacao'] as String?,
        fotoUrl: map['fotoUrl'] as String?,
      );
}
