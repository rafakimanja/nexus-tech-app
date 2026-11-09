import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../app/app_dependencies.dart';
import '../../../core/widgets/recurso_indisponivel.dart';
import '../../../core/models/anexo.dart';
import '../../../core/models/demanda.dart';
import '../../../core/repositories/anexo_repository.dart';
import '../../auth/widgets/form_label.dart';
import '../providers/acao_demanda_provider.dart';
import '../widgets/demanda_detalhe_widgets.dart';

/// UC12 — Interface de entrega. O professor descreve a solução e, opcionalmente,
/// anexa os arquivos do entregável (PDF, DOCX, JPG, PNG · até 10MB). Confirmar
/// envia os anexos e conclui a demanda (transição atômica no repositório).
class EntregaDemandaScreen extends StatefulWidget {
  final Demanda demanda;
  final String professorId;

  const EntregaDemandaScreen({
    super.key,
    required this.demanda,
    required this.professorId,
  });

  @override
  State<EntregaDemandaScreen> createState() => _EntregaDemandaScreenState();
}

class _EntregaDemandaScreenState extends State<EntregaDemandaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descricao = TextEditingController();

  /// Anexos selecionados e ainda não enviados. É mutável e passado ao
  /// provider: cada anexo enviado com sucesso é removido daqui, evitando
  /// duplicação caso a conclusão precise ser repetida após uma falha de rede.
  final List<AnexoPendente> _anexos = [];

  static const _maxDescricao = 1000;

  @override
  void dispose() {
    _descricao.dispose();
    super.dispose();
  }

  Future<void> _selecionarArquivo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: AnexoRepository.formatosPermitidos.toList(),
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;

    final pendente = AnexoPendente(
      nomeLocal: file.name,
      caminhoLocal: file.path!,
      tamanhoBytes: file.size,
      formato: (file.extension ?? '').toLowerCase(),
    );

    final erro = AnexoRepository.validar(pendente);
    if (erro != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(erro), backgroundColor: AppColors.error),
        );
      }
      return;
    }

    final duplicado = _anexos.any((a) =>
        a.nomeLocal == pendente.nomeLocal &&
        a.tamanhoBytes == pendente.tamanhoBytes);
    if (duplicado) return;

    setState(() => _anexos.add(pendente));
  }

  Future<void> _confirmar() async {
    if (!_formKey.currentState!.validate()) return;

    final acao = context.read<AcaoDemandaProvider>();
    final ok = await acao.concluir(
      demandaId: widget.demanda.id,
      professorId: widget.professorId,
      descricaoSolucao: _descricao.text,
      anexos: _anexos,
    );

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      // Anexos já enviados foram removidos de _anexos pelo provider; reflete na UI.
      setState(() {});
      if (acao.erro != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(acao.erro!), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final processando =
        context.watch<AcaoDemandaProvider>().processando(widget.demanda.id);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const DetalheHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Entrega da Demanda',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.demanda.titulo,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const FormLabel('Descrição da solução *'),
                      TextFormField(
                        controller: _descricao,
                        maxLines: 6,
                        maxLength: _maxDescricao,
                        textCapitalization: TextCapitalization.sentences,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(_maxDescricao),
                        ],
                        decoration: const InputDecoration(
                          hintText:
                              'Descreva o que foi entregue, como utilizar e '
                              'quaisquer observações relevantes para o demandante.',
                          counterText: '',
                        ),
                        validator: (v) {
                          final t = v?.trim() ?? '';
                          if (t.isEmpty)
                            return 'A descrição da entrega é obrigatória';
                          if (t.length < 20) {
                            return 'Descreva a entrega com pelo menos 20 caracteres';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      if (context.read<AppDependencies>().usaApi)
                        const RecursoIndisponivel('Arquivos da entrega')
                      else ...[
                        const Text(
                          'Arquivos da entrega',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Opcional. PDF, DOCX, JPG ou PNG • máx 10 MB',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: processando ? null : _selecionarArquivo,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.4),
                                width: 1.5,
                              ),
                            ),
                            child: const Column(
                              children: [
                                Icon(Icons.cloud_upload_outlined,
                                    size: 32, color: AppColors.primary),
                                SizedBox(height: 8),
                                Text(
                                  'Anexar arquivo',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ..._anexos.asMap().entries.map(
                              (e) => _AnexoPendenteTile(
                                anexo: e.value,
                                onRemover: processando
                                    ? null
                                    : () =>
                                        setState(() => _anexos.removeAt(e.key)),
                              ),
                            ),
                      ],
                      const SizedBox(height: 8),
                      BlocoInfo(
                        cor: AppColors.textSecondary,
                        icone: Icons.info_outline,
                        titulo: 'Ao concluir',
                        conteudo: context.read<AppDependencies>().usaApi
                            ? 'A solução fica disponível ao demandante e a demanda sai da prateleira.'
                            : 'O demandante é notificado, a avaliação é liberada '
                                'e a demanda sai da prateleira pública.',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _barraInferior(processando),
          ],
        ),
      ),
    );
  }

  Widget _barraInferior(bool processando) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: processando ? null : () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: BorderSide(color: Colors.grey.shade300),
                minimumSize: const Size.fromHeight(52),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              // FittedBox evita que "Cancelar" quebre linha em telas estreitas.
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Cancelar', maxLines: 1, softWrap: false),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: processando ? null : _confirmar,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: processando
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Confirmar entrega',
                          maxLines: 1, softWrap: false),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnexoPendenteTile extends StatelessWidget {
  final AnexoPendente anexo;
  final VoidCallback? onRemover;

  const _AnexoPendenteTile({required this.anexo, required this.onRemover});

  IconData get _icone => switch (anexo.formato.toLowerCase()) {
        'pdf' => Icons.picture_as_pdf_outlined,
        'docx' => Icons.description_outlined,
        'jpg' || 'jpeg' || 'png' => Icons.image_outlined,
        _ => Icons.insert_drive_file_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(_icone, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  anexo.nomeLocal,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  anexo.tamanhoFormatado,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (onRemover != null)
            IconButton(
              icon: Icon(Icons.close, color: Colors.grey.shade500, size: 20),
              onPressed: onRemover,
            ),
        ],
      ),
    );
  }
}
