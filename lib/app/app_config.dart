enum AppBackend { firebase, memory, api }

class AppConfig {
  // Identificador público do cliente Web anunciado por /auth/google da API.
  static const defaultGoogleClientId =
      '1077839155998-0d21041askgo67r3tfgdrgmmmalism8m.apps.googleusercontent.com';
  final AppBackend backend;
  final String apiBaseUrl;
  final String googleClientId;
  const AppConfig({
    required this.backend,
    this.apiBaseUrl = 'https://nexus-tech-api.awl3gr.easypanel.host',
    this.googleClientId = defaultGoogleClientId,
  });

  factory AppConfig.fromEnvironment() => AppConfig(
        backend: AppConfig.parse(const String.fromEnvironment('APP_BACKEND',
                defaultValue: 'api'))
            .backend,
        apiBaseUrl: const String.fromEnvironment('API_BASE_URL',
            defaultValue: 'https://nexus-tech-api.awl3gr.easypanel.host'),
        googleClientId: const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID',
            defaultValue: defaultGoogleClientId),
      );

  factory AppConfig.parse(String value) => AppConfig(
          backend: switch (value) {
        'firebase' => AppBackend.firebase,
        'memory' => AppBackend.memory,
        'api' => AppBackend.api,
        _ =>
          throw ArgumentError('APP_BACKEND deve ser firebase, memory ou api.'),
      });
}
