import '../core/repositories/admin_repository.dart';
import '../core/repositories/firebase/admin_repository.dart';
import '../core/repositories/anexo_repository.dart';
import '../core/repositories/firebase/anexo_repository.dart';
import '../core/repositories/area_repository.dart';
import '../core/repositories/firebase/area_repository.dart';
import '../core/repositories/chat_repository.dart';
import '../core/repositories/firebase/chat_repository.dart';
import '../core/repositories/demanda_repository.dart';
import '../core/repositories/firebase/demanda_repository.dart';
import '../core/repositories/denuncia_repository.dart';
import '../core/repositories/firebase/denuncia_repository.dart';
import '../core/repositories/foto_perfil_repository.dart';
import '../core/repositories/firebase/foto_perfil_repository.dart';
import '../core/repositories/notificacao_repository.dart';
import '../core/repositories/firebase/notificacao_repository.dart';
import '../core/repositories/usuario_repository.dart';
import '../core/repositories/firebase/usuario_repository.dart';
import '../core/services/auth_service.dart';
import '../core/services/firebase_auth_service.dart';
import '../core/api/api_client.dart';
import '../core/services/api_auth_service.dart';
import '../core/services/api_push_service.dart';
import '../core/repositories/api/admin_repository.dart';
import '../core/repositories/api/notificacao_repository.dart';
import '../core/repositories/api/denuncia_repository.dart';
import '../core/repositories/api/area_repository.dart';
import '../core/repositories/api/demanda_repository.dart';
import '../core/repositories/api/usuario_repository.dart';
import '../core/repositories/api/recursos_indisponiveis.dart';

/// Único ponto de composição dos backends. Não há fallback entre eles.
class AppDependencies {
  final AuthService auth;
  final ApiPushService? push;
  final AdminRepository admin;
  final AnexoRepository anexo;
  final AreaRepository area;
  final ChatRepository chat;
  final DemandaRepository demanda;
  final DenunciaRepository denuncia;
  final FotoPerfilRepository fotoPerfil;
  final NotificacaoRepository notificacao;
  final UsuarioRepository usuario;
  final bool usaApi;
  final void Function()? _disposeApi;

  AppDependencies({
    required this.auth,
    this.push,
    required this.admin,
    required this.anexo,
    required this.area,
    required this.chat,
    required this.demanda,
    required this.denuncia,
    required this.fotoPerfil,
    required this.notificacao,
    required this.usuario,
    this.usaApi = false,
    void Function()? disposeApi,
  }) : _disposeApi = disposeApi;

  factory AppDependencies.api(
      {required String baseUrl,
      String googleClientId = '',
      bool enablePush = false}) {
    final client = ApiClient(baseUrl);
    final auth = ApiAuthService.google(client, clientId: googleClientId);
    final push =
        enablePush ? ApiPushService(client, FirebasePushMessaging()) : null;
    auth.push = push;
    return AppDependencies(
      usaApi: true,
      push: push,
      auth: auth,
      usuario: ApiUsuarioRepository(client),
      area: ApiAreaRepository(client),
      demanda: ApiDemandaRepository(client),
      admin: ApiAdminRepository(client),
      anexo: ApiAnexoRepository(),
      chat: ApiChatRepository(),
      denuncia: ApiDenunciaRepository(client),
      fotoPerfil: ApiFotoPerfilRepository(),
      notificacao: ApiNotificacaoRepository(client),
      disposeApi: () {
        push?.dispose();
        auth.dispose();
        client.dispose();
      },
    );
  }

  factory AppDependencies.firebase() {
    final notificacao = FirebaseNotificacaoRepository();
    final chat = FirebaseChatRepository(notificacaoRepository: notificacao);
    final demanda = FirebaseDemandaRepository(
        chatRepository: chat, notificacaoRepository: notificacao);
    final usuario = FirebaseUsuarioRepository();
    return AppDependencies(
        auth: FirebaseAuthService(usuarios: usuario),
        usuario: usuario,
        notificacao: notificacao,
        chat: chat,
        demanda: demanda,
        admin: FirebaseAdminRepository(notificacaoRepository: notificacao),
        denuncia:
            FirebaseDenunciaRepository(notificacaoRepository: notificacao),
        area: FirebaseAreaRepository(),
        anexo: FirebaseAnexoRepository(demandaRepository: demanda),
        fotoPerfil: FirebaseFotoPerfilRepository());
  }

  void dispose() {
    _disposeApi?.call();
  }
}
