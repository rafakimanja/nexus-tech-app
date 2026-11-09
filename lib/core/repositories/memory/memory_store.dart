import 'dart:async';

import '../../exceptions/app_exception.dart';
import '../../models/administrador.dart';
import '../../models/anexo.dart';
import '../../models/area.dart';
import '../../models/area_selecionada.dart';
import '../../models/chat.dart';
import '../../models/demanda.dart';
import '../../models/demandante.dart';
import '../../models/denuncia.dart';
import '../../models/enums.dart';
import '../../models/notificacao.dart';
import '../../models/professor.dart';
import '../../models/sessao_usuario.dart';
import '../../models/usuario.dart';

/// Banco efêmero compartilhado por todos os repositórios de demonstração.
/// Cada instância começa do zero; nenhuma chamada externa é feita.
class MemoryStore {
  final DateTime Function() agora;
  final Duration latencia;
  final usuarios = <String, Usuario>{};
  final areas = <String, Area>{};
  final demandas = <String, Demanda>{};
  final chats = <String, Chat>{};
  final mensagens = <String, List<Mensagem>>{};
  final notificacoes = <String, Notificacao>{};
  final denuncias = <String, Denuncia>{};
  final anexos = <String, Map<String, Anexo>>{};
  final devolvidas = <String, int>{};
  final _changes = StreamController<void>.broadcast(sync: true);
  SessaoUsuario? sessao;
  AppException? proximaFalha;
  int _sequencia = 1000;

  MemoryStore(
      {DateTime Function()? agora,
      this.latencia = Duration.zero,
      bool popular = true})
      : agora = agora ?? DateTime.now {
    if (popular) _popular();
  }

  String novoId() => '${++_sequencia}';
  void notificar() => _changes.add(null);
  Future<void> dispose() => _changes.close();

  Future<void> preparar() async {
    if (latencia != Duration.zero) await Future<void>.delayed(latencia);
    final falha = proximaFalha;
    proximaFalha = null;
    if (falha != null) throw falha;
  }

  Stream<T> observar<T>(T Function() ler) async* {
    await preparar();
    yield* Stream<T>.multi((controller) {
      void emitir() {
        try {
          controller.add(ler());
        } catch (e, stack) {
          controller.addError(e, stack);
        }
      }

      final sub =
          _changes.stream.listen((_) => emitir(), onDone: controller.close);
      emitir();
      controller.onCancel = sub.cancel;
    });
  }

  Usuario exigirUsuario({String? id, UserRole? role}) {
    final usuario = usuarios[sessao?.id];
    if (sessao == null) throw const AuthException();
    if (usuario == null ||
        (id != null && usuario.id != id) ||
        (role != null && usuario.role != role)) {
      throw const PermissionException();
    }
    if (usuario is Demandante && usuario.banido ||
        usuario is Professor && !usuario.ativo) {
      throw const ContaBloqueadaException('Esta conta está bloqueada.');
    }
    return usuario;
  }

  void atualizarUsuario(String id, Map<String, dynamic> campos) {
    final anterior = usuarios[id];
    if (anterior == null) throw const NotFoundException('Usuário');
    final dados = {...anterior.toMap(), ...campos};
    usuarios[id] = switch (anterior.role) {
      UserRole.demandante => Demandante.fromMap(dados),
      UserRole.administrador => Administrador.fromMap(dados),
      UserRole.professor => _professor(dados),
    };
  }

  Professor _professor(Map<String, dynamic> dados) {
    final p = Professor.fromMap(dados);
    List<AreaSelecionada> resolver(List<AreaSelecionada> lista) =>
        lista.map((a) {
          final matches = areas.values.where((v) => v.nome == a.nome);
          return matches.length == 1
              ? AreaSelecionada(id: matches.single.id, nome: a.nome)
              : a;
        }).toList();
    return Professor(
        id: p.id,
        email: p.email,
        nome: p.nome,
        criadoEm: p.criadoEm,
        siape: p.siape,
        areasTecnicas: resolver(p.areasTecnicas),
        areasInteresse: resolver(p.areasInteresse),
        ativo: p.ativo,
        fotoUrl: p.fotoUrl,
        desativadoEm: p.desativadoEm,
        motivoDesativacao: p.motivoDesativacao);
  }

  List<SessaoUsuario> get contas => [
        ...usuarios.values.map((u) => SessaoUsuario(
            id: u.id, email: u.email, nome: u.nome, role: u.role)),
        const SessaoUsuario(
            id: '5',
            email: 'novo@example.test',
            nome: 'Novo demandante',
            role: UserRole.demandante),
        const SessaoUsuario(
            id: '6',
            email: 'nova.docente@example.test',
            nome: 'Nova professora',
            role: UserRole.professor),
      ].fold<List<SessaoUsuario>>([], (lista, conta) {
        if (!lista.any((s) => s.id == conta.id)) lista.add(conta);
        return lista;
      });

  void _popular() {
    final data = DateTime.utc(2026, 11, 4, 12);
    areas['10'] = Area(
        id: '10',
        nome: 'Desenvolvimento de Software',
        criadoEm: data,
        criadoPor: '2');
    areas['11'] =
        Area(id: '11', nome: 'Educação', criadoEm: data, criadoPor: '2');
    for (final id in ['1', '7']) {
      usuarios[id] = Demandante(
          id: id,
          email: 'organizacao$id@example.test',
          nome: id == '1' ? 'Associação do Bairro' : 'Demandante bloqueado',
          criadoEm: data,
          telefone: '51999999999',
          tipo: TipoDemandante.ong,
          cpfCnpj: '11222333000181',
          endereco: 'Rua Exemplo, 100',
          banido: id == '7',
          strikes: id == '7' ? 3 : 0);
    }
    for (final id in ['2', '4', '8']) {
      usuarios[id] = Professor(
          id: id,
          email: 'professor$id@example.test',
          nome: id == '8' ? 'Professor inativo' : 'Professor $id',
          criadoEm: data,
          siape: '0012345',
          ativo: id != '8',
          areasTecnicas: [
            const AreaSelecionada(id: '10', nome: 'Desenvolvimento de Software')
          ],
          areasInteresse: [
            const AreaSelecionada(id: '11', nome: 'Educação')
          ]);
    }
    usuarios['3'] = Administrador(
        id: '3',
        email: 'admin@example.test',
        nome: 'Administração',
        criadoEm: data);
    for (final status in StatusDemanda.values) {
      final id = '${101 + status.index}';
      final atribuida = [
        StatusDemanda.emAnalise,
        StatusDemanda.emProducao,
        StatusDemanda.concluida
      ].contains(status);
      demandas[id] = Demanda(
          id: id,
          demandanteId: '1',
          demandanteNome: 'Associação do Bairro',
          demandanteTipo: TipoDemandante.ong,
          titulo: 'Projeto ${status.label}',
          descricao: 'Organizar o atendimento e as atividades da associação.',
          publicoAlvo: 'Moradores do bairro',
          impacto: 'Facilitar o acesso aos serviços.',
          status: status,
          criadoEm: data,
          professorId: atribuida ? '2' : null,
          professorNome: atribuida ? 'Professor 2' : null,
          analiseIniciadaEm: status == StatusDemanda.emAnalise ? agora() : null,
          analiseExpiraEm: status == StatusDemanda.emAnalise
              ? agora().add(const Duration(hours: 24))
              : null,
          concluidaEm: status == StatusDemanda.concluida ? data : null,
          descricaoSolucao: status == StatusDemanda.concluida
              ? 'Solução de demonstração entregue.'
              : null,
          canceladoEm: status == StatusDemanda.cancelada ? data : null,
          motivoCancelamento: status == StatusDemanda.cancelada
              ? 'Prioridades alteradas.'
              : null);
      if (status == StatusDemanda.emProducao ||
          status == StatusDemanda.concluida) {
        final chatId = '9$id';
        chats[chatId] = Chat(
            id: chatId,
            demandaId: id,
            tituloDemanda: demandas[id]!.titulo,
            demandanteId: '1',
            demandanteNome: 'Associação do Bairro',
            professorId: '2',
            professorNome: 'Professor 2',
            participantes: ['1', '2'],
            naoLidas: {'1': 0, '2': 0},
            criadoEm: data,
            ativo: status == StatusDemanda.emProducao,
            ultimaMensagem: 'Conversa de demonstração',
            ultimaMensagemEm: data);
        mensagens[chatId] = [
          Mensagem(
              id: 'm$id',
              autorId: '2',
              autorNome: 'Professor 2',
              texto: 'Conversa de demonstração',
              enviadaEm: data)
        ];
      }
    }
  }
}
