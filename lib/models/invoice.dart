class InvoiceItem {
  final String description;
  final double quantity;
  final double unitPrice;

  const InvoiceItem({
    required this.description,
    required this.quantity,
    required this.unitPrice,
  });

  double get total => quantity * unitPrice;

  factory InvoiceItem.fromMap(Map<String, Object?> m) => InvoiceItem(
        description: m['description'] as String,
        quantity: (m['quantity'] as num).toDouble(),
        unitPrice: (m['unit_price'] as num).toDouble(),
      );

  Map<String, Object?> toMap(int invoiceId, int position) => {
        'invoice_id': invoiceId,
        'description': description,
        'quantity': quantity,
        'unit_price': unitPrice,
        'position': position,
      };

  Map<String, Object?> toJson() => {
        'description': description,
        'quantity': quantity,
        'unit_price': unitPrice,
      };
}

class Payment {
  final int? id;

  /// Identificador compartido con el servidor (se genera en el dispositivo).
  final String? uuid;
  final double amount;
  final DateTime date;
  final String method;
  final String note;

  /// Número de recibo (RC-0001). Lo asigna el servidor al sincronizar.
  final String? receiptNumber;

  /// Anulado: se conserva en el historial pero no cuenta en el saldo.
  final DateTime? voidedAt;
  final String voidReason;

  const Payment({
    this.id,
    this.uuid,
    required this.amount,
    required this.date,
    this.method = '',
    this.note = '',
    this.receiptNumber,
    this.voidedAt,
    this.voidReason = '',
  });

  bool get isVoided => voidedAt != null;

  static const methods = ['Efectivo', 'Transferencia', 'Tarjeta', 'Otro'];

  /// Aún no ha llegado al servidor: no tiene número de recibo.
  bool get isPending => receiptNumber == null;

  factory Payment.fromMap(Map<String, Object?> m) => Payment(
        id: m['id'] as int,
        uuid: m['uuid'] as String?,
        amount: (m['amount'] as num).toDouble(),
        date: DateTime.parse(m['date'] as String),
        method: m['method'] as String? ?? '',
        note: m['note'] as String? ?? '',
        receiptNumber: m['receipt_number'] as String?,
        voidedAt: m['voided_at'] == null ? null : DateTime.parse(m['voided_at'] as String),
        voidReason: m['void_reason'] as String? ?? '',
      );
}

/// Importes en céntimos para comparar sin errores de coma flotante.
int toCents(double v) => (v * 100).round();

class Invoice {
  final int? id;

  /// Identificador compartido con el servidor (se genera en el dispositivo).
  final String? uuid;

  /// Número (F-0001). Null mientras es un borrador sin sincronizar.
  final String? number;
  final DateTime issueDate;
  final DateTime? dueDate;
  final String clientName;
  final String clientTaxId;
  final String clientAddress;
  final String clientEmail;
  final double taxRate;
  final String notes;
  final bool paid;
  final DateTime? paidDate;
  final List<InvoiceItem> items;

  /// Todos los pagos, también los anulados (para el historial).
  final List<Payment> payments;

  /// Anulada: se conserva en el historial con el motivo; no cuenta como deuda.
  final DateTime? voidedAt;
  final String voidReason;

  const Invoice({
    this.id,
    this.uuid,
    this.number,
    required this.issueDate,
    this.dueDate,
    required this.clientName,
    this.clientTaxId = '',
    this.clientAddress = '',
    this.clientEmail = '',
    required this.taxRate,
    this.notes = '',
    this.paid = false,
    this.paidDate,
    this.items = const [],
    this.payments = const [],
    this.voidedAt,
    this.voidReason = '',
  });

  bool get isVoided => voidedAt != null;

  /// Pagos vigentes (sin los anulados).
  List<Payment> get activePayments => payments.where((p) => !p.isVoided).toList();

  bool get isDraft => number == null;
  String get displayNumber => number ?? 'Borrador';

  double get subtotal => items.fold(0, (sum, i) => sum + i.total);
  double get taxAmount => subtotal * taxRate / 100;
  double get total => subtotal + taxAmount;

  double get paidAmount => activePayments.fold(0, (sum, p) => sum + p.amount);

  /// Saldo pendiente (nunca negativo).
  double get balance {
    final cents = toCents(total) - toCents(paidAmount);
    return cents > 0 ? cents / 100 : 0;
  }

  /// ¿Tiene pagos vigentes? (los anulados no cuentan)
  bool get hasPayments => activePayments.isNotEmpty;
  bool get isPartiallyPaid => !paid && !isVoided && hasPayments;

  /// Solo se edita si no está anulada ni tiene pagos vigentes.
  bool get isEditable => !isVoided && !paid && !hasPayments;

  /// Pendiente de cobro (cuenta en "Por cobrar").
  bool get isOpen => !paid && !isVoided;

  bool get isOverdue {
    if (paid || isVoided || dueDate == null) return false;
    final now = DateTime.now();
    return dueDate!.isBefore(DateTime(now.year, now.month, now.day));
  }

  factory Invoice.fromMap(Map<String, Object?> m, List<InvoiceItem> items,
          [List<Payment> payments = const []]) =>
      Invoice(
        id: m['id'] as int,
        uuid: m['uuid'] as String?,
        number: m['number'] as String?,
        issueDate: DateTime.parse(m['issue_date'] as String),
        dueDate: _parseDate(m['due_date']),
        clientName: m['client_name'] as String,
        clientTaxId: m['client_tax_id'] as String? ?? '',
        clientAddress: m['client_address'] as String? ?? '',
        clientEmail: m['client_email'] as String? ?? '',
        taxRate: (m['tax_rate'] as num).toDouble(),
        notes: m['notes'] as String? ?? '',
        paid: (m['paid'] as int) == 1,
        paidDate: _parseDate(m['paid_date']),
        items: items,
        payments: payments,
        voidedAt: _parseDate(m['voided_at']),
        voidReason: m['void_reason'] as String? ?? '',
      );

  /// Campos que se pueden modificar mientras la factura no tiene pagos.
  Map<String, Object?> editableFields() => {
        'issue_date': issueDate.toIso8601String(),
        'due_date': dueDate?.toIso8601String(),
        'client_name': clientName,
        'client_tax_id': clientTaxId,
        'client_address': clientAddress,
        'client_email': clientEmail,
        'tax_rate': taxRate,
        'notes': notes,
      };

  static DateTime? _parseDate(Object? v) =>
      v == null ? null : DateTime.parse(v as String);
}
