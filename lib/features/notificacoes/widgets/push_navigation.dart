import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app/app_dependencies.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/repositories/api/notificacao_repository.dart';
import '../../../core/services/api_push_service.dart';
import '../screens/notificacoes_screen.dart';

/// Aguarda o login e confirma no histórico da sessão antes de abrir um push.
class PushNavigation extends StatefulWidget {
  final Widget child;
  const PushNavigation({super.key, required this.child});
  @override
  State<PushNavigation> createState() => _PushNavigationState();
}

class _PushNavigationState extends State<PushNavigation> {
  ApiPushService? _push;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _push = context.read<AppDependencies>().push;
    _push?.addListener(_schedule);
  }

  void _schedule() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => _open());

  Future<void> _open() async {
    if (!mounted || _busy) return;
    final data = _push?.pendingOpen;
    final auth = context.read<AuthProvider>();
    if (data == null || auth.status != AuthStatus.autenticado) return;
    final user = auth.sessao?.id;
    _busy = true;
    try {
      final repo = context.read<AppDependencies>().notificacao
          as ApiNotificacaoRepository;
      final items = await repo.listar();
      if (!mounted || auth.sessao?.id != user) return;
      _push?.pendingOpen = null;
      for (final n in items) {
        if (n.id == data['notification_id']) {
          await NotificacoesScreen.abrirNotificacao(context, n);
          break;
        }
      }
    } catch (_) {
      if (mounted) {
        _push?.pendingOpen = null;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Não foi possível abrir o aviso. Consulte suas notificações.'),
        ));
      }
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AuthProvider>();
    _schedule();
    return widget.child;
  }

  @override
  void dispose() {
    _push?.removeListener(_schedule);
    super.dispose();
  }
}
