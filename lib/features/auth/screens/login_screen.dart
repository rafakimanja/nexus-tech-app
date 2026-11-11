import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../app/app_dependencies.dart';
import '../widgets/api_google_button.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              const Spacer(flex: 3),
              Image.asset(
                'assets/images/logo.png',
                width: 140,
                height: 140,
              ),
              const SizedBox(height: 24),
              Text(
                'Nexus Tech',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const Spacer(flex: 5),
              if (auth.status == AuthStatus.autenticando)
                const CircularProgressIndicator()
              else if (context.read<AppDependencies>().usaApi)
                const ApiGoogleButton()
              else
                ElevatedButton.icon(
                  onPressed: () =>
                      context.read<AuthProvider>().entrarComGoogle(),
                  icon: const Icon(Icons.login),
                  label: const Text('Entrar com Google'),
                ),
              if (auth.erro != null) ...[
                const SizedBox(height: 16),
                Text(
                  auth.erro!,
                  style: const TextStyle(color: AppColors.error),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Text(
                      'Nexus Tech Mobile v1.0',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    Text(
                      '© 2025',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
