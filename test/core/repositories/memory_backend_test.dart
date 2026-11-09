import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_tech/app/app_config.dart';
import 'package:nexus_tech/app/app_dependencies.dart';
import 'package:nexus_tech/core/exceptions/app_exception.dart';
import 'package:nexus_tech/core/models/area_selecionada.dart';
import 'package:nexus_tech/core/models/criar_demanda.dart';
import 'package:nexus_tech/core/models/demanda.dart';
import 'package:nexus_tech/core/models/demandante.dart';
import 'package:nexus_tech/core/models/denuncia.dart';
import 'package:nexus_tech/core/models/enums.dart';
import 'package:nexus_tech/core/models/professor.dart';
import 'package:nexus_tech/core/repositories/area_repository.dart';
import 'package:nexus_tech/core/repositories/memory/memory_store.dart';

const entrada = CriarDemanda(
    demandanteId: '1',
    demandanteNome: 'Associação do Bairro',
    demandanteTipo: TipoDemandante.ong,
    titulo: 'Agenda comunitária',
    descricao: 'Organizar as atividades da comunidade.',
    publicoAlvo: 'Moradores',
    impacto: 'Facilitar o atendimento.');

void main() {
  late MemoryStore store;
  late AppDependencies deps;
  late DateTime agora;
  setUp(() {
    agora = DateTime.utc(2026, 11, 4, 15);
    store = MemoryStore(agora: () => agora);
    deps = AppDependencies.memory(store: store);
  });
  tearDown(() async {
    await store.dispose();
  });
  Future<void> entrar(String id) => deps.entrarDemonstracao!(id);

  test('configuração inválida não escolhe silenciosamente outro backend', () {
    expect(AppConfig.parse('firebase').backend, AppBackend.firebase);
    expect(AppConfig.parse('memory').backend, AppBackend.memory);
    expect(AppConfig.parse('api').backend, AppBackend.api);
    expect(() => AppConfig.parse('invalido'), throwsArgumentError);
  });

  test('criação e edição são refletidas pelo mesmo stream e usam ID gerado',
      () async {
    await entrar('1');
    final eventos = <List<Demanda>>[];
    final sub =
        deps.demanda.listarDoDemandante(demandanteId: '1').listen(eventos.add);
    await Future<void>.delayed(Duration.zero);
    final id = await deps.demanda.criar(entrada);
    expect(int.parse(id), greaterThan(0));
    expect(store.demandas[id]!.criadoEm, agora);
    await deps.demanda.atualizar(
        id: id,
        autorId: '1',
        titulo: 'Agenda nova',
        descricao: entrada.descricao,
        publicoAlvo: entrada.publicoAlvo,
        impacto: entrada.impacto);
    await Future<void>.delayed(Duration.zero);
    expect(eventos.last.singleWhere((d) => d.id == id).titulo, 'Agenda nova');
    await sub.cancel();
  });

  test('ciclo completo compartilha demanda, conversa, mensagens e notificações',
      () async {
    await entrar('1');
    final id = await deps.demanda.criar(entrada);
    await entrar('2');
    await deps.demanda.marcarParaAnalise(
        demandaId: id, professorId: '2', professorNome: 'Professor 2');
    expect(store.demandas[id]!.analiseExpiraEm,
        agora.add(const Duration(hours: 24)));
    await deps.demanda.assumir(demandaId: id, professorId: '2');
    final chat = (await deps.chat.buscarPorDemanda(id))!;
    expect(chat.id, isNot(id));
    expect(chat.demandaId, id);
    await deps.chat.enviarMensagem(
        chatId: chat.id,
        autorId: '2',
        autorNome: 'Professor 2',
        texto: 'Vamos começar.');
    await entrar('1');
    expect(
        (await deps.chat.observarChats('1').first)
            .singleWhere((c) => c.id == chat.id)
            .naoLidasDe('1'),
        1);
    expect(
        (await deps.notificacao.observar('1').first)
            .where((n) => n.demandaId == id),
        isNotEmpty);
    await deps.chat.marcarComoLido(chatId: chat.id, id: '1');
    expect((await deps.chat.buscar(chat.id))!.naoLidasDe('1'), 0);
    await entrar('2');
    await deps.demanda.concluir(
        demandaId: id, professorId: '2', descricaoSolucao: 'Agenda entregue.');
    expect(store.demandas[id]!.status, StatusDemanda.concluida);
    expect((await deps.chat.buscar(chat.id))!.ativo, false);
    await expectLater(
        deps.chat.enviarMensagem(
            chatId: chat.id,
            autorId: '2',
            autorNome: 'Professor 2',
            texto: 'Nova mensagem'),
        throwsA(isA<ConflictException>()));
  });

  test('reservas concorrentes não duplicam atribuição nem notificações',
      () async {
    await entrar('2');
    Future<Object?> reservar() async {
      try {
        await deps.demanda.marcarParaAnalise(
            demandaId: '101', professorId: '2', professorNome: 'Professor 2');
        return null;
      } catch (e) {
        return e;
      }
    }

    final resultados = await Future.wait([reservar(), reservar()]);
    expect(resultados.where((r) => r == null).length, 1);
    expect(resultados.whereType<ConflictException>().length, 1);
    expect(
        store.notificacoes.values.where((n) => n.demandaId == '101').length, 1);
    await entrar('4');
    await expectLater(deps.demanda.assumir(demandaId: '101', professorId: '4'),
        throwsA(isA<ConflictException>()));
  });

  test('prazo vencido libera a demanda e impede assunção atrasada', () async {
    await entrar('2');
    await deps.demanda.marcarParaAnalise(
        demandaId: '101', professorId: '2', professorNome: 'Professor 2');
    agora = agora.add(const Duration(hours: 24));
    await expectLater(deps.demanda.assumir(demandaId: '101', professorId: '2'),
        throwsA(isA<ConflictException>()));
    final d = (await deps.demanda.observar('101').first)!;
    expect(d.status, StatusDemanda.cadastrada);
    expect(d.professorId, isNull);
    expect(d.analiseExpiraEm, isNull);
  });

  test('devolução remove atribuição e permite nova reserva', () async {
    await entrar('2');
    await deps.demanda.rejeitarAnalise(demandaId: '102', professorId: '2');
    expect(store.demandas['102']!.professorId, isNull);
    await entrar('4');
    await deps.demanda.marcarParaAnalise(
        demandaId: '102', professorId: '4', professorNome: 'Professor 4');
    expect(store.demandas['102']!.professorId, '4');
  });

  test('cancelamento e republicação preservam original e impedem duplicata',
      () async {
    await entrar('1');
    await deps.demanda
        .cancelar(id: '101', autorId: '1', motivo: 'Mudança de prioridades');
    final id = await deps.demanda.criar(entrada, originalCanceladaId: '101');
    expect(store.demandas['101']!.status, StatusDemanda.cancelada);
    expect(store.demandas['101']!.republicadaComoId, id);
    expect(store.demandas[id]!.status, StatusDemanda.cadastrada);
    await expectLater(deps.demanda.criar(entrada, originalCanceladaId: '101'),
        throwsA(isA<ConflictException>()));
  });

  test('falha simulada não grava nem retorna sucesso', () async {
    await entrar('1');
    final total = store.demandas.length;
    store.proximaFalha = const NetworkException();
    await expectLater(
        deps.demanda.criar(entrada), throwsA(isA<NetworkException>()));
    expect(store.demandas.length, total);
    store.proximaFalha = const NetworkException();
    await expectLater(deps.demanda.listarDoDemandante(demandanteId: '1').first,
        throwsA(isA<NetworkException>()));
  });

  test('logout e bloqueio impedem operações', () async {
    await entrar('8');
    await expectLater(deps.demanda.listarPrateleira().first,
        throwsA(isA<ContaBloqueadaException>()));
    await deps.auth.signOut();
    await expectLater(
        deps.demanda.criar(entrada), throwsA(isA<AuthException>()));
  });

  test('cadastro de professor preserva IDs e separa os tipos de associação',
      () async {
    await entrar('6');
    expect(await deps.usuario.buscarPorId('6'), isNull);
    final tecnicas = await deps.area.listar(TipoArea.tecnica);
    final interesses = await deps.area.listar(TipoArea.interesse);
    expect(tecnicas.map((a) => a.id), interesses.map((a) => a.id));
    final p = Professor(
        id: '6',
        email: 'nova.docente@example.test',
        nome: 'Nova professora',
        criadoEm: agora,
        siape: '0001234',
        areasTecnicas: [
          const AreaSelecionada(id: '10', nome: 'Desenvolvimento de Software')
        ],
        areasInteresse: [
          const AreaSelecionada(id: '11', nome: 'Educação')
        ]);
    await deps.usuario.criarProfessor(p);
    final salvo = await deps.usuario.buscarPorId('6') as Professor;
    expect(salvo.areasTecnicas.single.id, '10');
    expect(salvo.siape, '0001234');
    await expectLater(
        deps.usuario.atualizarProfessor(
            id: '6',
            nome: p.nome,
            areasTecnicas: p.areasTecnicas,
            areasInteresse: p.areasTecnicas),
        throwsA(isA<ValidationException>()));
  });

  test('julgamento repetido não aplica dois strikes', () async {
    await entrar('2');
    final id = await deps.denuncia.denunciar(
        demanda: store.demandas['101']!,
        professorId: '2',
        professorNome: 'Professor 2',
        motivo: MotivoDenuncia.outro,
        descricao: 'Descrição do problema encontrado.',
        adminIds: {'3'});
    await entrar('3');
    final d = store.denuncias[id]!;
    await deps.denuncia.julgar(
        denuncia: d,
        procedente: true,
        adminId: '3',
        adminNome: 'Administração',
        parecer: 'Problema confirmado na análise.');
    await expectLater(
        deps.denuncia.julgar(
            denuncia: d,
            procedente: true,
            adminId: '3',
            adminNome: 'Administração',
            parecer: 'Problema confirmado na análise.'),
        throwsA(isA<ConflictException>()));
    expect((store.usuarios['1']! as Demandante).strikes, 1);
  });

  test('instâncias novas reiniciam os dados de demonstração', () async {
    store.demandas.clear();
    final outra = MemoryStore(agora: () => agora);
    expect(outra.demandas.length, StatusDemanda.values.length);
    expect(outra.sessao, isNull);
    await outra.dispose();
  });
}
