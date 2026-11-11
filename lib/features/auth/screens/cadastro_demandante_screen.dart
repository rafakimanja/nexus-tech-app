import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/texto_botao.dart';
import '../../../app/theme.dart';
import '../../../core/models/enums.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/utils/input_formatters.dart';
import '../../../core/utils/validators.dart';
import '../providers/cadastro_provider.dart';
import '../widgets/auth_header.dart';
import '../widgets/form_label.dart';

class CadastroDemandanteScreen extends StatefulWidget {
  const CadastroDemandanteScreen({super.key});

  @override
  State<CadastroDemandanteScreen> createState() =>
      _CadastroDemandanteScreenState();
}

class _CadastroDemandanteScreenState extends State<CadastroDemandanteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nome = TextEditingController();
  final _telefone = TextEditingController();
  final _cpfCnpj = TextEditingController();
  final _endereco = TextEditingController();
  TipoDemandante? _tipo;

  @override
  void dispose() {
    _nome.dispose();
    _telefone.dispose();
    _cpfCnpj.dispose();
    _endereco.dispose();
    super.dispose();
  }

  Future<void> _submeter() async {
    final formOk = _formKey.currentState!.validate();
    final tipoOk = _tipo != null;

    if (!tipoOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione o tipo de demandante')),
      );
    }
    if (!formOk || !tipoOk) return;

    final auth = context.read<AuthProvider>();
    final cadastro = context.read<CadastroProvider>();
    final sessao = auth.sessao;

    if (sessao == null) return;

    final ok = await cadastro.cadastrarDemandante(
      id: sessao.id,
      email: sessao.email,
      nome: _nome.text,
      telefone: _telefone.text,
      tipo: _tipo!,
      cpfCnpj: _cpfCnpj.text,
      endereco: _endereco.text,
    );

    if (!mounted) return;

    if (ok) {
      await auth.recarregarUsuario();
    } else if (cadastro.erro != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(cadastro.erro!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cadastro = context.watch<CadastroProvider>();

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
                const AuthHeader(titulo: 'Cadastro de Demandante'),
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
                    hintText: 'Selecione',
                  ),
                  items: TipoDemandante.cadastraveis
                      .map((t) =>
                          DropdownMenuItem(value: t, child: Text(t.label)))
                      .toList(),
                  onChanged: (v) => setState(() => _tipo = v),
                  validator: (v) => v == null ? 'Selecione um tipo' : null,
                ),
                const SizedBox(height: 20),
                const FormLabel('CPF ou CNPJ *'),
                TextFormField(
                  controller: _cpfCnpj,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(14),
                    CpfCnpjInputFormatter(),
                  ],
                  decoration: const InputDecoration(
                    hintText: 'Digite seu CPF ou CNPJ',
                  ),
                  validator: Validators.cpfCnpj,
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
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: cadastro.salvando ? null : _submeter,
                  child: cadastro.salvando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const TextoBotao('Concluir cadastro'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
