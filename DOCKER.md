# Executar no navegador com Docker

Com o Docker instalado e em execução (usando contêineres Linux), execute na raiz do projeto:

```sh
docker build -t nexus-tech-web .
docker run --rm --name nexus-tech-web -p 8080:80 nexus-tech-web
```

Abra http://localhost:8080. Para encerrar, pressione Ctrl+C.

O Dockerfile compila o Flutter Web em modo release e usa Nginx para servir os arquivos. Não é necessário instalar Flutter na máquina. A configuração existente em `nginx.conf` permite acessar rotas do aplicativo diretamente.

Por padrão, o aplicativo usa o backend `api` e os valores de `lib/app/app_config.dart`. Para apontar para outra API:

```sh
docker build -t nexus-tech-web --build-arg API_BASE_URL=https://sua-api.example.com .
```

Também são aceitos `APP_BACKEND` e `GOOGLE_WEB_CLIENT_ID` como argumentos de build. Esses valores são incorporados ao aplicativo durante a compilação; para alterá-los, reconstrua a imagem e recrie o contêiner. Não coloque segredos nesses argumentos, pois o código web é público.

A API precisa estar acessível pelo navegador e permitir a origem `http://localhost:8080` em sua configuração CORS. Se utilizar login com Google, configure essa origem no cliente OAuth. O contêiner serve apenas o frontend; a API deve estar em execução separadamente.

A imagem Flutter usa a tag `stable`. Para fixar o SDK, passe `--build-arg FLUTTER_IMAGE=ghcr.io/cirruslabs/flutter:<versao>`, escolhendo uma versão compatível com `pubspec.lock` (Dart >= 3.11 e Flutter >= 3.38). A tag móvel e o comando `flutter pub get` podem atualizar a resolução das dependências dentro da imagem.
