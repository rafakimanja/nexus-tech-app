# Integração HTTP

O backend padrão do app é `api`, apontando para
`https://nexus-tech-api.awl3gr.easypanel.host`. No Android inicializa Firebase apenas para Messaging; não
usa dados do `MemoryStore`. A seleção é feita em `lib/app/app_config.dart` e
a composição em `lib/app/app_dependencies.dart`.

## Executar

Na IDE, escolha uma das configurações em `.vscode/launch.json`:
**Nexus Tech • API**, **API Web**, **Demonstração** ou **Firebase**.
O console informa `Nexus Tech • backend: api` ao iniciar.

```sh
flutter run --dart-define=APP_BACKEND=api
flutter run -d chrome --web-hostname=localhost --web-port=5173 --dart-define=APP_BACKEND=api
flutter run --dart-define=APP_BACKEND=memory
flutter run --dart-define=APP_BACKEND=firebase
```

Neste workspace o SDK também está em `.tools/flutter/bin/flutter.bat`.
Pare a execução e inicie novamente ao trocar os defines; hot reload não
troca o backend. O modo memória mantém seu banner de demonstração.

Configurações opcionais:

| Define | Uso |
| --- | --- |
| `API_BASE_URL` | Endereço de outra instância, sem prefixo `/v2` |
| `GOOGLE_WEB_CLIENT_ID` | Cliente OAuth Web aceito pela API; é público, não é um segredo |

## Login e sessão

O ID token Google é enviado a `POST /login/v2` em `{"idToken":"..."}`.
As demais requisições usam **o JWT da API** em `Authorization: Bearer ...`.
ID e papel vêm da API (`admin` é convertido para `administrador`); o app não
reclassifica usuários por e-mail. `/me` decide se é necessário concluir o
cadastro, e os perfis completos vêm de `/teachers/:id` ou `/applicants/:id`.

O cliente OAuth padrão foi obtido do redirecionamento público `/auth/google`
da instância informada. O Google precisa autorizar as plataformas usadas:

- Web: cadastrar `http://localhost:5173` nas origens JavaScript autorizadas
  desse cliente OAuth. Usamos o botão oficial GIS para obter o ID token;
  `GoogleSignIn.signIn()` na Web não fornece esse token.
- Android: cadastrar um cliente OAuth Android com o package name e SHA-1
  da assinatura do build no mesmo projeto Google. O `google-services.json`
  presente no projeto tem `oauth_client` vazio; a configuração de assinatura
  ainda precisa ser confirmada no console Google.
- iOS/macOS: configurar o cliente e o URL scheme Google próprios da plataforma.
  `GOOGLE_WEB_CLIENT_ID` é a audiência do servidor e não substitui esses IDs.
- Windows/Linux: o plugin Google Sign-In usado pelo projeto não implementa
  login nativo nessas plataformas. Para testar no computador, use Chrome.

A sessão da API vale até `expires_at` (12 horas no contrato atual), e um `401`
encerra a sessão local. Não há refresh no servidor. Nesta primeira integração,
o JWT fica **somente na memória do processo**: reiniciar o app ou recarregar a
página exige entrar novamente. Nenhum token é escrito em arquivo ou log.

## Recursos conectados

- Login Google, consulta de sessão, cadastro e edição de demandante/professor.
- Catálogo de áreas e criação; IDs das associações são preservados. A mesma
  área não pode ocupar simultaneamente os dois tipos no contrato atual.
- Criação, edição, consulta e filtros de demandas; prateleira e minhas demandas.
- Análise, devolução, atribuição, conclusão com descrição e cancelamento.
- Painel administrativo original: visão geral de demandas, listas com busca,
  fichas de professores e demandantes e métricas derivadas das demandas.

Datas e enums seguem os DTOs do backend. Somente campos editáveis são enviados;
autoria, permissões, transições e expiração da análise são determinadas pela API.
As listas são consultadas a cada 15 segundos enquanto observadas e atualizadas
após mutações do app. Falhas de leitura não encerram o polling; escritas não são
repetidas automaticamente. Respostas atrasadas de outra sessão são descartadas.

## Limites do backend atual

Chat, upload de anexos/fotos, julgamento de denúncias, moderação, métricas
completas e republicação vinculada não têm endpoints equivalentes. No modo API,
a interface oculta ou informa a indisponibilidade desses recursos. Os contratos
correspondentes também rejeitam operações explicitamente; não há fallback para
Firebase ou mocks. A conclusão de demanda funciona com descrição, sem anexos.
As recomendações recebidas aparecem na central de notificações e abrem a demanda.

## Notificações e denúncias (09/11/2026)

- A central e o sino usam `GET /notifications`, com polling de 15 segundos.
  Todas as páginas são consumidas para contar também as não lidas antigas.
  Leitura individual/coletiva usa os PATCHs documentados; o app não cria avisos.
- No Android, `firebase_messaging` pede permissão depois do login, registra o
  token em `PUT /notifications/devices` e acompanha sua renovação. Registro
  malsucedido é tentado novamente a cada 30 segundos sem impedir a central HTTP.
- Logout aguarda registros em andamento e remove o dispositivo antes de apagar
  o JWT. Se a remoção falhar, invalida o token no FCM. Expiração da sessão também
  tenta invalidá-lo. Falhas simultâneas de rede e FCM precisam de validação real.
- Em primeiro plano, push atualiza as consultas. Ao tocar num push, inclusive
  com o app fechado, o app aguarda login, confirma o aviso no histórico da sessão
  e abre o recurso, cuja tela consulta a API. Não há push Web/iOS nesta integração.
- Professores enviam `POST /reports` sem consultar administradores. Duplicação
  (`409`) informa que a demanda já foi denunciada. O painel lista todas as páginas
  de `/reports` e consulta `/reports/:id` ao abrir; não oferece julgamento/strikes.

Para validar a entrega Android, a API precisa estar publicada com FCM ativo e usar
o mesmo projeto Firebase do app (`nexus-tech-2025` na configuração atual). Validar
em aparelho: permissão, login, evento de demanda/recomendação/denúncia, primeiro
plano, segundo plano, abertura a frio, renovação de token e troca de conta.
A credencial de serviço permanece somente no servidor. Nenhuma alteração de
infraestrutura ou envio real foi realizado nesta integração.

Referência: `../nexus-tech-api/docs/notificacoes.md` e
[recebimento FCM no Flutter](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages).

O admin usa `AdminHomeScreen` em todos os backends; o roteador não direciona
mais para `ApiAdminScreen`. As consultas usam `GET /demands/`, `GET /teachers/`
e `GET /applicants/`. Contagens, taxa de conclusão e tempos médios são calculados
a partir dos vínculos e datas das demandas retornadas pela API. O histórico de
devoluções não é retornado e aparece como indisponível, nunca como zero confirmado.
Advertências e ativação/desativação permanecem sinalizadas nas telas
originais como indisponíveis no servidor; os PUTs de perfil atuais são exclusivos
do proprietário e não substituem endpoints administrativos de moderação.
Falhas de consulta aparecem separadamente por lista e se recuperam no polling.

A API consultada permite CORS em `http://localhost:5173`; outras origens exigem
configuração no servidor. O catálogo de áreas não garante unicidade sob criação
concorrente. Contas/dados do Firebase não são migrados automaticamente. Uma conta
existente na API sem vínculo Google pode retornar `409` no login e precisa de
vinculação no backend.

## Verificação

```sh
flutter test
flutter analyze --no-fatal-infos
flutter build web --dart-define=APP_BACKEND=api
```

Os testes HTTP usam transporte controlado para verificar payloads, IDs, papel,
erros, logout, cancelamento, polling e isolamento de sessões, sem criar dados no
servidor publicado. O teste de tela cobre login, listagem, atualização e novo login.
A checagem pública confirmou `/` e `/health` com `200`, `/me` sem token com `401`
e preflight CORS com `204`. O fluxo Google com uma conta real e a execução de
escritas autenticadas no servidor ainda precisam ser validados pelo usuário.

Contratos de referência: código e documentação do repositório vizinho
`D:/nexus-tech/nexus-tech-api`, especialmente `docs/rotas.md` e os DTOs em
`internal/domain`. A revisão publicada deve corresponder a esses contratos.

### Correções de admin e criação de áreas (07/11/2026)

- Reproduzido em teste o erro `Stream has already been listened to` ao revisitar
  abas administrativas. As listas agora preservam seu estado e assinatura durante
  a navegação, com cancelamento ao sair da tela.
- Cadastro e edição de professor usam o mesmo diálogo de criação de área, que
  aguarda a resposta, impede envio repetido e mantém nome e mensagem em caso de erro.
  O provider preserva os erros de permissão, rede e servidor.
- `POST /areas/` existe no backend local e retorna `areaID`; o app usa essa
  confirmação diretamente, sem depender de um GET adicional para concluir a ação.
  A falha original de criação no servidor publicado não foi reproduzida com uma
  sessão real; os testes usam transporte HTTP controlado conforme o contrato local.
