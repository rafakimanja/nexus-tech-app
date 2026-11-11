import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/exceptions/app_exception.dart';
import '../../../core/models/demanda.dart';
import '../../../core/models/demandante.dart';
import '../../../core/models/professor.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/repositories/denuncia_repository.dart';
import '../../../core/models/denuncia.dart';
import '../../notificacoes/widgets/sino_notificacoes.dart';
import '../../notificacoes/providers/notificacoes_provider.dart';
import 'api_denuncia_detalhes_screen.dart';

/// Consultas administrativas disponíveis no contrato HTTP atual.
class ApiAdminScreen extends StatefulWidget {
  const ApiAdminScreen({super.key});
  @override
  State<ApiAdminScreen> createState() => _ApiAdminScreenState();
}

class _ApiAdminScreenState extends State<ApiAdminScreen> {
  late final repo = context.read<AdminRepository>();
  late final demands = repo.observarTodasDemandas();
  late final teachers = repo.observarProfessores();
  late final applicants = repo.observarDemandantes();
  late final reports = context.read<DenunciaRepository>().observarTodas();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final id = context.read<AuthProvider>().usuario?.id;
      if (id != null) context.read<NotificacoesProvider>().observar(id);
    });
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
              title: const Text('Administração'),
              actions: [
                const SinoNotificacoes(),
                IconButton(
                    tooltip: 'Sair',
                    icon: const Icon(Icons.logout),
                    onPressed: () => context.read<AuthProvider>().sair()),
              ],
              bottom: const TabBar(tabs: [
                Tab(text: 'Demandas'),
                Tab(text: 'Professores'),
                Tab(text: 'Demandantes'),
                Tab(text: 'Denúncias')
              ])),
          body: Column(children: [
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    'Consulte demandas, professores, demandantes e denúncias.')),
            Expanded(
                child: TabBarView(children: [
              _list<Demanda>(
                  demands,
                  (d) => ListTile(
                      title: Text(d.titulo),
                      subtitle:
                          Text('${d.status.label} • ${d.demandanteNome}'))),
              _list<Professor>(
                  teachers,
                  (p) => ListTile(
                      title: Text(p.nome),
                      subtitle: Text(
                          '${p.email}\nSIAPE ${p.siape} • ${p.ativo ? "Ativo" : "Desativado"}'),
                      isThreeLine: true)),
              _list<Demandante>(
                  applicants,
                  (d) => ListTile(
                      title: Text(d.nome),
                      subtitle: Text(
                          '${d.email}\n${d.tipo.label} • ${d.banido ? "Suspenso" : "Ativo"}'),
                      isThreeLine: true)),
              _list<Denuncia>(
                  reports,
                  (d) => ListTile(
                        title: Text(d.tituloDemanda),
                        subtitle: Text(d.motivo.label),
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) =>
                                    ApiDenunciaDetalhesScreen(id: d.id))),
                      )),
            ])),
          ]),
        ),
      );
  Widget _list<T>(Stream<List<T>> stream, Widget Function(T) tile) =>
      _AdminList<T>(stream: stream, tile: tile);
}

// TabBarView descarta abas fora da viewport. Preserva a assinatura e os dados
// para não tentar ouvir novamente um stream de assinatura única ao retornar.
class _AdminList<T> extends StatefulWidget {
  final Stream<List<T>> stream;
  final Widget Function(T) tile;
  const _AdminList({required this.stream, required this.tile});

  @override
  State<_AdminList<T>> createState() => _AdminListState<T>();
}

class _AdminListState<T> extends State<_AdminList<T>>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return StreamBuilder<List<T>>(
        stream: widget.stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final error = snapshot.error;
            return Center(
                child: Text(error is AppException
                    ? error.message
                    : 'Não foi possível consultar os dados.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final values = snapshot.data!;
          if (values.isEmpty) {
            return const Center(child: Text('Nenhum registro encontrado.'));
          }
          return ListView.builder(
              itemCount: values.length,
              itemBuilder: (_, i) => widget.tile(values[i]));
        });
  }
}
