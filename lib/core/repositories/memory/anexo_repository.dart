import '../../exceptions/app_exception.dart';
import '../../models/anexo.dart';
import '../anexo_repository.dart';
import 'memory_store.dart';

/// Mantém apenas uma referência ao arquivo local; não faz upload remoto.
class MemoryAnexoRepository implements AnexoRepository {
  final MemoryStore store;
  MemoryAnexoRepository(this.store);
  @override
  Future<Anexo> upload(
      {required String demandaId,
      required String id,
      required AnexoPendente pendente}) async {
    await store.preparar();
    store.exigirUsuario(id: id);
    final erro = AnexoRepository.validar(pendente);
    if (erro != null) throw ValidationException(erro);
    final demanda =
        store.demandas[demandaId] ?? (throw const NotFoundException('Demanda'));
    if (demanda.demandanteId != id && demanda.professorId != id)
      throw const PermissionException();
    final anexo = Anexo(
        id: store.novoId(),
        nome: pendente.nomeLocal,
        url: Uri.file(pendente.caminhoLocal).toString(),
        tamanhoBytes: pendente.tamanhoBytes,
        formato: pendente.formato,
        enviadoPorId: id,
        enviadoEm: store.agora());
    store.anexos.putIfAbsent(demandaId, () => {})[anexo.id] = anexo;
    store.notificar();
    return anexo;
  }

  @override
  Future<void> remover(
      {required String demandaId, required Anexo anexo}) async {
    await store.preparar();
    store.exigirUsuario(id: anexo.enviadoPorId);
    store.anexos[demandaId]?.remove(anexo.id);
    store.notificar();
  }
}
