import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app/app_dependencies.dart';

/// Disponível exclusivamente no ambiente de demonstração.
class DemoLoginOptions extends StatefulWidget {
  const DemoLoginOptions({super.key});
  @override
  State<DemoLoginOptions> createState() => _DemoLoginOptionsState();
}

class _DemoLoginOptionsState extends State<DemoLoginOptions> {
  String _id = '1';
  bool _entrando = false;
  String? _erro;

  @override
  Widget build(BuildContext context) {
    final deps = context.read<AppDependencies>();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      DropdownButtonFormField<String>(
        value: _id,
        decoration: const InputDecoration(labelText: 'Conta de demonstração'),
        items: deps.demoStore!.contas
            .map((c) => DropdownMenuItem(value: c.id, child: Text(c.nome)))
            .toList(),
        onChanged: _entrando ? null : (id) => setState(() => _id = id!),
      ),
      const SizedBox(height: 12),
      ElevatedButton(
          onPressed: _entrando
              ? null
              : () async {
                  setState(() {
                    _entrando = true;
                    _erro = null;
                  });
                  try {
                    await deps.entrarDemonstracao!(_id);
                  } catch (_) {
                    if (mounted)
                      setState(() =>
                          _erro = 'Não foi possível entrar. Tente novamente.');
                  } finally {
                    if (mounted) setState(() => _entrando = false);
                  }
                },
          child: const Text('Entrar na demonstração')),
      if (_erro != null) Text(_erro!),
    ]);
  }
}
