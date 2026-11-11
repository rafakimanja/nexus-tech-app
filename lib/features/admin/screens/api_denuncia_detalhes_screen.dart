import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/exceptions/app_exception.dart';
import '../../../core/models/demanda.dart';
import '../../../core/models/denuncia.dart';
import '../../../core/models/enums.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/repositories/demanda_repository.dart';
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
  bool _processando = false;
  bool _enviando = false;
  ApiDenunciaRepository get _repository =>
      context.read<DenunciaRepository>() as ApiDenunciaRepository;
  Future<Denuncia> _load() => _repository.buscar(widget.id);

  Future<void> _julgar(Denuncia denuncia, bool procedente) async {
    final admin = context.read<AuthProvider>().sessao;
    if (_processando || admin?.role != UserRole.administrador) return;
    setState(() => _processando = true);
    try {
      final justificativa = await showDialog<String>(
        context: context,
        builder: (_) => _DialogJulgamento(procedente: procedente),
      );
      if (justificativa == null ||
          !mounted ||
          context.read<AuthProvider>().sessao?.id != admin!.id) {
        return;
      }
      setState(() => _enviando = true);
      final resultado = await _repository.julgar(
        denuncia: denuncia,
        procedente: procedente,
        adminId: admin.id,
        adminNome: admin.nome,
        parecer: justificativa,
      );
      if (!mounted) return;
      setState(() {
        _report = Future.value(resultado.denunciaAtualizada!);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
        !resultado.procedente
            ? 'Denúncia julgada improcedente. A demanda e as advertências foram mantidas.'
            : resultado.strikeAplicado
                ? 'Denúncia procedente. Demanda cancelada e uma advertência aplicada.'
                : 'Denúncia procedente. Demanda cancelada, sem nova advertência.',
      )));
    } on ConflictException catch (e) {
      if (!mounted) return;
      setState(() {
        _report = _load();
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
        e is AppException ? e.message : 'Não foi possível registrar a decisão.',
      )));
    } finally {
      if (mounted) {
        setState(() {
          _processando = false;
          _enviando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin =
        context.watch<AuthProvider>().sessao?.role == UserRole.administrador;
    return Scaffold(
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
                onPressed: () => setState(() {
                  _report = _load();
                }),
                child: const Text('Tentar novamente'),
              ),
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
            Text('Professor: ${d.professorNome}'),
            Text('Demandante: ${d.demandanteNome}'),
            Text(d.motivo.label),
            const SizedBox(height: 16),
            Text(d.descricao),
            const SizedBox(height: 24),
            Text('Situação: ${d.status.label}'),
            if (d.analisadaEm != null)
              Text('Julgada em: ${_data(d.analisadaEm!)}'),
            if (d.parecerAdmin != null) ...[
              const SizedBox(height: 16),
              Text('Parecer da administração',
                  style: Theme.of(context).textTheme.titleMedium),
              Text(d.parecerAdmin!),
              if (admin && d.status == StatusDenuncia.procedente)
                Text(d.strikeAplicado
                    ? 'Uma advertência aplicada nesta decisão.'
                    : 'Nenhuma nova advertência aplicada nesta decisão.'),
            ],
            if (admin) ...[
              const SizedBox(height: 24),
              _DemandaDenunciada(id: d.demandaId),
            ],
            if (admin && d.pendente) ...[
              const SizedBox(height: 24),
              const Text(
                  'A decisão é definitiva nesta versão. Revise a demanda e informe a justificativa.'),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 12, children: [
                OutlinedButton(
                  onPressed: _processando ? null : () => _julgar(d, false),
                  child: const Text('Julgar improcedente'),
                ),
                FilledButton(
                  onPressed: _processando ? null : () => _julgar(d, true),
                  child: const Text('Julgar procedente'),
                ),
              ]),
              if (_enviando) const LinearProgressIndicator(),
            ],
          ]);
        },
      ),
    );
  }

  String _data(DateTime value) {
    final d = value.toLocal();
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(d.day)}/${dois(d.month)}/${d.year} às ${dois(d.hour)}:${dois(d.minute)}';
  }
}

class _DialogJulgamento extends StatefulWidget {
  final bool procedente;
  const _DialogJulgamento({required this.procedente});
  @override
  State<_DialogJulgamento> createState() => _DialogJulgamentoState();
}

class _DialogJulgamentoState extends State<_DialogJulgamento> {
  final _form = GlobalKey<FormState>();
  final _texto = TextEditingController();
  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.procedente
            ? 'Confirmar procedência'
            : 'Confirmar improcedência'),
        content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
                child: Form(
              key: _form,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.procedente
                        ? 'A demanda será cancelada, mesmo se já estiver concluída. Será aplicada uma advertência se esta demanda ainda não tiver sido penalizada. Com três advertências, a conta é bloqueada. A decisão não poderá ser revertida.'
                        : 'A denúncia será encerrada sem alterar a demanda ou aplicar advertências. A decisão não poderá ser revertida.'),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _texto,
                      minLines: 3,
                      maxLines: 8,
                      decoration: const InputDecoration(
                          labelText: 'Justificativa',
                          helperText: 'Explique o motivo da decisão.'),
                      validator: (value) {
                        final texto = (value ?? '').trim();
                        if (texto.isEmpty) return 'Informe a justificativa.';
                        if (utf8.encode(texto).length > 5000) {
                          return 'A justificativa ultrapassa 5000 bytes.';
                        }
                        return null;
                      },
                    ),
                  ]),
            ))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () {
                if (_form.currentState!.validate()) {
                  Navigator.pop(context, _texto.text.trim());
                }
              },
              child: const Text('Confirmar julgamento')),
        ],
      );
}

class _DemandaDenunciada extends StatefulWidget {
  final String id;
  const _DemandaDenunciada({required this.id});
  @override
  State<_DemandaDenunciada> createState() => _DemandaDenunciadaState();
}

class _DemandaDenunciadaState extends State<_DemandaDenunciada> {
  late final _stream = context.read<DemandaRepository>().observar(widget.id);
  @override
  Widget build(BuildContext context) => StreamBuilder<Demanda?>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Text(
                'Não foi possível consultar o conteúdo da demanda.');
          }
          if (!snapshot.hasData) {
            return snapshot.connectionState == ConnectionState.waiting
                ? const LinearProgressIndicator()
                : const Text('Demanda indisponível.');
          }
          final d = snapshot.data!;
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Demanda denunciada',
                    style: Theme.of(context).textTheme.titleMedium),
                Text('Estado atual: ${d.status.label}'),
                const SizedBox(height: 8),
                Text(d.descricao),
                const SizedBox(height: 8),
                Text('Público-alvo: ${d.publicoAlvo}'),
                Text('Impacto: ${d.impacto}'),
              ]);
        },
      );
}
