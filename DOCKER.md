# Hospedagem do Flutter Web com Docker

Na VPS, instale o Docker e, na raiz do projeto, construa e inicie a imagem:

```sh
docker build -t nexus-tech-web .
docker run -d --name nexus-tech-web --restart unless-stopped -p 8080:80 nexus-tech-web
```

Acesse `http://IP_DA_VPS:8080`. O contêiner serve o aplicativo na raiz do domínio. Para usar HTTPS e um domínio, configure um proxy reverso com certificado TLS na VPS e encaminhe as requisições para a porta 8080.

Por padrão, o build usa o backend `api` e a URL e o cliente Google definidos em `lib/app/app_config.dart`. Para substituí-los, forneça argumentos durante o build:

```sh
docker build -t nexus-tech-web \
  --build-arg APP_BACKEND=api \
  --build-arg API_BASE_URL=https://sua-api.example.com \
  --build-arg GOOGLE_WEB_CLIENT_ID=seu-cliente-google \
  .
```

Esses valores são incorporados ao código público do aplicativo; não use segredos. Para alterá-los, gere uma nova imagem e recrie o contêiner. A API deve estar acessível pelo navegador e permitir a origem do frontend em sua configuração CORS. Configure também a origem autorizada no cliente Google, caso utilize login com Google.

Para builds reproduzíveis, fixe uma versão compatível da imagem Flutter, por exemplo com `--build-arg FLUTTER_IMAGE=ghcr.io/cirruslabs/flutter:<versao>`. A versão precisa ser compatível com os SDKs exigidos por `pubspec.lock`. Por padrão, é usada a tag `stable`.

Para atualizar após reconstruir a imagem:

```sh
docker stop nexus-tech-web
docker rm nexus-tech-web
docker run -d --name nexus-tech-web --restart unless-stopped -p 8080:80 nexus-tech-web
```
