/// Referência de área. ID nulo existe apenas na leitura de perfis legados.
class AreaSelecionada {
  final String? id;
  final String nome;
  const AreaSelecionada({required this.id, required this.nome});
  const AreaSelecionada.legada(this.nome) : id = null;

  @override
  bool operator ==(Object other) =>
      other is AreaSelecionada &&
      (id != null ? id == other.id : other.id == null && nome == other.nome);
  @override
  int get hashCode => id?.hashCode ?? nome.hashCode;
}
