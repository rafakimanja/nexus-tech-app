import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../core/models/demandante.dart';
import '../../../core/models/enums.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/utils/input_formatters.dart';
import '../../../core/utils/validators.dart';
import '../../auth/widgets/form_label.dart';
import '../providers/perfil_provider.dart';

/// UC23 — Edição do perfil do demandante. Campos editáveis: nome, telefone,
/// tipo e endereço (validados). E-mail e CPF/CNPJ são identidade e ficam
/// somente leitura.
class EditarPerfilDemandanteScreen extends StatefulWidget {
  final Demandante demandante;
  const EditarPerfilDemandanteScreen({super.key, required this.demandante});

  @override
  State<EditarPerfilDemandanteScreen> createState() =>
      _EditarPerfilDemandanteScreenState();
}

class _EditarPerfilDemandanteScreenState
    extends State<EditarPerfilDemandanteScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nome;
  late final TextEditingController _telefone;
  late final TextEditingController _endereco;
  TipoDemandante? _tipo;

  @override
  void initState() {
    super.initState();
    final d = widget.demandante;
    _nome = TextEditingController(text: d.nome);
    _telefone = TextEditingController(text: _mascararTelefone(d.telefone));
    _endereco = TextEditingController(text: d.endereco);
    _tipo = d.tipo == TipoDemandante.naoInformado ? null : d.tipo;
  }

  @override
  void dispose() {
    _nome.dispose();
    _telefone.dispose();
    _endereco.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    final perfil = context.read<PerfilProvider>();
    final auth = context.read<AuthProvider>();

    final ok = await perfil.salvarDemandante(
      id: widget.demandante.id,
      nome: _nome.text,
      telefone: _telefone.text,
      tipo: _tipo!,
      endereco: _endereco.text,
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
                _readOnly('E-mail', widget.demandante.email),
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
                const FormLabel('Telefone *'),
                TextFormField(
                  controller: _telefone,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                    TelefoneInputFormatter(),
                  ],
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.phone, color: AppColors.primary),
                    hintText: '(xx) xxxxx-xxxx',
                  ),
                  validator: Validators.telefone,
                ),
                const SizedBox(height: 20),
                const FormLabel('Tipo de Demandante *'),
                DropdownButtonFormField<TipoDemandante>(
                  initialValue: _tipo,
                  decoration: const InputDecoration(
                    prefixIcon:
                        Icon(Icons.business_center, color: AppColors.primary),
                  ),
                  items: TipoDemandante.cadastraveis
                      .map((t) =>
                          DropdownMenuItem(value: t, child: Text(t.label)))
                      .toList(),
                  onChanged: (v) => setState(() => _tipo = v ?? _tipo),
                  validator: (v) => v == null ? 'Selecione um tipo' : null,
                ),
                const SizedBox(height: 20),
                const FormLabel('Endereço *'),
                TextFormField(
                  controller: _endereco,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.location_on_outlined,
                        color: AppColors.primary),
                    hintText: 'Rua, número, bairro',
                  ),
                  validator: Validators.endereco,
                ),
                const SizedBox(height: 20),
                _readOnly('CPF/CNPJ (não editável)', widget.demandante.cpfCnpj),
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

  String _mascararTelefone(String digits) {
    if (digits.length == 11) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2, 7)}-${digits.substring(7)}';
    }
    if (digits.length == 10) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2, 6)}-${digits.substring(6)}';
    }
    return digits;
  }
}
