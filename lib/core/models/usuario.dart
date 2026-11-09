import 'enums.dart';

abstract class Usuario {
  final String id;
  final String email;
  final String nome;
  final UserRole role;
  final DateTime criadoEm;

  /// URL da foto de perfil enviada pelo próprio usuário (Firebase Storage).
  /// Quando `null`, a UI cai na foto do Google (`sessao.fotoUrl`) e,
  /// na ausência dela, nas iniciais do nome.
  final String? fotoUrl;

  const Usuario({
    required this.id,
    required this.email,
    required this.nome,
    required this.role,
    required this.criadoEm,
    this.fotoUrl,
  });

  Map<String, dynamic> toMap();
}
