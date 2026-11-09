import 'package:flutter/material.dart';

import '../../../core/models/area_selecionada.dart';
import '../../../core/repositories/area_repository.dart';
import '../providers/cadastro_provider.dart';

class NovaAreaDialog extends StatefulWidget {
  final TipoArea tipo;
  final String criadoPorId;
  final CadastroProvider cadastro;

  const NovaAreaDialog({
    super.key,
    required this.tipo,
    required this.criadoPorId,
    required this.cadastro,
  });

  @override
  State<NovaAreaDialog> createState() => _NovaAreaDialogState();
}

class _NovaAreaDialogState extends State<NovaAreaDialog> {
  final _nome = TextEditingController();
  bool _salvando = false;
  String? _erro;

  @override
  void dispose() {
    _nome.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (_salvando) return;
    if (_nome.text.trim().isEmpty) {
      setState(() => _erro = 'Informe o nome da área.');
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    final AreaSelecionada? area = await widget.cadastro.adicionarNovaArea(
      tipo: widget.tipo,
      nomeBruto: _nome.text,
      criadoPorId: widget.criadoPorId,
    );
    if (!mounted) return;
    setState(() {
      _salvando = false;
      _erro = area == null ? widget.cadastro.erro : null;
    });
    if (area != null) Navigator.of(context).pop(area);
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_salvando,
        child: AlertDialog(
          title: Text(widget.tipo == TipoArea.tecnica
              ? 'Nova área técnica'
              : 'Nova área de interesse'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nome,
                autofocus: true,
                enabled: !_salvando,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(hintText: 'Nome da área'),
                onSubmitted: (_) => _salvar(),
              ),
              if (_erro != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_erro!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _salvando ? null : () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: _salvando ? null : _salvar,
              child: Text(_salvando ? 'Salvando…' : 'Adicionar'),
            ),
          ],
        ),
      );
}
