import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/exceptions/app_exception.dart';
import '../../../core/models/denuncia.dart';
import '../../../core/repositories/denuncia_repository.dart';
import '../../../core/repositories/api/denuncia_repository.dart';

class ApiDenunciaDetalhesScreen extends StatefulWidget {
  final String id;
  const ApiDenunciaDetalhesScreen({super.key, required this.id});
  @override
  State<ApiDenunciaDetalhesScreen> createState() => _State();
}

class _State extends State<ApiDenunciaDetalhesScreen> {
  late Future<Denuncia> _report = _load();
  Future<Denuncia> _load() =>
      (context.read<DenunciaRepository>() as ApiDenunciaRepository)
          .buscar(widget.id);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Detalhes da denúncia')),
        body: FutureBuilder<Denuncia>(
            future: _report,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                final error = snapshot.error;
                return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(error is AppException
                      ? error.message
                      : 'Não foi possível carregar a denúncia.'),
                  TextButton(
                      onPressed: () => setState(() => _report = _load()),
                      child: const Text('Tentar novamente')),
                ]));
              }
              final d = snapshot.data;
              if (d == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return ListView(padding: const EdgeInsets.all(24), children: [
                Text(d.tituloDemanda,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                Text(d.professorNome),
                Text(d.motivo.label),
                const SizedBox(height: 16),
                Text(d.descricao),
                const SizedBox(height: 24),
                const Text(
                    'Denúncia registrada. O julgamento ainda não está disponível.'),
              ]);
            }),
      );
}
