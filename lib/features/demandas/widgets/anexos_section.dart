import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../app/app_dependencies.dart';
import '../../../core/widgets/recurso_indisponivel.dart';
import '../../../core/models/anexo.dart';
import '../../../core/repositories/anexo_repository.dart';
import '../providers/demanda_form_provider.dart';

/// Seção de anexos. Vive DENTRO do form de demanda (não é tela separada),
/// renderizada após os campos de texto. O usuário rola até ela.
class AnexosSection extends StatelessWidget {
  /// Se a demanda está sendo editada, os anexos existentes podem ser
  /// removidos via callback.
  final void Function(Anexo anexo)? onRemoverExistente;

  const AnexosSection({super.key, this.onRemoverExistente});

  Future<void> _selecionarArquivo(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: AnexoRepository.formatosPermitidos.toList(),
      withData: false,
    );

    if (result == null || result.files.isEmpty) return;
    if (!context.mounted) return;

    final file = result.files.first;
    if (file.path == null) return;

    final pendente = AnexoPendente(
      nomeLocal: file.name,
      caminhoLocal: file.path!,
      tamanhoBytes: file.size,
      formato: (file.extension ?? '').toLowerCase(),
    );

    final form = context.read<DemandaFormProvider>();
    final erro = form.adicionarAnexo(pendente);
    if (erro != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erro), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (context.read<AppDependencies>().usaApi) return const RecursoIndisponivel('Anexos');
    return Consumer<DemandaFormProvider>(
      builder: (context, form, _) {
        final temAlgo = form.totalAnexos > 0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Anexar Arquivos',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 12),

            // Drop zone / botão de adicionar
            InkWell(
              onTap: () => _selecionarArquivo(context),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    width: 1.5,
                    style: BorderStyle.solid,
                  ),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.cloud_upload_outlined,
                      size: 32,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      temAlgo ? 'Adicionar outro arquivo' : 'Anexe aqui',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'PDF, DOCX, JPG ou PNG • máx 10 MB',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (temAlgo) ...[
              const SizedBox(height: 16),
              // Anexos já enviados (modo edição)
              ...form.anexosExistentes.map(
                (a) => _AnexoTile(
                  nome: a.nome,
                  formato: a.formato,
                  tamanho: a.tamanhoFormatado,
                  ehPendente: false,
                  onRemover: onRemoverExistente == null
                      ? null
                      : () => onRemoverExistente!(a),
                ),
              ),
              // Anexos pendentes
              ...form.anexosPendentes.asMap().entries.map(
                    (e) => _AnexoTile(
                      nome: e.value.nomeLocal,
                      formato: e.value.formato,
                      tamanho: e.value.tamanhoFormatado,
                      ehPendente: true,
                      onRemover: () => form.removerAnexoPendente(e.key),
                    ),
                  ),
            ],
          ],
        );
      },
    );
  }
}

class _AnexoTile extends StatelessWidget {
  final String nome;
  final String formato;
  final String tamanho;
  final bool ehPendente;
  final VoidCallback? onRemover;

  const _AnexoTile({
    required this.nome,
    required this.formato,
    required this.tamanho,
    required this.ehPendente,
    required this.onRemover,
  });

  IconData get _icone => switch (formato.toLowerCase()) {
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
                  nome,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      tamanho,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (ehPendente) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'pendente',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange.shade800,
                          ),
                        ),
                      ),
                    ],
                  ],
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
