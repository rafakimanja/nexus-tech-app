import '../../exceptions/app_exception.dart';
import '../../models/anexo.dart';
import '../../models/chat.dart';
import '../anexo_repository.dart';
import '../chat_repository.dart';
import '../foto_perfil_repository.dart';

// Contratos ainda sem endpoints. Falham explicitamente, sem dados mock e sem
// gravar no Firebase por acidente. A interface também limita esses recursos.
class ApiAnexoRepository implements AnexoRepository {
  @override
  Future<Anexo> upload(
          {required String demandaId,
          required String id,
          required AnexoPendente pendente}) async =>
      throw const RecursoIndisponivelException('Anexos');
  @override
  Future<void> remover(
          {required String demandaId, required Anexo anexo}) async =>
      throw const RecursoIndisponivelException('Anexos');
}

class ApiFotoPerfilRepository implements FotoPerfilRepository {
  @override
  Future<String> enviarFoto(
          {required String id,
          required String caminhoLocal,
          required String formato}) async =>
      throw const RecursoIndisponivelException('Envio de foto');
}

class ApiChatRepository implements ChatRepository {
  @override
  Stream<List<Chat>> observarChats(String id) =>
      Stream.error(const RecursoIndisponivelException('Conversas'));
  @override
  Stream<Chat?> observarChat(String chatId) =>
      Stream.error(const RecursoIndisponivelException('Conversas'));
  @override
  Stream<List<Mensagem>> observarMensagens(String chatId) =>
      Stream.error(const RecursoIndisponivelException('Conversas'));
  @override
  Future<Chat?> buscar(String chatId) async =>
      throw const RecursoIndisponivelException('Conversas');
  @override
  Future<Chat?> buscarPorDemanda(String demandaId) async =>
      throw const RecursoIndisponivelException('Conversas');
  @override
  Future<void> enviarMensagem(
          {required String chatId,
          required String autorId,
          required String autorNome,
          required String texto}) async =>
      throw const RecursoIndisponivelException('Conversas');
  @override
  Future<void> registrarMensagemSistema(
          {required String chatId, required String texto}) async =>
      throw const RecursoIndisponivelException('Conversas');
  @override
  Future<void> marcarComoLido(
          {required String chatId, required String id}) async =>
      throw const RecursoIndisponivelException('Conversas');
  @override
  Future<void> encerrar(
          {required String chatId, required String motivo}) async =>
      throw const RecursoIndisponivelException('Conversas');
}
