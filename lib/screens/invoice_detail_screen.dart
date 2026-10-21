import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../data/invoice_repository.dart';
import '../data/issuer_repository.dart';
import '../models/invoice.dart';
import '../models/issuer.dart';
import '../services/auth_service.dart';
import '../services/pdf_service.dart';
import '../services/sync_service.dart';
import '../utils/format.dart';
import '../widgets/payment_dialog.dart';
import '../widgets/status_chip.dart';
import 'invoice_form_screen.dart';
import 'pdf_preview_screen.dart';

class InvoiceDetailScreen extends StatefulWidget {
  final int invoiceId;

  const InvoiceDetailScreen({super.key, required this.invoiceId});

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  final _repo = InvoiceRepository();
  Invoice? _invoice;
  Issuer _issuer = const Issuer();

  @override
  void initState() {
    super.initState();
    // Recarga cuando llegan cambios del servidor (número asignado, pagos de
    // otros dispositivos...).
    SyncService.instance.dataVersion.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    SyncService.instance.dataVersion.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final inv = await _repo.get(widget.invoiceId);
    final issuer = await IssuerRepository().get();
    if (!mounted) return;
    if (inv == null) {
      if (_invoice != null) {
        _showMessage('Esta factura se eliminó en otro dispositivo.');
      }
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _invoice = inv;
      _issuer = issuer;
    });
  }

  String _money(double v) => fmtMoney(v, _issuer.currency);

  void _showMessage(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _registerPayment() async {
    final inv = _invoice!;
    final payment = await showPaymentDialog(context,
        balance: inv.balance, currency: _issuer.currency);
    if (payment == null) return;
    final int paymentId;
    try {
      paymentId = await _repo.addPayment(inv.id!, payment);
    } on PaymentException catch (e) {
      _showMessage(e.toString());
      return;
    }
    final fullyPaid = toCents(payment.amount) >= toCents(inv.balance);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(fullyPaid
          ? 'Pago registrado. La factura queda pagada.'
          : 'Abono de ${_money(payment.amount)} registrado.'),
      // Con botón, Flutter deja el aviso fijo salvo que se indique lo contrario.
      persist: false,
      duration: const Duration(seconds: 5),
      // El recibo se numera en el servidor: se busca el pago actualizado.
      action: SnackBarAction(
        label: 'Ver recibo',
        onPressed: () {
          final saved =
              _invoice?.payments.where((p) => p.id == paymentId).firstOrNull;
          if (saved != null) _openReceipt(saved);
        },
      ),
    ));
  }

  static const _pendingNumberMessage =
      'Aún no tiene número: se asigna al sincronizar con el servidor. '
      'Conéctate a internet y espera unos segundos.';

  void _openReceipt(Payment p) {
    if (p.isPending) {
      _showMessage('El recibo $_pendingNumberMessage');
      return;
    }
    final inv = _invoice!;
    final issuer = _issuer;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PdfPreviewScreen(
        title: 'Recibo ${p.receiptNumber}',
        fileName: PdfService.receiptFileName(p),
        builder: () => PdfService.buildReceipt(inv, p, issuer),
      ),
    ));
  }

  void _openInvoicePdf() {
    final inv = _invoice!;
    if (inv.isDraft) {
      _showMessage('La factura $_pendingNumberMessage');
      return;
    }
    final issuer = _issuer;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PdfPreviewScreen(
        title: 'Factura ${inv.displayNumber}',
        fileName: PdfService.fileName(inv),
        builder: () => PdfService.build(inv, issuer),
      ),
    ));
  }

  Future<void> _deletePayment(Payment p) async {
    final ok = await _confirm(
      'Eliminar pago',
      '¿Eliminar el pago de ${_money(p.amount)} del ${fmtDate(p.date)}? '
          'El saldo pendiente aumentará en ese importe.',
      'Eliminar',
    );
    if (!ok) return;
    await _repo.deletePayment(_invoice!.id!, p.id!);
    _load();
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => InvoiceFormScreen(issuer: _issuer, invoice: _invoice)));
    if (saved == true) _load();
  }

  Future<void> _delete() async {
    final ok = await _confirm(
        'Eliminar factura',
        '¿Seguro que quieres eliminar la factura ${_invoice!.displayNumber}?',
        'Eliminar');
    if (!ok) return;
    try {
      await _repo.delete(_invoice!.id!);
      if (mounted) Navigator.of(context).pop();
    } on InvoiceLockedException catch (e) {
      _showMessage(e.toString());
    }
  }

  Future<void> _share() async {
    final inv = _invoice!;
    if (inv.isDraft) {
      _showMessage('La factura $_pendingNumberMessage');
      return;
    }
    final bytes = await PdfService.build(inv, _issuer);
    await Printing.sharePdf(bytes: bytes, filename: PdfService.fileName(inv));
  }

  @override
  Widget build(BuildContext context) {
    final inv = _invoice;
    if (inv == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Factura ${inv.displayNumber}'),
        actions: [
          if (inv.isEditable) ...[
            IconButton(
                tooltip: 'Editar',
                icon: const Icon(Icons.edit),
                onPressed: _edit),
            IconButton(
                tooltip: 'Eliminar',
                icon: const Icon(Icons.delete_outline),
                onPressed: _delete),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              StatusChip(invoice: inv),
              const Spacer(),
              Text(_money(inv.total), style: theme.textTheme.headlineSmall),
            ],
          ),
          if (inv.isDraft)
            Card(
              margin: const EdgeInsets.only(top: 12),
              color: theme.colorScheme.secondaryContainer,
              child: const ListTile(
                leading: Icon(Icons.cloud_upload_outlined),
                title: Text('Borrador sin número'),
                subtitle:
                    Text('Recibirá su número al sincronizar con el servidor. '
                        'El PDF estará disponible entonces.'),
              ),
            ),
          if (!inv.isEditable)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                const Icon(Icons.lock_outline, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    inv.paid
                        ? 'Pagada el ${inv.paidDate != null ? fmtDate(inv.paidDate!) : '-'}. '
                            'Las facturas con pagos no se pueden editar.'
                        : 'Tiene abonos registrados, por eso no se puede editar. '
                            'Para corregirla, elimina antes los pagos.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ]),
            ),
          const SizedBox(height: 16),
          _section('Cliente', [
            Text(inv.clientName, style: theme.textTheme.titleMedium),
            for (final l in [
              inv.clientTaxId,
              inv.clientAddress,
              inv.clientEmail
            ])
              if (l.isNotEmpty) Text(l),
          ]),
          _section('Fechas', [
            Text('Emisión: ${fmtDate(inv.issueDate)}'),
            if (inv.dueDate != null)
              Text('Vencimiento: ${fmtDate(inv.dueDate!)}'),
          ]),
          _section('Conceptos', [
            for (final it in inv.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(it.description),
                          Text(
                              '${fmtQty(it.quantity)} × ${_money(it.unitPrice)}',
                              style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    Text(_money(it.total)),
                  ],
                ),
              ),
            const Divider(),
            _totalLine('Base imponible', _money(inv.subtotal)),
            _totalLine('IVA (${fmtQty(inv.taxRate)} %)', _money(inv.taxAmount)),
            _totalLine('Total', _money(inv.total), bold: true),
          ]),
          if (inv.notes.isNotEmpty)
            _section('Observaciones', [Text(inv.notes)]),
          _paymentsSection(inv),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Ver PDF'),
                  onPressed: _openInvoicePdf,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.share),
                  label: const Text('Compartir'),
                  onPressed: _share,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!inv.paid)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: Colors.green.shade700),
              icon: const Icon(Icons.payments_outlined),
              label: Text(inv.hasPayments
                  ? 'Registrar otro abono'
                  : 'Registrar pago o abono'),
              onPressed: _registerPayment,
            ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: Theme.of(context).colorScheme.primary)),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      );

  Widget _paymentsSection(Invoice inv) {
    final theme = Theme.of(context);
    final progress =
        inv.total > 0 ? (inv.paidAmount / inv.total).clamp(0.0, 1.0) : 0.0;
    return _section('Pagos', [
      _totalLine('Total factura', _money(inv.total)),
      _totalLine('Pagado', _money(inv.paidAmount)),
      _totalLine('Saldo pendiente', _money(inv.balance), bold: true),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: progress,
          minHeight: 8,
          color: Colors.green.shade600,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
      ),
      const SizedBox(height: 12),
      Text('Historial de pagos', style: theme.textTheme.labelLarge),
      if (inv.payments.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('Aún no se ha registrado ningún pago.',
              style: theme.textTheme.bodySmall),
        )
      else
        for (final p in inv.payments.reversed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.green.shade50,
              child: Icon(Icons.payments_outlined,
                  size: 18, color: Colors.green.shade700),
            ),
            title: Text(_money(p.amount),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text([
              '${p.receiptNumber ?? 'Pendiente de sincronizar'} · ${fmtDate(p.date)}',
              if (p.method.isNotEmpty) p.method,
              if (p.note.isNotEmpty) p.note,
            ].join(' · ')),
            onTap: () => _openReceipt(p),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Recibo PDF',
                  icon: const Icon(Icons.receipt_long, size: 20),
                  onPressed: () => _openReceipt(p),
                ),
                // Un pago aún no enviado lo puede quitar cualquiera; uno ya
                // sincronizado, solo un administrador.
                if (AuthService.instance.isAdmin || p.isPending)
                  IconButton(
                    tooltip: 'Eliminar pago',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => _deletePayment(p),
                  ),
              ],
            ),
          ),
    ]);
  }

  Widget _totalLine(String label, String value, {bool bold = false}) {
    final style = bold ? const TextStyle(fontWeight: FontWeight.bold) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}
