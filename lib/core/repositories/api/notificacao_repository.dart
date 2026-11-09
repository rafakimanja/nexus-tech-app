import '../../api/api_client.dart';
import '../../api/api_dto.dart';
import '../../exceptions/app_exception.dart';
import '../../models/notificacao.dart';
import '../notificacao_repository.dart';

/// Percorre o histórico inteiro para que o badge inclua todas as não lidas.
class ApiNotificacaoRepository implements NotificacaoRepository {
  final ApiClient client;
  ApiNotificacaoRepository(this.client);

  Future<List<Notificacao>> listar() async {
    final items = await apiPages(client, '/notifications');
    return items
        .map((m) => Notificacao(
              id: apiId(m['id']),
              destinatarioId: apiId(m['user_id']),
              autorId: '',
              autorNome: 'Nexus Tech',
              tipo: TipoNotificacao.from(m['type'] as String?),
              titulo: m['title'] as String,
              corpo: m['body'] as String,
              criadoEm: DateTime.parse(m['created_at'] as String),
              lida: m['read_at'] != null,
              lidaEm: m['read_at'] == null
                  ? null
                  : DateTime.parse(m['read_at'] as String),
              demandaId: m['resource_type'] == 'demand'
                  ? apiId(m['resource_id'])
                  : null,
              denunciaId: m['resource_type'] == 'report'
                  ? apiId(m['resource_id'])
                  : null,
            ))
        .toList();
  }

  @override
  Stream<List<Notificacao>> observar(String id) => client.watch(listar);
  @override
  Future<void> marcarComoLida(String id) async {
    await client.request('PATCH', '/notifications/${numericId(id)}/read');
  }

  @override
  Future<void> marcarTodasComoLidas(String id) async {
    await client.request('PATCH', '/notifications/read-all');
  }

  // Os destinatários e eventos são determinados exclusivamente pelo servidor.
  @override
  Future<void> enfileirar(
          {required String destinatarioId,
          required String autorId,
          required String autorNome,
          required TipoNotificacao tipo,
          required String titulo,
          required String corpo,
          String? demandaId,
          String? chatId,
          String? denunciaId}) async =>
      throw const RecursoIndisponivelException(
          'Criação manual de notificações');
}

Future<List<Map<String, dynamic>>> apiPages(
    ApiClient client, String path) async {
  final result = <Map<String, dynamic>>[];
  int? before;
  while (true) {
    final page = apiList(await client.request(
        'GET', '$path?limit=100${before == null ? '' : '&before=$before'}'));
    if (page.isEmpty) return result;
    final next = numericId(apiId(page.last['id']));
    if (before != null && next >= before) throw const ServerException();
    result.addAll(page);
    if (page.length < 100) return result;
    before = next;
  }
}
