import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_sign_in_web/web_only.dart' as gis;
import '../../../app/app_dependencies.dart';
import '../../../core/services/api_auth_service.dart';

class ApiGoogleButton extends StatefulWidget {
  const ApiGoogleButton({super.key});
  @override
  State<ApiGoogleButton> createState() => _ApiGoogleButtonState();
}

class _ApiGoogleButtonState extends State<ApiGoogleButton> {
  late final Future<void> ready =
      (context.read<AppDependencies>().auth as ApiAuthService)
          .prepareWebSignIn();
  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
      future: ready,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text(
              'Não foi possível iniciar o login Google. Recarregue a página.');
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const CircularProgressIndicator();
        }
        return gis.renderButton();
      });
}
