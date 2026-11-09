import 'demanda.dart';
import 'enums.dart';

/// Entrada do formulário. Identificador, estado e datas pertencem ao backend.
class CriarDemanda {
  final String demandanteId;
  final String demandanteNome;
  final TipoDemandante demandanteTipo;
  final String titulo;
  final String descricao;
  final String publicoAlvo;
  final String impacto;

  const CriarDemanda(
      {required this.demandanteId,
      required this.demandanteNome,
      required this.demandanteTipo,
      required this.titulo,
      required this.descricao,
      required this.publicoAlvo,
      required this.impacto});

  Demanda materializar({required String id, required DateTime criadoEm}) =>
      Demanda(
        id: id,
        demandanteId: demandanteId,
        demandanteNome: demandanteNome,
        demandanteTipo: demandanteTipo,
        titulo: titulo,
        descricao: descricao,
        publicoAlvo: publicoAlvo,
        impacto: impacto,
        status: StatusDemanda.cadastrada,
        criadoEm: criadoEm,
      );
}
