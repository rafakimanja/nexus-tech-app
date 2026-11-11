enum UserRole { administrador, professor, demandante }

enum TipoDemandante {
  empresa,
  orgaoPublico,
  ong,
  instituicaoEducacional,
  pessoaFisica,
  academico,
  naoInformado;

  /// Valores aceitos ao criar ou editar um cadastro. O último valor existe
  /// apenas para exibir registros antigos/incompletos sem inventar um tipo.
  static List<TipoDemandante> get cadastraveis =>
      values.where((tipo) => tipo != naoInformado).toList();

  static TipoDemandante fromApi(String? value) {
    String normalizar(String text) => text.trim().toLowerCase()
        .replaceAll(RegExp('[áàãâ]'), 'a')
        .replaceAll(RegExp('[éê]'), 'e')
        .replaceAll(RegExp('[í]'), 'i')
        .replaceAll(RegExp('[óôõ]'), 'o')
        .replaceAll(RegExp('[úü]'), 'u')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'[\s_-]'), '');
    final normalized = normalizar(value ?? '');
    return values.firstWhere(
      (tipo) => normalizar(tipo.name) == normalized ||
          normalizar(tipo.label) == normalized,
      orElse: () => naoInformado,
    );
  }

  String get label => switch (this) {
        TipoDemandante.empresa => 'Empresa',
        TipoDemandante.orgaoPublico => 'Órgão Público',
        TipoDemandante.ong => 'ONG',
        TipoDemandante.instituicaoEducacional => 'Instituição Educacional',
        TipoDemandante.pessoaFisica => 'Pessoa Física',
        TipoDemandante.academico => 'Acadêmico',
        TipoDemandante.naoInformado => 'Não informado',
      };
}
