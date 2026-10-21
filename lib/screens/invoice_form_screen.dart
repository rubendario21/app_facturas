import 'package:flutter/material.dart';

import '../data/invoice_repository.dart';
import '../models/invoice.dart';
import '../models/issuer.dart';
import '../utils/format.dart';

/// Alta y edición de facturas. Solo se abre en modo edición si no está pagada.
class InvoiceFormScreen extends StatefulWidget {
  final Issuer issuer;
  final Invoice? invoice;

  const InvoiceFormScreen({super.key, required this.issuer, this.invoice});

  @override
  State<InvoiceFormScreen> createState() => _InvoiceFormScreenState();
}

class _ItemFields {
  final description = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final price = TextEditingController();

  _ItemFields();

  _ItemFields.from(InvoiceItem item) {
    description.text = item.description;
    quantity.text = fmtQty(item.quantity);
    price.text = item.unitPrice.toStringAsFixed(2).replaceAll('.', ',');
  }

  double get total =>
      (parseNum(quantity.text) ?? 0) * (parseNum(price.text) ?? 0);

  InvoiceItem toItem() => InvoiceItem(
        description: description.text.trim(),
        quantity: parseNum(quantity.text) ?? 0,
        unitPrice: parseNum(price.text) ?? 0,
      );

  void dispose() {
    description.dispose();
    quantity.dispose();
    price.dispose();
  }
}

class _InvoiceFormScreenState extends State<InvoiceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _clientName = TextEditingController();
  final _clientTaxId = TextEditingController();
  final _clientAddress = TextEditingController();
  final _clientEmail = TextEditingController();
  final _taxRate = TextEditingController();
  final _notes = TextEditingController();
  final List<_ItemFields> _items = [];

  late DateTime _issueDate;
  DateTime? _dueDate;
  bool _saving = false;

  bool get _isEdit => widget.invoice != null;

  @override
  void initState() {
    super.initState();
    final inv = widget.invoice;
    if (inv != null) {
      _clientName.text = inv.clientName;
      _clientTaxId.text = inv.clientTaxId;
      _clientAddress.text = inv.clientAddress;
      _clientEmail.text = inv.clientEmail;
      _taxRate.text = fmtQty(inv.taxRate);
      _notes.text = inv.notes;
      _issueDate = inv.issueDate;
      _dueDate = inv.dueDate;
      _items.addAll(inv.items.map(_ItemFields.from));
    } else {
      _taxRate.text = fmtQty(widget.issuer.defaultTaxRate);
      _issueDate = dateOnly(DateTime.now());
      _dueDate = _issueDate.add(const Duration(days: 30));
    }
    if (_items.isEmpty) _items.add(_ItemFields());
  }

  @override
  void dispose() {
    for (final c in [
      _clientName,
      _clientTaxId,
      _clientAddress,
      _clientEmail,
      _taxRate,
      _notes,
    ]) {
      c.dispose();
    }
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  double get _subtotal => _items.fold(0, (s, i) => s + i.total);
  double get _taxAmount => _subtotal * (parseNum(_taxRate.text) ?? 0) / 100;

  Future<void> _pickDate({required bool due}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (due ? _dueDate : _issueDate) ?? _issueDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (due) {
        _dueDate = picked;
      } else {
        _issueDate = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dueDate != null && _dueDate!.isBefore(_issueDate)) {
      _message('El vencimiento no puede ser anterior a la fecha de emisión');
      return;
    }
    setState(() => _saving = true);

    final invoice = Invoice(
      id: widget.invoice?.id,
      uuid: widget.invoice?.uuid,
      number: widget.invoice?.number,
      issueDate: _issueDate,
      dueDate: _dueDate,
      clientName: _clientName.text.trim(),
      clientTaxId: _clientTaxId.text.trim(),
      clientAddress: _clientAddress.text.trim(),
      clientEmail: _clientEmail.text.trim(),
      taxRate: parseNum(_taxRate.text) ?? 0,
      notes: _notes.text.trim(),
      items: _items.map((i) => i.toItem()).toList(),
    );

    final repo = InvoiceRepository();
    try {
      if (_isEdit) {
        await repo.update(invoice);
      } else {
        await repo.create(invoice);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on InvoiceLockedException catch (e) {
      _message(e.toString());
      setState(() => _saving = false);
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null;

  String? _number(String? v, {bool positive = false}) {
    final n = parseNum(v ?? '');
    if (n == null) return 'Número no válido';
    if (n < 0 || (positive && n == 0)) return 'Valor no válido';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    String money(double v) => fmtMoney(v, widget.issuer.currency);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit
            ? 'Editar ${widget.invoice!.displayNumber}'
            : 'Nueva factura'),
        actions: [
          IconButton(
            tooltip: 'Guardar',
            icon: const Icon(Icons.save),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Cliente', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            TextFormField(
              controller: _clientName,
              decoration:
                  const InputDecoration(labelText: 'Nombre o razón social *'),
              textCapitalization: TextCapitalization.words,
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _clientTaxId,
              decoration: const InputDecoration(
                  labelText: 'Identificación fiscal (NIF/CIF/RFC)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _clientAddress,
              decoration: const InputDecoration(labelText: 'Dirección'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _clientEmail,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 24),
            Text('Fechas', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'Emisión',
                    value: _issueDate,
                    onTap: () => _pickDate(due: false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateField(
                    label: 'Vencimiento',
                    value: _dueDate,
                    onTap: () => _pickDate(due: true),
                    onClear: () => setState(() => _dueDate = null),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                    child:
                        Text('Conceptos', style: theme.textTheme.titleMedium)),
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Añadir'),
                  onPressed: () => setState(() => _items.add(_ItemFields())),
                ),
              ],
            ),
            for (var i = 0; i < _items.length; i++) _buildItem(i, money),
            const SizedBox(height: 16),
            TextFormField(
              controller: _taxRate,
              decoration: const InputDecoration(
                  labelText: 'IVA / impuesto (%)', suffixText: '%'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: _number,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Observaciones'),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _totalRow('Base imponible', money(_subtotal)),
                    _totalRow('Impuesto', money(_taxAmount)),
                    const Divider(),
                    _totalRow('Total', money(_subtotal + _taxAmount),
                        bold: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save),
              label: Text(_isEdit ? 'Guardar cambios' : 'Crear factura'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(int index, String Function(double) money) {
    final item = _items[index];
    return Card(
      key: ObjectKey(item),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: item.description,
                    decoration:
                        const InputDecoration(labelText: 'Descripción *'),
                    validator: _required,
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar',
                  icon: const Icon(Icons.close),
                  onPressed:
                      _items.length == 1 ? null : () => _removeItem(index),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 80,
                    child: TextFormField(
                      controller: item.quantity,
                      decoration: const InputDecoration(labelText: 'Cant.'),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) => _number(v, positive: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: item.price,
                      decoration: InputDecoration(
                          labelText: 'Precio unit.',
                          prefixText: '${widget.issuer.currency} '),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: _number,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(money(item.total),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _removeItem(int index) {
    final removed = _items[index];
    setState(() => _items.removeAt(index));
    // Los campos siguen montados hasta el próximo frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  Widget _totalRow(String label, String value, {bool bold = false}) {
    final style = bold
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _DateField(
      {required this.label,
      required this.value,
      required this.onTap,
      this.onClear});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: onClear != null && value != null
              ? IconButton(icon: const Icon(Icons.clear), onPressed: onClear)
              : const Icon(Icons.calendar_today),
        ),
        child: Text(value == null ? 'Sin fecha' : fmtDate(value!)),
      ),
    );
  }
}
