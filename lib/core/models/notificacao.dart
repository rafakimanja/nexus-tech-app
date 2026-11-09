import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Tipos de evento que geram notificação in-app.
///
/// O `name` de cada valor é o que vai persistido em `notificacoes.tipo`, então
/// **renomear um valor quebra notificações já gravadas** — desserialização cai
/// no fallback [TipoNotificacao.generica]. Adicionar valores novos é seguro.
///
/// A rota de destino ao tocar na notificação é derivada aqui ([destino]),
/// mantendo a UI burra: ela só pergunta "para onde vou?".
enum TipoNotificacao {
  /// Professor marcou a demanda para análise (UC09).
  demandaEmAnalise,

  /// Professor assumiu a demanda (UC11). Nasce junto com o chat.
  demandaEmProducao,

  /// Professor devolveu a demanda à prateleira (UC10).
  demandaDevolvida,

  /// Professor entregou (UC12).
  demandaConcluida,

  /// Demandante cancelou uma demanda que estava com um professor (UC16).
  demandaCancelada,
  demandaRecomendada,

  /// Nova mensagem no chat. Só é gerada quando o destinatário ainda não tinha
  /// mensagens não lidas naquele chat — ver `ChatRepository.enviarMensagem`.
  novaMensagem,

  /// Admin recebeu uma denúncia nova (UC-admin).
  denunciaRecebida,

  /// Denúncia analisada — retorno ao professor que denunciou.
  denunciaAnalisada,

  /// Strike aplicado ao demandante após denúncia procedente.
  strikeAplicado,

  /// Terceiro strike: conta banida.
  contaBanida,

  /// Admin desativou o perfil do professor.
  perfilDesativado,

  /// Admin reativou o perfil do professor.
  perfilReativado,

  /// Fallback de desserialização — tipo desconhecido/legado.
  generica;

  static TipoNotificacao from(String? valor) => TipoNotificacao.values
      .firstWhere((t) => t.name == valor, orElse: () => generica);

  IconData get icone => switch (this) {
        TipoNotificacao.demandaRecomendada => Icons.recommend_outlined,
        TipoNotificacao.demandaEmAnalise => Icons.search,
        TipoNotificacao.demandaEmProducao => Icons.engineering_outlined,
        TipoNotificacao.demandaDevolvida => Icons.undo,
        TipoNotificacao.demandaConcluida => Icons.check_circle_outline,
        TipoNotificacao.demandaCancelada => Icons.cancel_outlined,
        TipoNotificacao.novaMensagem => Icons.chat_bubble_outline,
        TipoNotificacao.denunciaRecebida => Icons.flag_outlined,
        TipoNotificacao.denunciaAnalisada => Icons.gavel_outlined,
        TipoNotificacao.strikeAplicado => Icons.warning_amber_outlined,
        TipoNotificacao.contaBanida => Icons.block,
        TipoNotificacao.perfilDesativado => Icons.person_off_outlined,
        TipoNotificacao.perfilReativado => Icons.person_outline,
        TipoNotificacao.generica => Icons.notifications_outlined,
      };

  Color get cor => switch (this) {
        TipoNotificacao.demandaRecomendada => AppColors.primary,
        TipoNotificacao.demandaEmAnalise => Colors.orange.shade700,
        TipoNotificacao.demandaEmProducao => Colors.blue.shade700,
        TipoNotificacao.demandaDevolvida => Colors.amber.shade800,
        TipoNotificacao.demandaConcluida => AppColors.success,
        TipoNotificacao.demandaCancelada => AppColors.error,
        TipoNotificacao.novaMensagem => AppColors.primary,
        TipoNotificacao.denunciaRecebida => Colors.deepOrange.shade700,
        TipoNotificacao.denunciaAnalisada => Colors.indigo.shade600,
        TipoNotificacao.strikeAplicado => Colors.deepOrange.shade800,
        TipoNotificacao.contaBanida => AppColors.error,
        TipoNotificacao.perfilDesativado => AppColors.error,
        TipoNotificacao.perfilReativado => AppColors.success,
        TipoNotificacao.generica => AppColors.textSecondary,
      };

  /// Para onde a notificação leva quando tocada.
  DestinoNotificacao get destino => switch (this) {
        TipoNotificacao.novaMensagem => DestinoNotificacao.chat,
        TipoNotificacao.denunciaRecebida ||
        TipoNotificacao.denunciaAnalisada =>
          DestinoNotificacao.denuncia,
        TipoNotificacao.strikeAplicado ||
        TipoNotificacao.contaBanida ||
        TipoNotificacao.perfilDesativado ||
        TipoNotificacao.perfilReativado =>
          DestinoNotificacao.perfil,
        TipoNotificacao.generica => DestinoNotificacao.nenhum,
        _ => DestinoNotificacao.demanda,
      };
}

/// Destino de navegação derivado do tipo. A tela de notificações traduz isso
/// em rota concreta conforme o papel do usuário logado (a mesma notificação de
/// demanda abre telas diferentes para demandante e professor).
enum DestinoNotificacao { demanda, chat, denuncia, perfil, nenhum }

/// Notificação in-app.
///
/// **Free tier:** este documento é lido em tempo real pelo app e renderizado na
/// central de notificações — funciona 100% no plano Spark. O push (FCM) exige
/// uma Cloud Function que observe esta coleção e marque [enviada]; por isso o
/// campo existe desde já. Ver `docs/CLOUD_FUNCTIONS.md`.
class Notificacao {
  final String id;

  /// Quem recebe. É o campo que a Rule usa para autorizar a leitura.
  final String destinatarioId;

  /// Quem causou o evento. `autorId == request.auth.uid` na criação é o que a
  /// Rule exige para impedir que alguém forje notificações em nome de terceiros.
  final String autorId;
  final String autorNome;

  final TipoNotificacao tipo;
  final String titulo;
  final String corpo;

  // --- referências opcionais para navegação ---
  final String? demandaId;
  final String? chatId;
  final String? denunciaId;

  final bool lida;
  final DateTime? lidaEm;

  /// Consumida pela Cloud Function de despacho FCM (plano Blaze).
  /// Permanece `false` enquanto o push não existir — não afeta o in-app.
  final bool enviada;

  final DateTime criadoEm;

  const Notificacao({
    required this.id,
    required this.destinatarioId,
    required this.autorId,
    required this.autorNome,
    required this.tipo,
    required this.titulo,
    required this.corpo,
    required this.criadoEm,
    this.demandaId,
    this.chatId,
    this.denunciaId,
    this.lida = false,
    this.lidaEm,
    this.enviada = false,
  });

  Map<String, dynamic> toMap() => {
        'destinatarioUid': destinatarioId,
        'autorUid': autorId,
        'autorNome': autorNome,
        'tipo': tipo.name,
        'titulo': titulo,
        'corpo': corpo,
        'demandaId': demandaId,
        'chatId': chatId,
        'denunciaId': denunciaId,
        'lida': lida,
        'lidaEm': lidaEm?.toIso8601String(),
        'enviada': enviada,
        'criadoEm': criadoEm.toIso8601String(),
      };

  factory Notificacao.fromMap(String id, Map<String, dynamic> map) =>
      Notificacao(
        id: id,
        destinatarioId: map['destinatarioUid'] as String,
        autorId: map['autorUid'] as String? ?? '',
        autorNome: map['autorNome'] as String? ?? 'Nexus Tech',
        tipo: TipoNotificacao.from(map['tipo'] as String?),
        titulo: map['titulo'] as String? ?? 'Nexus Tech',
        corpo: map['corpo'] as String? ?? '',
        demandaId: map['demandaId'] as String?,
        chatId: map['chatId'] as String?,
        denunciaId: map['denunciaId'] as String?,
        lida: map['lida'] as bool? ?? false,
        lidaEm: DateTime.tryParse(map['lidaEm'] as String? ?? ''),
        enviada: map['enviada'] as bool? ?? false,
        criadoEm: DateTime.tryParse(map['criadoEm'] as String? ?? '') ??
            DateTime.now(),
      );
}
