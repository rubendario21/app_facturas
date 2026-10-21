import 'package:flutter/material.dart';

import '../services/sync_service.dart';
import '../utils/format.dart';

/// Icono de estado de la sincronización; al pulsarlo muestra el detalle.
class SyncButton extends StatelessWidget {
  const SyncButton({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = SyncService.instance;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final Widget icon = switch (sync.status) {
          SyncStatus.syncing => const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SyncStatus.offline => const Icon(Icons.cloud_off),
          SyncStatus.error ||
          SyncStatus.sessionExpired =>
            Icon(Icons.sync_problem, color: scheme.error),
          SyncStatus.idle when sync.pending > 0 =>
            const Icon(Icons.cloud_upload_outlined),
          SyncStatus.idle => const Icon(Icons.cloud_done_outlined),
        };
        return IconButton(
          tooltip: _title(sync),
          onPressed: () => _showDetails(context),
          icon: sync.pending > 0 && sync.status != SyncStatus.syncing
              ? Badge(label: Text('${sync.pending}'), child: icon)
              : icon,
        );
      },
    );
  }

  static String _title(SyncService s) => switch (s.status) {
        SyncStatus.syncing => 'Sincronizando…',
        SyncStatus.offline => 'Sin conexión',
        SyncStatus.error => 'Error de sincronización',
        SyncStatus.sessionExpired => 'Sesión caducada',
        SyncStatus.idle when s.pending > 0 => 'Cambios pendientes de enviar',
        SyncStatus.idle => 'Todo sincronizado',
      };

  void _showDetails(BuildContext context) {
    final sync = SyncService.instance;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListenableBuilder(
        listenable: sync,
        builder: (ctx, _) {
          final last = sync.lastSync;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_title(sync), style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Text(sync.pending == 0
                      ? 'No hay cambios pendientes en este dispositivo.'
                      : '${sync.pending} cambio(s) de este dispositivo esperan a enviarse.'),
                  if (last != null)
                    Text('Última sincronización: ${fmtDate(last)} '
                        '${last.hour.toString().padLeft(2, '0')}:${last.minute.toString().padLeft(2, '0')}'),
                  if (sync.status == SyncStatus.offline)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                          'Puedes seguir trabajando: los cambios se guardan en el '
                          'dispositivo y se envían al recuperar la conexión.'),
                    ),
                  if (sync.lastError != null &&
                      sync.status != SyncStatus.offline)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(sync.lastError!,
                          style: TextStyle(
                              color: Theme.of(ctx).colorScheme.error)),
                    ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed:
                        sync.status == SyncStatus.syncing ? null : sync.sync,
                    icon: const Icon(Icons.sync),
                    label: const Text('Sincronizar ahora'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
