import '../models/area.dart';
import '../models/area_selecionada.dart';
import '../models/demanda.dart';
import '../models/demandante.dart';
import '../models/enums.dart';
import '../models/professor.dart';
import '../models/sessao_usuario.dart';

String apiId(dynamic value) {
  if (value is! int || value <= 0) throw const FormatException('ID inválido');
  return value.toString();
}

int numericId(String value) {
  final id = int.tryParse(value);
  if (id == null || id <= 0) throw const FormatException('ID inválido');
  return id;
}

List<Map<String, dynamic>> apiList(dynamic value) => (value as List? ?? [])
    .map((v) => Map<String, dynamic>.from(v as Map))
    .toList();

UserRole apiRole(dynamic role) => switch (role) {
      'admin' => UserRole.administrador,
      'professor' => UserRole.professor,
      'demandante' => UserRole.demandante,
      _ => throw const FormatException('Papel desconhecido'),
    };
SessaoUsuario apiSession(Map<String, dynamic> m) => SessaoUsuario(
    id: apiId(m['id']),
    email: m['email'] as String,
    nome: m['name'] as String,
    role: apiRole(m['role']),
    fotoUrl: m['photo_url'] as String?);

Demandante apiApplicant(Map<String, dynamic> m) => Demandante(
    id: apiId(m['id']),
    email: m['email'] as String,
    nome: m['name'] as String,
    criadoEm: DateTime.parse(m['created_at'] as String),
    fotoUrl: m['photo_url'] as String?,
    telefone: m['phone'] as String,
    tipo: TipoDemandante.values.byName(m['type'] as String),
    cpfCnpj: m['cpf_cnpj'] as String,
    endereco: m['address'] as String,
    strikes: m['strikes'] as int,
    banido: m['blocked'] as bool);

Professor apiTeacher(Map<String, dynamic> m) {
  final areas = apiList(m['areas']);
  List<AreaSelecionada> select(String type) => areas
      .where((a) => a['type'] == type)
      .map((a) =>
          AreaSelecionada(id: apiId(a['areas_id']), nome: a['name'] as String))
      .toList();
  return Professor(
      id: apiId(m['id']),
      email: m['email'] as String,
      nome: m['name'] as String,
      criadoEm: DateTime.parse(m['created_at'] as String),
      fotoUrl: m['photo_url'] as String?,
      siape: m['siape'] as String,
      ativo: m['is_active'] as bool,
      areasTecnicas: select('técnica'),
      areasInteresse: select('interesse'));
}

Area apiArea(Map<String, dynamic> m) => Area(
    id: apiId(m['id']),
    nome: m['name'] as String,
    // O contrato de áreas não informa autoria nem data de criação.
    criadoEm: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    criadoPor: '');

Demanda apiDemand(Map<String, dynamic> m) {
  // Validar enums antes do mapper legado, que aceita defaults do Firestore.
  StatusDemanda.values.byName(m['status'] as String);
  TipoDemandante.values.byName(m['demandanteTipo'] as String);
  return Demanda.fromMap(apiId(m['id']), {
    ...m,
    'demandanteUid': apiId(m['demandanteId']),
    'professorUid': m['professorId'] == null ? null : apiId(m['professorId']),
  });
}
