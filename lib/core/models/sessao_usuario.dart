import 'enums.dart';

class SessaoUsuario {
  final String id;
  final String email;
  final String nome;
  final String? fotoUrl;
  final UserRole role;

  const SessaoUsuario({
    required this.id,
    required this.email,
    required this.nome,
    required this.role,
    this.fotoUrl,
  });
}
