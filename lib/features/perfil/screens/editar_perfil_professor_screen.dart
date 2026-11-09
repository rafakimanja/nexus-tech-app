import '../../auth/widgets/nova_area_dialog.dart';
import '../../../core/models/area_selecionada.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../core/models/professor.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/repositories/area_repository.dart';
import '../../../core/utils/validators.dart';
import '../../auth/providers/cadastro_provider.dart';
import '../../auth/widgets/form_label.dart';
import '../providers/perfil_provider.dart';

/// UC23 — Edição do perfil do professor. Campos editáveis: nome, áreas
/// técnicas e áreas de interesse (validados). E-mail e SIAPE são identidade
/// institucional e ficam somente leitura.
class EditarPerfilProfessorScreen extends StatefulWidget {
  final Professor professor;
  const EditarPerfilProfessorScreen({super.key, required this.professor});

  @override
  State<EditarPerfilProfessorScreen> createState() =>
      _EditarPerfilProfessorScreenState();
}

class _EditarPerfilProfessorScreenState
    extends State<EditarPerfilProfessorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nome;
  late final Set<AreaSelecionada> _areasTecnicas;
  late final Set<AreaSelecionada> _areasInteresse;
  bool _tentouSalvar = false;

  @override
  void initState() {
    super.initState();
    _nome = TextEditingController(text: widget.professor.nome);
    _areasTecnicas = {...widget.professor.areasTecnicas};
    _areasInteresse = {...widget.professor.areasInteresse};
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CadastroProvider>().carregarAreas();
    });
  }

  @override
  void dispose() {
    _nome.dispose();
    super.dispose();
  }

  Future<void> _adicionarArea({required TipoArea tipo}) async {
    final cadastro = context.read<CadastroProvider>();
    final nomeFinal = await showDialog<AreaSelecionada>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NovaAreaDialog(
        tipo: tipo,
        criadoPorId: widget.professor.id,
        cadastro: cadastro,
      ),
    );
    if (!mounted) return;
    if (nomeFinal != null) {
      setState(() {
        if (tipo == TipoArea.tecnica) {
          _areasTecnicas.add(nomeFinal);
        } else {
          _areasInteresse.add(nomeFinal);
        }
      });
    }
  }

  Future<void> _salvar() async {
    setState(() => _tentouSalvar = true);

    final formOk = _formKey.currentState!.validate();
    if (!formOk || _areasTecnicas.isEmpty || _areasInteresse.isEmpty) return;

    final perfil = context.read<PerfilProvider>();
    final auth = context.read<AuthProvider>();

    final ok = await perfil.salvarProfessor(
      id: widget.professor.id,
      nome: _nome.text,
      areasTecnicas: _areasTecnicas.toList(),
      areasInteresse: _areasInteresse.toList(),
    );

    if (!mounted) return;
    if (ok) {
      await auth.recarregarUsuario();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Perfil atualizado com sucesso'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.of(context).pop();
    } else if (perfil.erro != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(perfil.erro!), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cadastro = context.watch<CadastroProvider>();
    final salvando = context.watch<PerfilProvider>().salvando;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _voltar(),
                const SizedBox(height: 8),
                const Text(
                  'Editar Perfil',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 24),
                _readOnly('E-mail', widget.professor.email),
                const SizedBox(height: 20),
                const FormLabel('Nome *'),
                TextFormField(
                  controller: _nome,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Digite seu nome completo',
                  ),
                  validator: Validators.nome,
                ),
                const SizedBox(height: 20),
                _readOnly('SIAPE (não editável)', widget.professor.siape),
                const SizedBox(height: 20),
                const FormLabel('Áreas Técnicas *'),
                _ChipsSelector(
                  opcoes: cadastro.areasTecnicas
                      .map((a) => AreaSelecionada(id: a.id, nome: a.nome))
                      .toList(),
                  selecionadas: _areasTecnicas,
                  onToggle: (a) => setState(() {
                    if (_areasTecnicas.contains(a)) {
                      _areasTecnicas.remove(a);
                    } else {
                      _areasTecnicas.add(a);
                    }
                  }),
                  onAdicionar: () => _adicionarArea(tipo: TipoArea.tecnica),
                ),
                if (_tentouSalvar && _areasTecnicas.isEmpty)
                  const _ErroCampo('Selecione ao menos uma área técnica'),
                const SizedBox(height: 20),
                const FormLabel('Áreas de Interesse *'),
                _ChipsSelector(
                  opcoes: cadastro.areasInteresse
                      .map((a) => AreaSelecionada(id: a.id, nome: a.nome))
                      .toList(),
                  selecionadas: _areasInteresse,
                  onToggle: (a) => setState(() {
                    if (_areasInteresse.contains(a)) {
                      _areasInteresse.remove(a);
                    } else {
                      _areasInteresse.add(a);
                    }
                  }),
                  onAdicionar: () => _adicionarArea(tipo: TipoArea.interesse),
                ),
                if (_tentouSalvar && _areasInteresse.isEmpty)
                  const _ErroCampo('Selecione ao menos uma área de interesse'),
                const SizedBox(height: 36),
                _botoes(salvando),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _voltar() => InkWell(
        onTap: () => Navigator.of(context).pop(),
        borderRadius: BorderRadius.circular(8),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_back, color: AppColors.primary),
              SizedBox(width: 8),
              Text('Voltar',
                  style: TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );

  Widget _readOnly(String label, String valor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormLabel(label),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Text(
            valor,
            style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
          ),
        ),
      ],
    );
  }

  Widget _botoes(bool salvando) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: salvando ? null : () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: BorderSide(color: Colors.grey.shade300),
              minimumSize: const Size.fromHeight(52),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
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
            onPressed: salvando ? null : _salvar,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: salvando
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const FittedBox(
                    fit: BoxFit.scaleDown,
                    child:
                        Text('Salvar alterações', maxLines: 1, softWrap: false),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ErroCampo extends StatelessWidget {
  final String mensagem;
  const _ErroCampo(this.mensagem);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          mensagem,
          style: const TextStyle(color: AppColors.error, fontSize: 12),
        ),
      );
}

class _ChipsSelector extends StatelessWidget {
  final List<AreaSelecionada> opcoes;
  final Set<AreaSelecionada> selecionadas;
  final ValueChanged<AreaSelecionada> onToggle;
  final VoidCallback onAdicionar;

  const _ChipsSelector({
    required this.opcoes,
    required this.selecionadas,
    required this.onToggle,
    required this.onAdicionar,
  });

  @override
  Widget build(BuildContext context) {
    final todas = {...opcoes, ...selecionadas}.toList();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...todas.map((area) {
          final selected = selecionadas.contains(area);
          return FilterChip(
            label: Text(area.nome),
            selected: selected,
            onSelected: (_) => onToggle(area),
            selectedColor: AppColors.primary,
            backgroundColor: Colors.white,
            labelStyle: TextStyle(
              color: selected ? Colors.white : AppColors.primary,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: AppColors.primary),
            ),
          );
        }),
        ActionChip(
          avatar: const Icon(Icons.add, size: 18, color: Colors.white),
          label: const Text('Nova', style: TextStyle(color: Colors.white)),
          backgroundColor: AppColors.success,
          onPressed: onAdicionar,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ],
    );
  }
}
