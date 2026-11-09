import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_tech/core/models/area_selecionada.dart';
import 'package:nexus_tech/core/models/criar_demanda.dart';
import 'package:nexus_tech/core/models/enums.dart';
import 'package:nexus_tech/core/models/professor.dart';

void main() {
  test('renomear IDs no domínio mantém as chaves legadas do Firestore', () {
    const dados = CriarDemanda(
        demandanteId: 'firebase-user',
        demandanteNome: 'Nome',
        demandanteTipo: TipoDemandante.ong,
        titulo: 'Título',
        descricao: 'Descrição',
        publicoAlvo: 'Público',
        impacto: 'Impacto');
    final d =
        dados.materializar(id: 'document-id', criadoEm: DateTime.utc(2026));
    expect(d.toMap()['demandanteUid'], 'firebase-user');
    expect(d.toMap().containsKey('demandanteId'), false);
    final p = Professor(
        id: 'firebase-professor',
        email: 'p@example.test',
        nome: 'Professor',
        criadoEm: DateTime.utc(2026),
        siape: '0012345',
        areasTecnicas: [
          const AreaSelecionada(id: 'doc-area', nome: 'Software')
        ],
        areasInteresse: []);
    expect(p.toMap()['uid'], p.id);
    expect(p.toMap()['areasTecnicas'], ['Software']);
    final legado = Professor.fromMap(p.toMap());
    expect(legado.id, p.id);
    expect(legado.areasTecnicas.single.nome, 'Software');
    expect(legado.areasTecnicas.single.id, isNull);
  });

  test('áreas com mesmo nome e IDs diferentes não se confundem', () {
    const a = AreaSelecionada(id: '10', nome: 'Software');
    const b = AreaSelecionada(id: '11', nome: 'Software');
    expect({a, b}.length, 2);
    expect(a, const AreaSelecionada(id: '10', nome: 'Nome atualizado'));
  });
}
