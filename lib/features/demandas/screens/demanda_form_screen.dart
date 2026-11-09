import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/texto_botao.dart';
import '../../../app/theme.dart';
import '../../../core/models/demanda.dart';
import '../../../core/models/demandante.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/repositories/demanda_repository.dart';
import '../../auth/widgets/form_label.dart';
import '../providers/demanda_form_provider.dart';
import '../widgets/anexos_section.dart';

/// Form unificado de criação e edição de demanda.
/// Decisão: uma tela só com modo controlado pelo enum, em vez de duas
/// telas quase iguais.
class DemandaFormScreen extends StatefulWidget {
  final DemandaFormModo modo;
  final Demanda? demandaExistente; // obrigatório quando modo == editar

  /// Valores iniciais para pré-preencher o formulário em modo criar.
  /// Usado pela republicação de demandas canceladas: copia título,
  /// descrição, público-alvo e impacto da demanda anterior, mas NÃO
  /// copia anexos nem metadados do ciclo de vida (status, cancelamento,
  /// professor responsável, datas).
  ///
  /// Quando essa demanda está com status `cancelada`, ao publicar a nova
  /// o repositório marca a original com `republicadaComoId` para impedir
  /// republicação dupla.
  final Demanda? valoresIniciais;

  const DemandaFormScreen({
    super.key,
    required this.modo,
    this.demandaExistente,
    this.valoresIniciais,
  })  : assert(
          modo == DemandaFormModo.criar || demandaExistente != null,
          'Edição exige demandaExistente',
        ),
        assert(
          modo == DemandaFormModo.editar || demandaExistente == null,
          'demandaExistente só faz sentido em modo editar — '
          'use valoresIniciais para pré-preencher modo criar',
        );

  @override
  State<DemandaFormScreen> createState() => _DemandaFormScreenState();
}

class _DemandaFormScreenState extends State<DemandaFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titulo;
  late final TextEditingController _descricao;
  late final TextEditingController _publicoAlvo;
  late final TextEditingController _impacto;

  /// Opções pré-definidas para o dropdown. UC15 não trava esse campo,
  /// então também aceitamos texto livre via o item "Outro".
  static const _opcoesPublicoAlvo = [
    'Escolas e universidades',
    'Empresas e indústrias',
    'Órgãos públicos',
    'ONGs e terceiro setor',
    'Comunidade em geral',
    'Pesquisa acadêmica',
    'Outro',
  ];

  bool _publicoEhPersonalizado = false;
  String? _publicoSelecionado;

  static const _maxTitulo = 100;
  static const _maxDescricao = 1000;
  static const _maxImpacto = 500;

  bool get _ehEdicao => widget.modo == DemandaFormModo.editar;

  /// ID da demanda cancelada original quando este form veio de uma
  /// republicação. null em criação normal ou edição.
  String? get _originalCanceladaId {
    final v = widget.valoresIniciais;
    if (v == null) return null;
    if (v.status != StatusDemanda.cancelada) return null;
    return v.id;
  }

  @override
  void initState() {
    super.initState();
    // Modo editar lê de demandaExistente. Modo criar pode receber
    // valoresIniciais (republicação a partir de cancelada).
    final base = widget.demandaExistente ?? widget.valoresIniciais;
    _titulo = TextEditingController(text: base?.titulo ?? '');
    _descricao = TextEditingController(text: base?.descricao ?? '');
    _publicoAlvo = TextEditingController(text: base?.publicoAlvo ?? '');
    _impacto = TextEditingController(text: base?.impacto ?? '');

    if (base != null) {
      if (_opcoesPublicoAlvo.contains(base.publicoAlvo)) {
        _publicoSelecionado = base.publicoAlvo;
      } else {
        _publicoSelecionado = 'Outro';
        _publicoEhPersonalizado = true;
      }
    }

    // Reset do provider em criação para limpar anexos pendentes residuais.
    // Em edição, carrega os anexos já existentes da demanda.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final form = context.read<DemandaFormProvider>();
      form.resetar();
      if (_ehEdicao) {
        try {
          final anexos = await context
              .read<DemandaRepository>()
              .buscarAnexos(widget.demandaExistente!.id);
          if (mounted) form.carregarAnexosExistentes(anexos);
        } catch (_) {
          // anexos não bloqueiam a edição — segue sem eles
        }
      }
    });
  }

  @override
  void dispose() {
    _titulo.dispose();
    _descricao.dispose();
    _publicoAlvo.dispose();
    _impacto.dispose();
    super.dispose();
  }

  String? _validarObrigatorio(String? v, String campo) {
    if (v == null || v.trim().isEmpty) return '$campo é obrigatório';
    return null;
  }

  String? _validarMinimo(String? v, String campo, int min) {
    final base = _validarObrigatorio(v, campo);
    if (base != null) return base;
    if (v!.trim().length < min)
      return '$campo precisa ter pelo menos $min caracteres';
    return null;
  }

  Future<void> _submeter() async {
    if (!_formKey.currentState!.validate()) return;
    if (_publicoEhPersonalizado && _publicoAlvo.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe o público-alvo personalizado'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final auth = context.read<AuthProvider>();
    final form = context.read<DemandaFormProvider>();
    final usuario = auth.usuario;
    if (usuario == null) return;

    // Esta tela só é acessível por demandantes (rota controlada pelo router).
    // Ainda assim, fazemos o type-check explícito em vez de cast dinâmico
    // para que um eventual erro estoure como falha clara de invariante.
    if (usuario is! Demandante) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Apenas demandantes podem cadastrar demandas'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final publicoFinal = _publicoEhPersonalizado
        ? _publicoAlvo.text
        : (_publicoSelecionado ?? '');

    final ok = _ehEdicao
        ? await form.editar(
            demandaId: widget.demandaExistente!.id,
            autorId: usuario.id,
            titulo: _titulo.text,
            descricao: _descricao.text,
            publicoAlvo: publicoFinal,
            impacto: _impacto.text,
          )
        : await form.criar(
            demandanteId: usuario.id,
            demandanteNome: usuario.nome,
            demandanteTipo: usuario.tipo,
            titulo: _titulo.text,
            descricao: _descricao.text,
            publicoAlvo: publicoFinal,
            impacto: _impacto.text,
            originalCanceladaId: _originalCanceladaId,
          );

    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_ehEdicao
              ? 'Demanda atualizada com sucesso'
              : 'Demanda publicada com sucesso'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.of(context).pop(true);
    } else if (form.erro != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(form.erro!),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _ehEdicao ? 'Editar Demanda' : 'Nova Demanda',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _ehEdicao
                            ? 'Atualize os campos necessários. Os professores '
                                'verão a versão mais recente.'
                            : 'Descreva sua necessidade de forma clara e '
                                'detalhada para conectarmos você com as melhores '
                                'soluções.',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),

                      _CampoComContador(
                        label: 'Título da Demanda *',
                        controller: _titulo,
                        hint: 'Ex: Sistema de Gestão de Estoque',
                        maxLength: _maxTitulo,
                        validator: (v) => _validarMinimo(v, 'Título', 5),
                      ),
                      const SizedBox(height: 20),

                      _CampoComContador(
                        label: 'Descrição Detalhada *',
                        controller: _descricao,
                        hint: 'Descreva em detalhes sua necessidade, contexto '
                            'atual, problemas a serem resolvidos e resultados '
                            'esperados',
                        maxLength: _maxDescricao,
                        maxLines: 5,
                        validator: (v) => _validarMinimo(v, 'Descrição', 30),
                      ),
                      const SizedBox(height: 20),

                      _campoPublicoAlvo(),
                      const SizedBox(height: 20),

                      _CampoComContador(
                        label: 'Impacto da Demanda *',
                        controller: _impacto,
                        hint: 'Descreva os benefícios, melhorias e resultados '
                            'esperados com a implementação da solução',
                        maxLength: _maxImpacto,
                        maxLines: 4,
                        validator: (v) => _validarMinimo(v, 'Impacto', 20),
                      ),
                      const SizedBox(height: 32),

                      // ============== ANEXOS (parte do form, conforme pedido) ==============
                      const AnexosSection(),
                      const SizedBox(height: 32),

                      _buildBotoes(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset('assets/images/logo.png', width: 56, height: 56),
              const SizedBox(width: 12),
              const Text(
                'Nexus Tech',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.arrow_back, color: AppColors.primary),
                  SizedBox(width: 8),
                  Text(
                    'Voltar',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _campoPublicoAlvo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FormLabel('Público-alvo *'),
        DropdownButtonFormField<String>(
          initialValue: _publicoSelecionado,
          isExpanded: true,
          decoration: const InputDecoration(
            hintText: 'Selecione o público-alvo',
          ),
          items: _opcoesPublicoAlvo
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          validator: (v) => v == null ? 'Selecione um público-alvo' : null,
          onChanged: (v) {
            setState(() {
              _publicoSelecionado = v;
              _publicoEhPersonalizado = v == 'Outro';
              if (!_publicoEhPersonalizado) {
                _publicoAlvo.clear();
              }
            });
          },
        ),
        if (_publicoEhPersonalizado) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _publicoAlvo,
            decoration: const InputDecoration(
              hintText: 'Especifique o público-alvo',
            ),
            validator: (v) => _publicoEhPersonalizado
                ? _validarObrigatorio(v, 'Público-alvo')
                : null,
          ),
        ],
      ],
    );
  }

  Widget _buildBotoes() {
    final form = context.watch<DemandaFormProvider>();
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: form.salvando ? null : _submeter,
            child: form.salvando
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : Text(_ehEdicao ? 'Salvar edições' : 'Publicar demanda'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton(
            onPressed: form.salvando ? null : () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: BorderSide(color: Colors.grey.shade300),
              minimumSize: const Size.fromHeight(56),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: TextoBotao(_ehEdicao ? 'Cancelar' : 'Descartar'),
          ),
        ),
      ],
    );
  }
}

class _CampoComContador extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final int maxLength;
  final int maxLines;
  final String? Function(String?)? validator;

  const _CampoComContador({
    required this.label,
    required this.controller,
    required this.hint,
    required this.maxLength,
    this.maxLines = 1,
    this.validator,
  });

  @override
  State<_CampoComContador> createState() => _CampoComContadorState();
}

class _CampoComContadorState extends State<_CampoComContador> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_atualizarContador);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_atualizarContador);
    super.dispose();
  }

  void _atualizarContador() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final atual = widget.controller.text.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormLabel(widget.label),
        TextFormField(
          controller: widget.controller,
          maxLength: widget.maxLength,
          maxLines: widget.maxLines,
          textCapitalization: widget.maxLines > 1
              ? TextCapitalization.sentences
              : TextCapitalization.words,
          inputFormatters: [LengthLimitingTextInputFormatter(widget.maxLength)],
          decoration: InputDecoration(
            hintText: widget.hint,
            counterText: '',
          ),
          validator: widget.validator,
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '$atual/${widget.maxLength} caracteres',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ),
      ],
    );
  }
}
