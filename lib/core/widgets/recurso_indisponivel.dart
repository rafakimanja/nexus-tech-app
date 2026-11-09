import 'package:flutter/material.dart';

class RecursoIndisponivel extends StatelessWidget {
  final String nome;
  const RecursoIndisponivel(this.nome, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text('$nome ainda não está disponível nesta versão.',
            textAlign: TextAlign.center),
      );
}
