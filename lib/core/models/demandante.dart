import '../constants/app_constants.dart';
import 'enums.dart';
import 'usuario.dart';

class Demandante extends Usuario {
  final String telefone;
  final TipoDemandante tipo;
  final String cpfCnpj;
  final String endereco;

  /// Advertências acumuladas por denúncias julgadas procedentes.
  /// Em [AppConstants.strikesParaBanimento] a conta é banida.
  final int strikes;

  /// `true` quando a conta atingiu o limite de strikes. Banimento é
  /// **permanente por decisão administrativa**: só um admin reverte
  /// (`AdminRepository.reverterBanimento`), o que zera os strikes.
  final bool banido;
  final DateTime? banidoEm;
  final String? motivoBanimento;

  Demandante({
    required super.id,
    required super.email,
    required super.nome,
    required super.criadoEm,
    required this.telefone,
    required this.tipo,
    required this.cpfCnpj,
    required this.endereco,
    this.strikes = 0,
    this.banido = false,
    this.banidoEm,
    this.motivoBanimento,
    super.fotoUrl,
  }) : super(role: UserRole.demandante);

  /// Quantos strikes ainda faltam para o banimento. Zero quando já banido.
  int get strikesRestantes =>
      banido ? 0 : (AppConstants.strikesParaBanimento - strikes).clamp(0, 99);

  @override
  Map<String, dynamic> toMap() => {
        'uid': id,
        'email': email,
        'nome': nome,
        'role': role.name,
        'criadoEm': criadoEm.toIso8601String(),
        'telefone': telefone,
        'tipo': tipo.name,
        'cpfCnpj': cpfCnpj,
        'endereco': endereco,
        'strikes': strikes,
        'banido': banido,
        'banidoEm': banidoEm?.toIso8601String(),
        'motivoBanimento': motivoBanimento,
        'fotoUrl': fotoUrl,
      };

  factory Demandante.fromMap(Map<String, dynamic> map) => Demandante(
        id: map['uid'] as String,
        email: map['email'] as String,
        nome: map['nome'] as String,
        criadoEm: DateTime.parse(map['criadoEm'] as String),
        telefone: map['telefone'] as String,
        tipo: TipoDemandante.values.firstWhere(
          (e) => e.name == map['tipo'],
          orElse: () => TipoDemandante.pessoaFisica,
        ),
        cpfCnpj: map['cpfCnpj'] as String,
        endereco: map['endereco'] as String,
        strikes: (map['strikes'] as num?)?.toInt() ?? 0,
        // Contas criadas antes do sistema de strikes não têm o campo.
        banido: map['banido'] as bool? ?? false,
        banidoEm: DateTime.tryParse(map['banidoEm'] as String? ?? ''),
        motivoBanimento: map['motivoBanimento'] as String?,
        fotoUrl: map['fotoUrl'] as String?,
      );
}
