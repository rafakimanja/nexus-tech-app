/// Exceções tipadas pra dar feedback específico ao usuário.
/// Cada categoria de erro tem mensagem e ação sugerida diferentes.
sealed class AppException implements Exception {
  final String message;
  const AppException(this.message);

  @override
  String toString() => message;
}

class RecursoIndisponivelException extends AppException {
  const RecursoIndisponivelException(String recurso)
      : super('$recurso ainda não está disponível nesta versão.');
}

/// Falha de rede ou conectividade
class NetworkException extends AppException {
  const NetworkException()
      : super('Sem conexão. Verifique sua internet e tente novamente.');
}

/// Operação negada por regras de segurança (Firestore Rules)
class PermissionException extends AppException {
  const PermissionException()
      : super('Você não tem permissão para realizar esta ação.');
}

/// Documento não encontrado no Firestore
class NotFoundException extends AppException {
  const NotFoundException(String recurso) : super('$recurso não encontrado.');
}

/// Falha genérica do servidor (erro 500, timeout, etc.)
class ServerException extends AppException {
  const ServerException()
      : super('Erro no servidor. Tente novamente em alguns instantes.');
}

/// Dado inválido fornecido pelo cliente
class ValidationException extends AppException {
  const ValidationException(super.message);
}

/// Conflito de concorrência: o recurso mudou de estado entre a leitura e a
/// escrita. Acontece, por exemplo, quando dois professores tentam marcar a
/// mesma demanda para análise — só o primeiro vence, o segundo recebe isto.
/// Usada pelas transações de mudança de status (UC09–UC12).
class ConflictException extends AppException {
  const ConflictException(super.message);
}

/// Falha de autenticação (login Google)
class AuthException extends AppException {
  const AuthException() : super('Falha na autenticação. Tente novamente.');
}

/// Ação bloqueada porque a conta do usuário está suspensa/banida (3 strikes)
/// ou o perfil de professor foi desativado pela administração.
/// Diferente de [PermissionException]: aqui a permissão existe em tese, mas o
/// estado da conta a suspende — a mensagem precisa explicar isso.
class ContaBloqueadaException extends AppException {
  const ContaBloqueadaException(super.message);
}
