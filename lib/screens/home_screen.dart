import 'package:flutter/material.dart';

import '../data/invoice_repository.dart';
import '../data/issuer_repository.dart';
import '../models/invoice.dart';
import '../models/issuer.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/status_chip.dart';
import '../widgets/sync_button.dart';
import 'business_picker_screen.dart';
import 'invoice_detail_screen.dart';
import 'invoice_form_screen.dart';
import 'issuer_settings_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';

enum _Filter { all, pending, overdue, paid, voided }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _invoiceRepo = InvoiceRepository();
  final _issuerRepo = IssuerRepository();

  List<Invoice>? _invoices;
  Issuer _issuer = const Issuer();
  _Filter _filter = _Filter.all;

  AuthService get _auth => AuthService.instance;
  SyncService get _sync => SyncService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sync.dataVersion.addListener(_reload);
    _sync.addListener(_onSyncChanged);
    _auth.addListener(_onAuthChanged);
    _sync.start();
    _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sync.dataVersion.removeListener(_reload);
    _sync.removeListener(_onSyncChanged);
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync.sync();
  }

  Future<void> _reload() async {
    final invoices = await _invoiceRepo.list();
    final issuer = await _issuerRepo.get();
    if (!mounted) return;
    setState(() {
      _invoices = invoices;
      _issuer = issuer;
    });
  }

  /// Avisa de los cambios que el servidor no aceptó.
  void _onSyncChanged() {
    if (!mounted) return;
    final rejected = _sync.takeRejections();
    if (rejected.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.sync_problem),
        title: const Text('Algunos cambios no se aplicaron'),
        content: Text(
          'El servidor rechazó estos cambios porque otra persona del equipo '
          'modificó los mismos datos:\n\n• ${rejected.join('\n• ')}\n\n'
          'Ahora ves los datos actuales del servidor.',
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendido')),
        ],
      ),
    );
  }

  void _onAuthChanged() {
    if (!mounted || !_auth.sessionExpired) return;
    _sync.stop();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
          builder: (_) => const LoginScreen(
              message: 'Tu sesión ha caducado. Vuelve a iniciar sesión; '
                  'tus cambios pendientes se conservan.')),
      (_) => false,
    );
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _reload();
  }

  void _newInvoice() {
    if (!_issuer.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_auth.isAdmin
            ? 'Configura primero los datos del emisor: nombre e identificación fiscal.'
            : 'Un administrador debe configurar antes los datos del emisor.'),
        // Con botón, Flutter deja el aviso fijo salvo que se indique lo contrario.
        persist: false,
        duration: const Duration(seconds: 5),
        action: _auth.isAdmin
            ? SnackBarAction(
                label: 'Configurar',
                onPressed: () => _open(const IssuerSettingsScreen()))
            : null,
      ));
      return;
    }
    _open(InvoiceFormScreen(issuer: _issuer));
  }

  bool _matches(Invoice i) => switch (_filter) {
        _Filter.all => true,
        _Filter.pending => i.isOpen,
        _Filter.overdue => i.isOverdue,
        _Filter.paid => i.paid,
        _Filter.voided => i.isVoided,
      };

  @override
  Widget build(BuildContext context) {
    final all = _invoices;
    final visible = all?.where(_matches).toList();
    final session = _auth.session;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: session != null && session.hasSeveralBusinesses
            ? InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BusinessPickerScreen())),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: Text(session.businessName, overflow: TextOverflow.ellipsis)),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              )
            : Text(session?.businessName ?? 'Facturas'),
        actions: [
          const SyncButton(),
          if (session != null)
            Padding(
              padding: const EdgeInsets.only(right: 12, left: 4),
              child: Tooltip(
                message: 'Perfil',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _open(const ProfileScreen()),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(initialsOf(session.user.name),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onPrimaryContainer)),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newInvoice,
        icon: const Icon(Icons.add),
        label: const Text('Nueva factura'),
      ),
      body: all == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _sync.sync();
                await _reload();
              },
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!_issuer.isConfigured) ...[
                            _IssuerNotice(
                              isAdmin: _auth.isAdmin,
                              onOpen: () => _open(const IssuerSettingsScreen()),
                            ),
                            const SizedBox(height: 12),
                          ],
                          _Summary(invoices: all, currency: _issuer.currency),
                          const SizedBox(height: 16),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SegmentedButton<_Filter>(
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment(
                                    value: _Filter.all, label: Text('Todas')),
                                ButtonSegment(
                                    value: _Filter.pending,
                                    label: Text('Por cobrar')),
                                ButtonSegment(
                                    value: _Filter.overdue,
                                    label: Text('Vencidas')),
                                ButtonSegment(
                                    value: _Filter.paid,
                                    label: Text('Pagadas')),
                                ButtonSegment(
                                    value: _Filter.voided,
                                    label: Text('Anuladas')),
                              ],
                              selected: {_filter},
                              onSelectionChanged: (s) =>
                                  setState(() => _filter = s.first),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  if (visible!.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyState(
                        filtered: all.isNotEmpty,
                        onCreate: _newInvoice,
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      sliver: SliverToBoxAdapter(
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              for (var i = 0; i < visible.length; i++) ...[
                                if (i > 0) const Divider(indent: 16),
                                _InvoiceRow(
                                  invoice: visible[i],
                                  currency: _issuer.currency,
                                  onTap: () => _open(InvoiceDetailScreen(
                                      invoiceId: visible[i].id!)),
                                ),
                              ],
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
}

/// La cifra que importa: cuánto falta por cobrar, y de eso cuánto está vencido.
class _Summary extends StatelessWidget {
  const _Summary({required this.invoices, required this.currency});

  final List<Invoice> invoices;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AppColors.of(context);
    final open = invoices.where((i) => i.isOpen);
    final receivable = open.fold<double>(0, (s, i) => s + i.balance);
    final overdue =
        open.where((i) => i.isOverdue).fold<double>(0, (s, i) => s + i.balance);
    final now = DateTime.now();
    final collected = invoices
        .expand((i) => i.activePayments)
        .where((p) => p.date.year == now.year && p.date.month == now.month)
        .fold<double>(0, (s, p) => s + p.amount);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Por cobrar',
                style: theme.textTheme.bodyMedium?.copyWith(color: c.muted)),
            const SizedBox(height: 2),
            Text(
              fmtMoney(receivable, currency),
              style: theme.textTheme.headlineMedium
                  ?.copyWith(fontFeatures: AppTheme.tabular),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _Figure(
                    label: 'Vencido',
                    value: fmtMoney(overdue, currency),
                    color: overdue > 0 ? c.overdue : null,
                  ),
                ),
                Container(width: 1, height: 34, color: c.line),
                const SizedBox(width: 16),
                Expanded(
                  child: _Figure(
                    label: 'Cobrado este mes',
                    value: fmtMoney(collected, currency),
                    color: collected > 0 ? c.paid : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.of(context).muted)),
        const SizedBox(height: 2),
        Text(value,
            style: theme.textTheme.titleMedium
                ?.copyWith(color: color, fontFeatures: AppTheme.tabular)),
      ],
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow(
      {required this.invoice, required this.currency, required this.onTap});

  final Invoice invoice;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AppColors.of(context);
    final inv = invoice;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(inv.clientName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    inv.isDraft
                        ? 'Borrador, sin número aún'
                        : '${inv.number}   ${fmtDate(inv.issueDate)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: c.muted,
                      fontStyle: inv.isDraft ? FontStyle.italic : null,
                      fontFeatures: AppTheme.tabular,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                    fmtMoney(inv.isPartiallyPaid ? inv.balance : inv.total,
                        currency),
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFeatures: AppTheme.tabular,
                        color: inv.isVoided ? c.muted : null,
                        decoration: inv.isVoided ? TextDecoration.lineThrough : null)),
                const SizedBox(height: 4),
                StatusChip(invoice: inv, dense: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IssuerNotice extends StatelessWidget {
  const _IssuerNotice({required this.isAdmin, required this.onOpen});

  final bool isAdmin;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: ListTile(
        leading:
            Icon(Icons.storefront_outlined, color: scheme.onPrimaryContainer),
        title: Text(
          isAdmin
              ? 'Completa los datos del emisor para poder facturar'
              : 'Falta que un administrador complete los datos del emisor',
          style: TextStyle(color: scheme.onPrimaryContainer),
        ),
        trailing: isAdmin
            ? TextButton(onPressed: onOpen, child: const Text('Completar'))
            : null,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filtered, required this.onCreate});

  final bool filtered;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 96),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
              filtered
                  ? Icons.filter_alt_off_outlined
                  : Icons.receipt_long_outlined,
              size: 44,
              color: AppColors.of(context).muted),
          const SizedBox(height: 12),
          Text(
              filtered
                  ? 'Ninguna factura en este filtro'
                  : 'Aún no hay facturas',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            filtered
                ? 'Prueba con otro filtro para ver el resto.'
                : 'Crea la primera; se compartirá con todo el equipo al sincronizar.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: AppColors.of(context).muted),
          ),
          if (!filtered) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('Crear factura')),
          ],
        ],
      ),
    );
  }
}
