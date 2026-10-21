import 'package:flutter/material.dart';

import '../models/invoice.dart';
import '../utils/format.dart';

/// Pide los datos de un pago o abono. Devuelve null si se cancela.
Future<Payment?> showPaymentDialog(
  BuildContext context, {
  required double balance,
  required String currency,
}) {
  return showDialog<Payment>(
    context: context,
    builder: (_) => _PaymentDialog(balance: balance, currency: currency),
  );
}

class _PaymentDialog extends StatefulWidget {
  final double balance;
  final String currency;

  const _PaymentDialog({required this.balance, required this.currency});

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(
      text: widget.balance.toStringAsFixed(2).replaceAll('.', ','));
  final _note = TextEditingController();
  DateTime _date = dateOnly(DateTime.now());
  String _method = Payment.methods.first;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _isPartial {
    final v = parseNum(_amount.text);
    return v != null && toCents(v) < toCents(widget.balance);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  String? _validateAmount(String? v) {
    final n = parseNum(v ?? '');
    if (n == null) return 'Importe no válido';
    if (toCents(n) <= 0) return 'Debe ser mayor que cero';
    if (toCents(n) > toCents(widget.balance)) {
      return 'Máximo ${fmtMoney(widget.balance, widget.currency)}';
    }
    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(Payment(
      amount: parseNum(_amount.text)!,
      date: _date,
      method: _method,
      note: _note.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar pago'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Saldo pendiente: ${fmtMoney(widget.balance, widget.currency)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amount,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Importe',
                  prefixText: '${widget.currency} ',
                  helperText:
                      _isPartial ? 'Abono parcial' : 'Pago del saldo completo',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: _validateAmount,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Fecha del pago',
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(fmtDate(_date)),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _method,
                decoration: const InputDecoration(labelText: 'Forma de pago'),
                items: [
                  for (final m in Payment.methods)
                    DropdownMenuItem(value: m, child: Text(m)),
                ],
                onChanged: (v) => setState(() => _method = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _note,
                decoration: const InputDecoration(
                    labelText: 'Nota (opcional)',
                    hintText: 'Ej.: nº de transferencia'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar')),
        FilledButton(onPressed: _submit, child: const Text('Registrar')),
      ],
    );
  }
}
