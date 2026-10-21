import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/session.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'profile_screen.dart';

/// Elegir el negocio en el que trabajar. Los datos y cambios pendientes de
/// cada negocio se guardan por separado en el dispositivo.
class BusinessPickerScreen extends StatefulWidget {
  const BusinessPickerScreen({super.key, this.afterLogin = false});

  /// Tras iniciar sesión no hay pantalla a la que volver.
  final bool afterLogin;

  @override
  State<BusinessPickerScreen> createState() => _BusinessPickerScreenState();
}

class _BusinessPickerScreenState extends State<BusinessPickerScreen> {
  int? _busyId;

  AuthService get _auth => AuthService.instance;

  Future<void> _choose(BusinessRef business) async {
    final session = _auth.session!;
    if (business.id == session.businessId) {
      _goHome();
      return;
    }
    setState(() => _busyId = business.id);
    final sync = SyncService.instance;
    try {
      // La sincronización en curso termina en el negocio en que empezó.
      sync.stop();
      await sync.idle();
      await _auth.switchBusiness(business.id);
      if (mounted) _goHome();
    } catch (e) {
      sync.start();
      if (!mounted) return;
      setState(() => _busyId = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e is NetworkException
            ? 'Para cambiar de negocio necesitas conexión con el servidor.'
            : e.toString()),
      ));
    }
  }

  void _goHome() {
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final session = _auth.session!;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.afterLogin,
        title: Text(widget.afterLogin ? 'Elige un negocio' : 'Cambiar de negocio'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
            child: Text(
              'Trabajas en ${session.businesses.length} negocios. Cada uno tiene sus '
              'propias facturas; puedes cambiar cuando quieras desde tu perfil.',
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.muted),
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < session.businesses.length; i++) ...[
                  if (i > 0) const Divider(indent: 72),
                  _tile(session.businesses[i], session),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(BusinessRef b, Session session) {
    final theme = Theme.of(context);
    final current = b.id == session.businessId;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        backgroundColor: current ? theme.colorScheme.primary : theme.colorScheme.primaryContainer,
        foregroundColor: current ? theme.colorScheme.onPrimary : theme.colorScheme.onPrimaryContainer,
        child: Text(initialsOf(b.name), style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      title: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(current
          ? '${b.isAdmin ? 'Administrador' : 'Miembro'}. Estás aquí ahora'
          : (b.isAdmin ? 'Administrador' : 'Miembro')),
      trailing: _busyId == b.id
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(current ? Icons.check_circle : Icons.chevron_right,
              color: current ? theme.colorScheme.primary : null),
      onTap: _busyId == null ? () => _choose(b) : null,
    );
  }
}
