import 'dart:io';

import 'package:facturas_app/data/database_helper.dart';
import 'package:facturas_app/data/invoice_repository.dart';
import 'package:facturas_app/data/outbox.dart';
import 'package:facturas_app/models/invoice.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Base de datos local: trabajo sin conexión y cola de cambios.
void main() {
  late DatabaseHelper helper;
  late InvoiceRepository repo;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('facturas_test');
    helper = DatabaseHelper(path: join(dir.path, 'local.db'));
    repo = InvoiceRepository(helper);
  });

  tearDown(() => helper.close());

  Invoice sample() => Invoice(
        issueDate: DateTime(2026, 10, 1),
        clientName: 'Cliente',
        taxRate: 19,
        items: const [InvoiceItem(description: 'Servicio', quantity: 1, unitPrice: 100)],
      );

  Future<List<OutboxOp>> queue() async => Outbox.pending(await helper.database);

  test('una factura nueva es un borrador sin número y queda en la cola', () async {
    final id = await repo.create(sample());
    final inv = (await repo.get(id))!;
    expect(inv.isDraft, isTrue);
    expect(inv.uuid, isNotNull);
    final ops = await queue();
    expect(ops.single.type, 'invoice_upsert');
    expect(ops.single.data['issue_date'], '2026-10-01');
    expect(ops.single.data['items'], hasLength(1));
  });

  test('editar sin conexión actualiza el mismo cambio pendiente', () async {
    final id = await repo.create(sample());
    final inv = (await repo.get(id))!;
    await repo.update(Invoice(
      id: id,
      uuid: inv.uuid,
      issueDate: inv.issueDate,
      clientName: 'Cliente editado',
      taxRate: 19,
      items: inv.items,
    ));
    final ops = await queue();
    expect(ops, hasLength(1));
    expect(ops.single.data['client_name'], 'Cliente editado');
  });

  test('pagos: cola, estado y límite del saldo', () async {
    final id = await repo.create(sample());
    await repo.addPayment(id, Payment(amount: 50, date: DateTime(2026, 10, 2)));
    expect(() => repo.addPayment(id, Payment(amount: 70, date: DateTime(2026, 10, 3))),
        throwsA(isA<PaymentException>()));
    await repo.addPayment(id, Payment(amount: 69, date: DateTime(2026, 10, 5)));
    final inv = (await repo.get(id))!;
    expect(inv.paid, isTrue);
    expect(inv.payments.every((p) => p.isPending), isTrue);
    expect((await queue()).map((o) => o.type),
        ['invoice_upsert', 'payment_add', 'payment_add']);
  });

  test('borrar un borrador nunca enviado limpia su cola', () async {
    final id = await repo.create(sample());
    await repo.delete(id);
    expect(await repo.get(id), isNull);
    expect(await queue(), isEmpty);
  });

  test('aplica lo que llega del servidor: número, pagos y borrado', () async {
    final id = await repo.create(sample());
    final uuid = (await repo.get(id))!.uuid!;
    final db = await helper.database;
    // Mientras haya cambios propios sin enviar, no se pisan.
    await InvoiceRepository.applyServerInvoice(db, _serverInvoice(uuid, 'F-0009'));
    expect((await repo.get(id))!.number, isNull);

    await Outbox.remove(db, (await queue()).single.id);
    await InvoiceRepository.applyServerInvoice(db, _serverInvoice(uuid, 'F-0009'));
    expect((await repo.get(id))!.number, 'F-0009');

    await InvoiceRepository.applyServerPayment(db, {
      'id': '11111111-1111-4111-8111-111111111111',
      'invoice_id': uuid,
      'receipt_number': 'RC-0004',
      'amount': 119.0,
      'date': '2026-10-06',
      'method': 'Transferencia',
      'note': '',
      'deleted': false,
      'rev': 5,
    });
    final paid = (await repo.get(id))!;
    expect(paid.paid, isTrue);
    expect(paid.payments.single.receiptNumber, 'RC-0004');
    expect(paid.paidDate, DateTime(2026, 10, 6));

    await InvoiceRepository.applyServerInvoice(db, {..._serverInvoice(uuid, 'F-0009'), 'deleted': true});
    expect(await repo.get(id), isNull);
  });

  test('facturas anteriores al servidor: se cuentan y se encolan con su número', () async {
    final db = await helper.database;
    final id = await db.insert('invoices', {
      'uuid': '22222222-2222-4222-8222-222222222222',
      'number': 'F-0003',
      'issue_date': DateTime(2026, 9, 1).toIso8601String(),
      'client_name': 'Antiguo',
      'tax_rate': 0,
      'paid': 0,
      'created_at': DateTime(2026, 9, 1).toIso8601String(),
    });
    await db.insert('invoice_items',
        {'invoice_id': id, 'description': 'X', 'quantity': 1, 'unit_price': 10, 'position': 0});
    expect(await repo.countLocalOnly(), 1);
    await repo.enqueueLocalOnly();
    expect(await repo.countLocalOnly(), 0);
    expect((await queue()).single.data['legacy_number'], 'F-0003');
  });
}

Map<String, Object?> _serverInvoice(String uuid, String number) => {
      'id': uuid,
      'number': number,
      'issue_date': '2026-10-01',
      'due_date': null,
      'client_name': 'Cliente',
      'client_tax_id': '',
      'client_address': '',
      'client_email': '',
      'tax_rate': 19.0,
      'notes': '',
      'items': [
        {'description': 'Servicio', 'quantity': 1.0, 'unit_price': 100.0}
      ],
      'paid': false,
      'paid_date': null,
      'deleted': false,
      'rev': 3,
    };
