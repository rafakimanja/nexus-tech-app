import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/exceptions/app_exception.dart';
import '../../notificacoes/widgets/sino_notificacoes.dart';

String mensagemErroAdmin(Object? erro) => erro is AppException
    ? erro.message
    : 'Não foi possível carregar os dados. Tente novamente.';

class AvisoAdmin extends StatelessWidget {
  final String mensagem;
  const AvisoAdmin(this.mensagem, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(mensagem, textAlign: TextAlign.center),
      );
}

/// Mantém assinaturas de seções que saem da viewport de uma ListView.
class SecaoPersistenteAdmin extends StatefulWidget {
  final Widget child;
  const SecaoPersistenteAdmin({super.key, required this.child});

  @override
  State<SecaoPersistenteAdmin> createState() => _SecaoPersistenteAdminState();
}

class _SecaoPersistenteAdminState extends State<SecaoPersistenteAdmin>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Cabeçalho padrão das abas do painel: logo, título da seção e o sino.
/// Repetido nas quatro abas para que o admin nunca perca a referência de onde
/// está nem o acesso às notificações.
class AdminHeader extends StatelessWidget {
  final String titulo;
  final String? subtitulo;
  final List<Widget> acoes;

  const AdminHeader({
    super.key,
    required this.titulo,
    this.subtitulo,
    this.acoes = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset('assets/images/logo.png', width: 44, height: 44),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Nexus Tech — Admin',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
              ...acoes,
              const SinoNotificacoes(),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            titulo,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
              height: 1.1,
            ),
          ),
          if (subtitulo != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitulo!,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }
}

/// Cartão de indicador (valor grande + rótulo).
///
/// Usa `FittedBox` no número pelo mesmo motivo de `EstatisticasDemandas`:
/// valores de 3+ dígitos não podem estourar a largura em telas estreitas.
class CartaoMetrica extends StatelessWidget {
  final String valor;
  final String label;
  final IconData icone;
  final Color cor;

  const CartaoMetrica({
    super.key,
    required this.valor,
    required this.label,
    required this.icone,
    required this.cor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha: 0.25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 20, color: cor),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              valor,
              maxLines: 1,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: cor,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              height: 1.3,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Grade responsiva de [CartaoMetrica]. Quebra em [colunas] por linha e
/// mantém altura uniforme dentro de cada linha.
class GradeMetricas extends StatelessWidget {
  final List<Widget> cartoes;
  final int colunas;

  const GradeMetricas({
    super.key,
    required this.cartoes,
    this.colunas = 3,
  });

  @override
  Widget build(BuildContext context) {
    final linhas = <Widget>[];

    for (var i = 0; i < cartoes.length; i += colunas) {
      final fatia = cartoes.skip(i).take(colunas).toList();
      linhas.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < colunas; j++) ...[
                if (j > 0) const SizedBox(width: 10),
                // Slots vazios na última linha mantêm o alinhamento da grade
                // em vez de esticar o último cartão.
                Expanded(
                  child: j < fatia.length ? fatia[j] : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
      if (i + colunas < cartoes.length) {
        linhas.add(const SizedBox(height: 10));
      }
    }

    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: linhas);
  }
}

/// Etiqueta compacta de estado (ativo/inativo, banido, nº de strikes).
class Etiqueta extends StatelessWidget {
  final String texto;
  final Color cor;
  final IconData? icone;

  const Etiqueta({
    super.key,
    required this.texto,
    required this.cor,
    this.icone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cor.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icone != null) ...[
            Icon(icone, size: 12, color: cor),
            const SizedBox(width: 4),
          ],
          Text(
            texto,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: cor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Linha "rótulo: valor" das telas de detalhe do painel.
class LinhaDetalhe extends StatelessWidget {
  final String rotulo;
  final String valor;

  const LinhaDetalhe({super.key, required this.rotulo, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              rotulo,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Coleta um texto obrigatório (motivo/parecer) antes de uma ação sensível.
///
/// Toda ação administrativa que afeta a conta de alguém passa por aqui: a
/// justificativa vai para a auditoria e para a notificação da pessoa afetada,
/// que tem direito de saber o porquê.
class DialogMotivo extends StatefulWidget {
  final String titulo;
  final String descricao;
  final String rotuloConfirmar;
  final String hint;
  final Color corConfirmar;
  final int minimoCaracteres;

  const DialogMotivo({
    super.key,
    required this.titulo,
    required this.descricao,
    required this.rotuloConfirmar,
    required this.hint,
    this.corConfirmar = AppColors.primary,
    this.minimoCaracteres = 5,
  });

  static Future<String?> mostrar(
    BuildContext context, {
    required String titulo,
    required String descricao,
    required String rotuloConfirmar,
    required String hint,
    Color corConfirmar = AppColors.primary,
    int minimoCaracteres = 5,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DialogMotivo(
        titulo: titulo,
        descricao: descricao,
        rotuloConfirmar: rotuloConfirmar,
        hint: hint,
        corConfirmar: corConfirmar,
        minimoCaracteres: minimoCaracteres,
      ),
    );
  }

  @override
  State<DialogMotivo> createState() => _DialogMotivoState();
}

class _DialogMotivoState extends State<DialogMotivo> {
  final _controller = TextEditingController();
  String? _erro;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirmar() {
    final texto = _controller.text.trim();
    if (texto.length < widget.minimoCaracteres) {
      setState(() =>
          _erro = 'Informe pelo menos ${widget.minimoCaracteres} caracteres');
      return;
    }
    Navigator.of(context).pop(texto);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        widget.titulo,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.descricao,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 4,
            maxLength: 400,
            textCapitalization: TextCapitalization.sentences,
            decoration:
                InputDecoration(hintText: widget.hint, errorText: _erro),
            onChanged: (_) {
              if (_erro != null) setState(() => _erro = null);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _confirmar,
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.corConfirmar,
            minimumSize: const Size(120, 44),
          ),
          child: Text(widget.rotuloConfirmar),
        ),
      ],
    );
  }
}
