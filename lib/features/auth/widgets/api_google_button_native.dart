import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/auth_provider.dart';

class ApiGoogleButton extends StatelessWidget {
  const ApiGoogleButton({super.key});
  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
      onPressed: () => context.read<AuthProvider>().entrarComGoogle(),
      icon: const Icon(Icons.login),
      label: const Text('Entrar com Google'));
}
