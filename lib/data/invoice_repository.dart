import 'package:sqflite/sqflite.dart';

import '../models/invoice.dart';
import '../utils/format.dart';
import '../utils/uuid.dart';
import 'database_helper.dart';
import 'outbox.dart';

class InvoiceLockedException implements Exception {
  @override
  String toString() =>
      'La factura tiene pagos registrados y no se puede modificar.';
}

class PaymentException implements Exception {
  final String message;
  PaymentException(this.message);

  @override
  String toString() => message;
}

/// Facturas y pagos en la base local. Cada cambio se guarda al momento y se
/// encola para el servidor; la sincronización lo envía cuando hay conexión.
class InvoiceRepository {
  InvoiceRepository([this._helper]);

  final DatabaseHelper? _helper;

  Future<Database> get _db => (_helper ?? DatabaseHelper.instance).database;

  /// Condición SQL: la factura no está pagada ni tiene abonos.
  static const _editable = 'paid = 0 AND voided_at IS NULL AND NOT EXISTS '
      '(SELECT 1 FROM payments p WHERE p.invoice_id = invoices.id AND p.voided_at IS NULL)';

  Future<List<Invoice>> list() async {
    final db = await _db;
    final rows =
        await db.query('invoices', orderBy: 'issue_date DESC, id DESC');
    final itemRows = await db.query('invoice_items', orderBy: 'position');
    final paymentRows = await db.query('payments', orderBy: 'date, id');

    final itemsByInvoice = <int, List<InvoiceItem>>{};
    for (final r in itemRows) {
      itemsByInvoice
          .putIfAbsent(r['invoice_id'] as int, () => [])
          .add(InvoiceItem.fromMap(r));
    }
    final paymentsByInvoice = <int, List<Payment>>{};
    for (final r in paymentRows) {
      paymentsByInvoice
          .putIfAbsent(r['invoice_id'] as int, () => [])
          .add(Payment.fromMap(r));
    }
    return [
      for (final r in rows)
        Invoice.fromMap(
          r,
          itemsByInvoice[r['id'] as int] ?? const [],
          paymentsByInvoice[r['id'] as int] ?? const [],
        ),
    ];
  }

  Future<Invoice?> get(int id) async {
    final db = await _db;
    return _get(db, id);
  }

  static Future<Invoice?> _get(DatabaseExecutor db, int id) async {
    final rows = await db.query('invoices', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final items = await db.query('invoice_items',
        where: 'invoice_id = ?', whereArgs: [id], orderBy: 'position');
    final payments = await db.query('payments',
        where: 'invoice_id = ?', whereArgs: [id], orderBy: 'date, id');
    return Invoice.fromMap(
      rows.first,
      items.map(InvoiceItem.fromMap).toList(),
      payments.map(Payment.fromMap).toList(),
    );
  }

  /// Crea la factura como borrador; el número lo asigna el servidor.
  Future<int> create(Invoice invoice) async {
    final db = await _db;
    final uuid = newUuid();
    final id = await db.transaction((txn) async {
      final id = await txn.insert('invoices', {
        ...invoice.editableFields(),
        'uuid': uuid,
        'paid': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
      await _insertItems(txn, id, invoice.items);
      await Outbox.add(
          txn, 'invoice_upsert', uuid, invoicePayload(invoice, uuid));
      return id;
    });
    Outbox.notifyChanged();
    return id;
  }

  /// Solo actualiza si la factura no tiene pagos registrados.
  Future<void> update(Invoice invoice) async {
    final db = await _db;
    await db.transaction((txn) async {
      final count = await txn.update('invoices', invoice.editableFields(),
          where: 'id = ? AND $_editable', whereArgs: [invoice.id]);
      if (count == 0) throw InvoiceLockedException();
      await txn.delete('invoice_items',
          where: 'invoice_id = ?', whereArgs: [invoice.id]);
      await _insertItems(txn, invoice.id!, invoice.items);
      final uuid = await _uuidOf(txn, invoice.id!);
      await Outbox.add(
          txn, 'invoice_upsert', uuid, invoicePayload(invoice, uuid));
    });
    Outbox.notifyChanged();
  }

  Future<void> delete(int id) async {
    final db = await _db;
    await db.transaction((txn) async {
      final row =
          (await txn.query('invoices', where: 'id = ?', whereArgs: [id]))
              .firstOrNull;
      if (row == null) return;
      final uuid = row['uuid'] as String;
      final count = await txn
          .delete('invoices', where: 'id = ? AND $_editable', whereArgs: [id]);
      if (count == 0) throw InvoiceLockedException();
      if (row['server_rev'] == null) {
        // Nunca llegó al servidor: basta con olvidar sus cambios pendientes.
        await Outbox.removeForInvoice(txn, uuid);
      } else {
        await Outbox.add(txn, 'invoice_delete', uuid, {'id': uuid});
      }
    });
    Outbox.notifyChanged();
  }

  /// Registra un pago o abono y devuelve su id. No admite importes mayores
  /// que el saldo (el servidor lo vuelve a comprobar al sincronizar).
  Future<int> addPayment(int invoiceId, Payment payment) async {
    final db = await _db;
    final id = await db.transaction((txn) async {
      final invoice = await _get(txn, invoiceId);
      if (invoice == null) throw PaymentException('La factura no existe.');
      final amount = toCents(payment.amount);
      if (amount <= 0) {
        throw PaymentException('El importe debe ser mayor que cero.');
      }
      if (amount > toCents(invoice.balance)) {
        throw PaymentException('El importe supera el saldo pendiente.');
      }
      final uuid = newUuid();
      final date = dateOnly(payment.date);
      final id = await txn.insert('payments', {
        'invoice_id': invoiceId,
        'uuid': uuid,
        'amount': amount / 100,
        'date': date.toIso8601String(),
        'method': payment.method,
        'note': payment.note,
        'created_at': DateTime.now().toIso8601String(),
      });
      await Outbox.add(
        txn,
        'payment_add',
        uuid,
        {
          'id': uuid,
          'invoice_id': invoice.uuid,
          'amount': amount / 100,
          'date': ymd(date),
          'method': payment.method,
          'note': payment.note,
        },
        invoiceUuid: invoice.uuid,
      );
      await syncPaidStatus(txn, invoiceId);
      return id;
    });
    Outbox.notifyChanged();
    return id;
  }

  /// Elimina un pago (p. ej. registrado por error) y recalcula el estado.
  Future<void> deletePayment(int invoiceId, int paymentId) async {
    final db = await _db;
    await db.transaction((txn) async {
      final row = (await txn.query('payments',
              where: 'id = ? AND invoice_id = ?',
              whereArgs: [paymentId, invoiceId]))
          .firstOrNull;
      if (row == null) return;
      final uuid = row['uuid'] as String;
      await txn.delete('payments', where: 'id = ?', whereArgs: [paymentId]);
      if (row['server_rev'] == null && await Outbox.hasPending(txn, uuid)) {
        await txn.delete('outbox', where: 'entity_uuid = ?', whereArgs: [uuid]);
      } else {
        await Outbox.add(txn, 'payment_delete', uuid, {'id': uuid},
            invoiceUuid: await _uuidOf(txn, invoiceId));
      }
      await syncPaidStatus(txn, invoiceId);
    });
    Outbox.notifyChanged();
  }

  /// Motivo de anulación válido (el servidor exige lo mismo).
  static String checkVoidReason(String reason) {
    final r = reason.trim();
    if (r.length < 3) {
      throw PaymentException('Escribe el motivo de la anulación (al menos 3 caracteres).');
    }
    return r.length > 255 ? r.substring(0, 255) : r;
  }

  /// Anula la factura y todos sus pagos vigentes. Se conservan en el
  /// historial con el motivo (solo administradores; el servidor lo comprueba).
  Future<void> voidInvoice(int invoiceId, String reason) async {
    final r = checkVoidReason(reason);
    final db = await _db;
    await db.transaction((txn) async {
      final invoice = await _get(txn, invoiceId);
      if (invoice == null || invoice.isVoided) return;
      final now = DateTime.now().toIso8601String();
      await txn.update(
        'invoices',
        {'voided_at': now, 'void_reason': r, 'paid': 0, 'paid_date': null},
        where: 'id = ?',
        whereArgs: [invoiceId],
      );
      var paymentReason = 'Anulación de la factura ${invoice.displayNumber}: $r';
      if (paymentReason.length > 255) paymentReason = paymentReason.substring(0, 255);
      await txn.update('payments', {'voided_at': now, 'void_reason': paymentReason},
          where: 'invoice_id = ? AND voided_at IS NULL', whereArgs: [invoiceId]);
      await Outbox.add(txn, 'invoice_void', invoice.uuid!, {'id': invoice.uuid, 'reason': r},
          invoiceUuid: invoice.uuid);
    });
    Outbox.notifyChanged();
  }

  /// Anula un pago: deja de contar y el saldo vuelve a subir. Si el pago aún
  /// no había llegado al servidor, simplemente se quita.
  Future<void> voidPayment(int invoiceId, int paymentId, String reason) async {
    final r = checkVoidReason(reason);
    final db = await _db;
    await db.transaction((txn) async {
      final row = (await txn.query('payments',
              where: 'id = ? AND invoice_id = ?', whereArgs: [paymentId, invoiceId]))
          .firstOrNull;
      if (row == null || row['voided_at'] != null) return;
      final uuid = row['uuid'] as String;
      if (row['server_rev'] == null && await Outbox.hasPending(txn, uuid)) {
        await txn.delete('payments', where: 'id = ?', whereArgs: [paymentId]);
        await txn.delete('outbox', where: 'entity_uuid = ?', whereArgs: [uuid]);
      } else {
        await txn.update(
          'payments',
          {'voided_at': DateTime.now().toIso8601String(), 'void_reason': r},
          where: 'id = ?',
          whereArgs: [paymentId],
        );
        await Outbox.add(txn, 'payment_void', uuid, {'id': uuid, 'reason': r},
            invoiceUuid: await _uuidOf(txn, invoiceId));
      }
      await syncPaidStatus(txn, invoiceId);
    });
    Outbox.notifyChanged();
  }

  // ------------------------------------------------- datos del servidor

  /// Aplica una factura recibida del servidor (alta, cambio o borrado).
  /// Si en el dispositivo hay cambios sin enviar de esa factura, se respetan.
  static Future<void> applyServerInvoice(
      DatabaseExecutor db, Map<String, Object?> j) async {
    final uuid = j['id'] as String;
    if (await Outbox.hasPending(db, uuid,
        types: ['invoice_upsert', 'invoice_delete', 'invoice_void'])) {
      return;
    }
    final local =
        (await db.query('invoices', where: 'uuid = ?', whereArgs: [uuid]))
            .firstOrNull;
    if (j['deleted'] == true) {
      if (local != null) {
        await db.delete('invoices', where: 'id = ?', whereArgs: [local['id']]);
      }
      return;
    }
    final fields = {
      'uuid': uuid,
      'number': j['number'],
      'issue_date': _serverDate(j['issue_date'])!.toIso8601String(),
      'due_date': _serverDate(j['due_date'])?.toIso8601String(),
      'client_name': j['client_name'],
      'client_tax_id': j['client_tax_id'],
      'client_address': j['client_address'],
      'client_email': j['client_email'],
      'tax_rate': (j['tax_rate'] as num).toDouble(),
      'notes': j['notes'],
      'voided_at': _serverDateTime(j['voided_at']),
      'void_reason': j['void_reason'],
      'server_rev': j['rev'],
    };
    final int id;
    if (local == null) {
      id = await db.insert('invoices', {
        ...fields,
        'paid': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
    } else {
      id = local['id'] as int;
      await db.update('invoices', fields, where: 'id = ?', whereArgs: [id]);
      await db
          .delete('invoice_items', where: 'invoice_id = ?', whereArgs: [id]);
    }
    final items = (j['items'] as List).cast<Map<String, Object?>>();
    for (var i = 0; i < items.length; i++) {
      await db.insert('invoice_items', {
        'invoice_id': id,
        'description': items[i]['description'],
        'quantity': (items[i]['quantity'] as num).toDouble(),
        'unit_price': (items[i]['unit_price'] as num).toDouble(),
        'position': i,
      });
    }
    await syncPaidStatus(db, id);
  }

  /// Aplica un pago recibido del servidor.
  static Future<void> applyServerPayment(
      DatabaseExecutor db, Map<String, Object?> j) async {
    final uuid = j['id'] as String;
    if (await Outbox.hasPending(db, uuid)) return;
    final invoice = (await db
            .query('invoices', where: 'uuid = ?', whereArgs: [j['invoice_id']]))
        .firstOrNull;
    final local =
        (await db.query('payments', where: 'uuid = ?', whereArgs: [uuid]))
            .firstOrNull;
    if (j['deleted'] == true || invoice == null) {
      if (local != null) {
        await db.delete('payments', where: 'id = ?', whereArgs: [local['id']]);
        await syncPaidStatus(db, local['invoice_id'] as int);
      }
      return;
    }
    final fields = {
      'invoice_id': invoice['id'],
      'uuid': uuid,
      'receipt_number': j['receipt_number'],
      'amount': (j['amount'] as num).toDouble(),
      'date': _serverDate(j['date'])!.toIso8601String(),
      'method': j['method'],
      'note': j['note'],
      'voided_at': _serverDateTime(j['voided_at']),
      'void_reason': j['void_reason'],
      'server_rev': j['rev'],
    };
    if (local == null) {
      await db.insert('payments',
          {...fields, 'created_at': DateTime.now().toIso8601String()});
    } else {
      await db.update('payments', fields,
          where: 'id = ?', whereArgs: [local['id']]);
    }
    await syncPaidStatus(db, invoice['id'] as int);
  }

  /// La factura queda pagada cuando los pagos cubren el total; la fecha de
  /// pago es la del último abono (misma regla que el servidor).
  static Future<void> syncPaidStatus(DatabaseExecutor db, int invoiceId) async {
    final invoice = await _get(db, invoiceId);
    if (invoice == null) return;
    final fullyPaid = !invoice.isVoided &&
        invoice.hasPayments &&
        toCents(invoice.paidAmount) >= toCents(invoice.total);
    final lastDate = invoice.activePayments
        .map((p) => dateOnly(p.date))
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    await db.update(
      'invoices',
      {
        'paid': fullyPaid ? 1 : 0,
        'paid_date': fullyPaid ? lastDate!.toIso8601String() : null,
      },
      where: 'id = ?',
      whereArgs: [invoiceId],
    );
  }

  // ------------------------------------- datos previos a la sincronización

  /// Facturas creadas antes de conectar la app al servidor (nunca enviadas).
  Future<int> countLocalOnly() async {
    final db = await _db;
    return Sqflite.firstIntValue(await db.rawQuery('''
          SELECT COUNT(*) FROM invoices
          WHERE server_rev IS NULL
            AND NOT EXISTS (SELECT 1 FROM outbox o WHERE o.entity_uuid = invoices.uuid)''')) ??
        0;
  }

  /// Encola las facturas y pagos anteriores para subirlos, conservando sus
  /// números (el servidor los respeta si están libres).
  Future<void> enqueueLocalOnly() async {
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.rawQuery('''
          SELECT id FROM invoices
          WHERE server_rev IS NULL
            AND NOT EXISTS (SELECT 1 FROM outbox o WHERE o.entity_uuid = invoices.uuid)
          ORDER BY issue_date, id''');
      for (final r in rows) {
        final invoice = (await _get(txn, r['id'] as int))!;
        await Outbox.add(txn, 'invoice_upsert', invoice.uuid!, {
          ...invoicePayload(invoice, invoice.uuid!),
          if (invoice.number != null) 'legacy_number': invoice.number,
        });
        for (final p in invoice.payments) {
          await Outbox.add(
            txn,
            'payment_add',
            p.uuid!,
            {
              'id': p.uuid,
              'invoice_id': invoice.uuid,
              'amount': p.amount,
              'date': ymd(p.date),
              'method': p.method,
              'note': p.note,
              // Antes el recibo se numeraba con el id local del pago.
              'legacy_receipt_number': 'RC-${p.id.toString().padLeft(4, '0')}',
            },
            invoiceUuid: invoice.uuid,
          );
        }
      }
    });
    Outbox.notifyChanged();
  }

  /// Descarta las facturas anteriores a la sincronización (no se suben).
  Future<void> discardLocalOnly() async {
    final db = await _db;
    await db.delete('invoices', where: '''
        server_rev IS NULL
        AND NOT EXISTS (SELECT 1 FROM outbox o WHERE o.entity_uuid = invoices.uuid)''');
  }

  /// Borra todos los datos locales (al cerrar sesión o cambiar de negocio).
  Future<void> wipeAll() async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('outbox');
      await txn.delete('payments');
      await txn.delete('invoice_items');
      await txn.delete('invoices');
      await txn.delete('issuer');
    });
  }

  // ------------------------------------------------------------- comunes

  static Map<String, Object?> invoicePayload(Invoice invoice, String uuid) => {
        'id': uuid,
        'issue_date': ymd(invoice.issueDate),
        'due_date': invoice.dueDate == null ? null : ymd(invoice.dueDate!),
        'client_name': invoice.clientName,
        'client_tax_id': invoice.clientTaxId,
        'client_address': invoice.clientAddress,
        'client_email': invoice.clientEmail,
        'tax_rate': invoice.taxRate,
        'notes': invoice.notes,
        'items': [for (final i in invoice.items) i.toJson()],
      };

  /// Fecha y hora del servidor ("2026-10-24 22:07:37") en formato ISO.
  static String? _serverDateTime(Object? v) =>
      v == null ? null : DateTime.parse(v as String).toIso8601String();

  static DateTime? _serverDate(Object? v) =>
      v == null ? null : dateOnly(DateTime.parse(v as String));

  static Future<String> _uuidOf(DatabaseExecutor db, int invoiceId) async =>
      (await db.query('invoices',
              columns: ['uuid'], where: 'id = ?', whereArgs: [invoiceId]))
          .first['uuid'] as String;

  static Future<void> _insertItems(
      DatabaseExecutor db, int invoiceId, List<InvoiceItem> items) async {
    for (var i = 0; i < items.length; i++) {
      await db.insert('invoice_items', items[i].toMap(invoiceId, i));
    }
  }
}
