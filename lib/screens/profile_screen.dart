import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/change_password_dialog.dart';
import 'business_picker_screen.dart';
import 'issuer_settings_screen.dart';
import 'login_screen.dart';

/// Iniciales para el avatar ("Rubén Gutiérrez" → "RG").
String initialsOf(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  final first = parts.first.characters.first;
  final last = parts.length > 1 ? parts.last.characters.first : '';
  return (first + last).toUpperCase();
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    final sync = SyncService.instance;
    final pending = sync.pending;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: Text(pending > 0
            ? 'Hay $pending cambio(s) sin sincronizar. Si cierras sesión ahora se perderán.\n\n'
                'Conéctate a internet y espera a que se sincronicen antes de salir.'
            : 'Se borrarán los datos guardados en este dispositivo. Siguen en el servidor '
                'y se descargan al volver a entrar.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: pending > 0
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child:
                Text(pending > 0 ? 'Salir y perder cambios' : 'Cerrar sesión'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    sync.stop();
    await sync.idle();
    await AuthService.instance.logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final session = AuthService.instance.session!;
    final user = session.user;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final portalUrl = '${session.serverUrl}/admin';

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Cabecera: quién eres y en qué negocio.
          Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                child: Text(initialsOf(user.name),
                    style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 2),
                    Text(session.businessName,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: colors.muted)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      _RoleBadge(isAdmin: user.isAdmin),
                      if (user.isSuperadmin) const _SuperBadge(),
                    ]),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          _SectionTitle('Apariencia'),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: ThemeController.instance,
            builder: (context, mode, _) => SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_outlined),
                      label: Text('Sistema')),
                  ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_outlined),
                      label: Text('Claro')),
                  ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_outlined),
                      label: Text('Oscuro')),
                ],
                selected: {mode},
                showSelectedIcon: false,
                onSelectionChanged: (s) =>
                    ThemeController.instance.set(s.first),
              ),
            ),
          ),
          const SizedBox(height: 28),

          _SectionTitle('Sincronización'),
          ListenableBuilder(
            listenable: SyncService.instance,
            builder: (context, _) {
              final sync = SyncService.instance;
              final last = sync.lastSync;
              final (text, color) = switch (sync.status) {
                SyncStatus.syncing => (
                    'Sincronizando…',
                    theme.colorScheme.primary
                  ),
                SyncStatus.offline => (
                    'Sin conexión con el servidor',
                    colors.pending
                  ),
                SyncStatus.error || SyncStatus.sessionExpired => (
                    sync.lastError ?? 'Error al sincronizar',
                    colors.overdue
                  ),
                SyncStatus.idle when sync.pending > 0 => (
                    '${sync.pending} cambio(s) por enviar',
                    colors.pending
                  ),
                SyncStatus.idle => ('Todo sincronizado', colors.paid),
              };
              return Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.circle, size: 12, color: color),
                      title: Text(text),
                      subtitle: last == null
                          ? null
                          : Text('Última vez: ${fmtDate(last)} a las '
                              '${last.hour.toString().padLeft(2, '0')}:${last.minute.toString().padLeft(2, '0')}'),
                      trailing: IconButton(
                        tooltip: 'Sincronizar ahora',
                        icon: const Icon(Icons.sync),
                        onPressed: sync.status == SyncStatus.syncing
                            ? null
                            : sync.sync,
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.dns_outlined),
                      title: const Text('Servidor'),
                      subtitle: Text(session.serverUrl),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 28),

          _SectionTitle('Cuenta y negocio'),
          Card(
            child: Column(
              children: [
                if (session.hasSeveralBusinesses) ...[
                  ListTile(
                    leading: const Icon(Icons.swap_horiz),
                    title: const Text('Cambiar de negocio'),
                    subtitle: Text('Trabajas en ${session.businesses.length} negocios'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const BusinessPickerScreen())),
                  ),
                  const Divider(),
                ],
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Usuario'),
                  subtitle: Text(user.username),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: const Text('Cambiar contraseña'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showChangePasswordDialog(context),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title: const Text('Datos del emisor'),
                  subtitle: Text(user.isAdmin
                      ? 'Logo, identificación fiscal, numeración'
                      : 'Solo lectura'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const IssuerSettingsScreen())),
                ),
              ],
            ),
          ),

          if (user.isAdmin || user.webAccess) ...[
            const SizedBox(height: 28),
            _SectionTitle(user.isAdmin ? 'Administración y web' : 'Versión web'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.isAdmin
                        ? 'Desde la web, con tu mismo usuario, gestionas el equipo, las '
                            'contraseñas y los datos del negocio, y también puedes facturar.'
                        : 'También puedes facturar y registrar pagos desde el navegador, '
                            'con tu mismo usuario (por ejemplo, desde un iPhone).'),
                    const SizedBox(height: 12),
                    SelectableText(portalUrl,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: portalUrl));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Enlace del portal copiado')));
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copiar enlace'),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 32),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(
                  color: theme.colorScheme.error.withValues(alpha: 0.5)),
            ),
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout),
            label: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: AppColors.of(context).muted,
                fontWeight: FontWeight.w600)),
      );
}

class _SuperBadge extends StatelessWidget {
  const _SuperBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.primary.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('Superadministrador',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: scheme.primary)),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.isAdmin});
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color:
            isAdmin ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isAdmin ? Icons.verified_user_outlined : Icons.person_outline,
              size: 15,
              color: isAdmin ? scheme.onPrimaryContainer : scheme.onSurface),
          const SizedBox(width: 5),
          Text(isAdmin ? 'Administrador' : 'Miembro del equipo',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color:
                      isAdmin ? scheme.onPrimaryContainer : scheme.onSurface)),
        ],
      ),
    );
  }
}
