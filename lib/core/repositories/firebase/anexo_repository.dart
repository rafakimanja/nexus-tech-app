import '../anexo_repository.dart';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

import '../../exceptions/app_exception.dart';
import '../../exceptions/firestore_error_handler.dart';
import '../../models/anexo.dart';
import 'demanda_repository.dart';

class FirebaseAnexoRepository implements AnexoRepository {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseDemandaRepository _demandaRepository;

  FirebaseAnexoRepository({FirebaseDemandaRepository? demandaRepository})
      : _demandaRepository = demandaRepository ?? FirebaseDemandaRepository();

  /// UC20 R01: formatos permitidos.
  static const Set<String> formatosPermitidos = {'pdf', 'docx', 'jpg', 'png'};

  /// UC20 R02: tamanho máximo 10MB.
  static const int tamanhoMaximoBytes = 10 * 1024 * 1024;

  /// Valida se um arquivo pendente passa nas regras de negócio.
  /// Retorna mensagem de erro ou null se OK.

  /// IMPORTANTE: a verificação de "antivírus" prevista em UC20 R03
  /// não é executável client-side de forma confiável. Aqui validamos
  /// apenas extensão + MIME inferido + tamanho. A verificação real
  /// deveria ser uma Cloud Function async pós-upload chamando uma
  /// API de scanner (VirusTotal, ClamAV server, etc) — fica como
  /// trabalho futuro de hardening de segurança.
  static String? validar(AnexoPendente anexo) {
    final formatoLower = anexo.formato.toLowerCase();
    if (!formatosPermitidos.contains(formatoLower)) {
      return 'Formato não permitido. Use: '
          '${formatosPermitidos.join(", ").toUpperCase()}';
    }
    if (anexo.tamanhoBytes > tamanhoMaximoBytes) {
      return 'Arquivo muito grande. Máximo 10MB '
          '(este: ${anexo.tamanhoFormatado})';
    }
    if (anexo.tamanhoBytes <= 0) {
      return 'Arquivo vazio ou corrompido';
    }
    return null;
  }

  /// Faz upload do arquivo no Storage e registra o metadata no Firestore.
  /// Operação atômica do ponto de vista do consumidor: se falhar, limpa.
  @override
  Future<Anexo> upload({
    required String demandaId,
    required String id,
    required AnexoPendente pendente,
  }) async {
    final erroValidacao = validar(pendente);
    if (erroValidacao != null) {
      throw ValidationException(erroValidacao);
    }

    final nomeStorage =
        '${DateTime.now().millisecondsSinceEpoch}_${pendente.nomeLocal}';
    final caminhoStorage = 'demandas/$demandaId/anexos/$nomeStorage';

    final arquivo = File(pendente.caminhoLocal);
    final ref = _storage.ref(caminhoStorage);

    try {
      // 1. Upload do binário
      final task = await ref.putFile(
        arquivo,
        SettableMetadata(
          contentType: _mimeFromFormato(pendente.formato),
          customMetadata: {
            'enviadoPorUid': id,
            'demandaId': demandaId,
          },
        ),
      );
      final url = await task.ref.getDownloadURL();

      // 2. Metadata no Firestore
      final agora = DateTime.now();
      final dadosAnexo = {
        'nome': pendente.nomeLocal,
        'url': url,
        'caminhoStorage': caminhoStorage, // necessário para deletar depois
        'tamanhoBytes': pendente.tamanhoBytes,
        'formato': pendente.formato,
        'enviadoPorUid': id,
        'enviadoEm': agora.toIso8601String(),
      };

      final anexoId = await _demandaRepository.registrarAnexo(
        demandaId: demandaId,
        dadosAnexo: dadosAnexo,
      );

      return Anexo(
        id: anexoId,
        nome: pendente.nomeLocal,
        url: url,
        tamanhoBytes: pendente.tamanhoBytes,
        formato: pendente.formato,
        enviadoPorId: id,
        enviadoEm: agora,
      );
    } catch (e) {
      // Tenta limpar o arquivo do Storage caso tenha subido mas falhado depois.
      try {
        await ref.delete();
      } catch (_) {
        // best effort
      }
      if (e is AppException) rethrow;
      throw mapFirestoreError(e, recurso: 'Anexo');
    }
  }

  /// Remove anexo (Firestore + Storage).
  @override
  Future<void> remover({
    required String demandaId,
    required Anexo anexo,
  }) async {
    try {
      await _storage.refFromURL(anexo.url).delete();
    } catch (_) {
      // Mesmo se o arquivo já não existir, prossegue para deletar o metadata.
    }
    await _demandaRepository.removerAnexoMetadata(
      demandaId: demandaId,
      anexoId: anexo.id,
    );
  }

  String _mimeFromFormato(String formato) => switch (formato.toLowerCase()) {
        'pdf' => 'application/pdf',
        'docx' =>
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        _ => 'application/octet-stream',
      };
}
