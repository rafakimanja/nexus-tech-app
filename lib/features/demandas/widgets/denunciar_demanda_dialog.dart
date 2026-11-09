import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app/app_dependencies.dart';

import '../../../app/theme.dart';
import '../../../core/models/denuncia.dart';
import '../../../core/widgets/texto_botao.dart';

/// O que o professor preencheu ao denunciar.
typedef DadosDenuncia = ({MotivoDenuncia motivo, String descricao});

/// Coleta motivo + justificativa de uma denúncia de demanda.
///
/// Motivo é lista fechada (alimenta as métricas do painel admin) e a
/// justificativa é obrigatória: o admin julga com base nela, e uma denúncia
/// sem texto é impossível de avaliar de forma justa.
///
/// Retorna [DadosDenuncia] ou `null` se o professor desistiu.
class DenunciarDemandaDialog extends StatefulWidget {
  final String tituloDemanda;

  const DenunciarDemandaDialog({super.key, required this.tituloDemanda});

  static Future<DadosDenuncia?> mostrar(
    BuildContext context, {
    required String tituloDemanda,
  }) {
    return showDialog<DadosDenuncia>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DenunciarDemandaDialog(tituloDemanda: tituloDemanda),
    );
  }

  @override
  State<DenunciarDemandaDialog> createState() => _DenunciarDemandaDialogState();
}

class _DenunciarDemandaDialogState extends State<DenunciarDemandaDialog> {
  final _controller = TextEditingController();
  MotivoDenuncia _motivo = MotivoDenuncia.conteudoOfensivo;
  String? _erro;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirmar() {
    final descricao = _controller.text.trim();
    if (descricao.length < 10) {
      setState(
          () => _erro = 'Descreva o problema com pelo menos 10 caracteres');
      return;
    }
    Navigator.of(context).pop((motivo: _motivo, descricao: descricao));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.flag_outlined, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Denunciar demanda',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '"${widget.tituloDemanda}"',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              const Text(
                'Motivo',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<MotivoDenuncia>(
                initialValue: _motivo,
                isExpanded: true,
                decoration: const InputDecoration(
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
                items: [
                  for (final m in MotivoDenuncia.values)
                    DropdownMenuItem(
                      value: m,
                      child: Text(m.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (m) {
                  if (m != null) setState(() => _motivo = m);
                },
              ),
              const SizedBox(height: 16),
              const Text(
                'O que está errado?',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                maxLines: 4,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Explique para a administração o que motivou '
                      'esta denúncia...',
                  errorText: _erro,
                ),
                onChanged: (_) {
                  if (_erro != null) setState(() => _erro = null);
                },
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 18, color: Colors.amber.shade900),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.read<AppDependencies>().usaApi
                            ? 'A denúncia será encaminhada à administração.'
                            : 'Denúncias procedentes geram advertência ao '
                                'demandante. Três advertências suspendem a conta.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey.shade700,
                        side: BorderSide(color: Colors.grey.shade400),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const TextoBotao('Voltar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _confirmar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const TextoBotao('Denunciar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
