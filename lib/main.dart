import 'app/app_config.dart';
import 'app/app_dependencies.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'firebase_options.dart';
import 'package:flutter/foundation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  final enablePush = config.backend == AppBackend.api &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android;
  if (config.backend == AppBackend.firebase || enablePush) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  final dependencies = switch (config.backend) {
    AppBackend.firebase => AppDependencies.firebase(),
    AppBackend.api => AppDependencies.api(
        baseUrl: config.apiBaseUrl,
        googleClientId: config.googleClientId,
        enablePush: enablePush),
  };
  debugPrint('Nexus Tech • backend: ${config.backend.name}');
  runApp(App(dependencies: dependencies));
  try {
    await dependencies.push?.listenFirebase();
  } catch (e) {
    debugPrint('Não foi possível iniciar o recebimento de push.');
  }
}
