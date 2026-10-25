import 'dart:io';

import 'package:facturas_app/data/database_helper.dart';
import 'package:facturas_app/data/invoice_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Una base de datos antigua (versión 2: sin abonos ni sincronización) se
/// actualiza a la versión actual sin perder nada.
void main() {
  test('migra de la v2 a la actual conservando facturas, conceptos y pagos', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('facturas_migracion');
    final path = join(dir.path, 'facturas.db');

    final v2 = await databaseFactory.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 2,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, _) async {
            await db.execute('CREATE TABLE users(id INTEGER PRIMARY KEY, username TEXT, password_hash TEXT, salt TEXT)');
            await db.execute('''CREATE TABLE issuer(id INTEGER PRIMARY KEY CHECK (id = 1), name TEXT,
                tax_id TEXT, address TEXT, city TEXT, phone TEXT, email TEXT, bank_account TEXT,
                invoice_prefix TEXT, next_number INTEGER, default_tax_rate REAL, currency TEXT, logo BLOB)''');
            await db.execute('''CREATE TABLE invoices(id INTEGER PRIMARY KEY AUTOINCREMENT,
                number TEXT NOT NULL UNIQUE, issue_date TEXT NOT NULL, due_date TEXT,
                client_name TEXT NOT NULL, client_tax_id TEXT, client_address TEXT, client_email TEXT,
                tax_rate REAL NOT NULL, notes TEXT, paid INTEGER NOT NULL DEFAULT 0, paid_date TEXT,
                created_at TEXT NOT NULL)''');
            await db.execute('''CREATE TABLE invoice_items(id INTEGER PRIMARY KEY AUTOINCREMENT,
                invoice_id INTEGER NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
                description TEXT NOT NULL, quantity REAL NOT NULL, unit_price REAL NOT NULL,
                position INTEGER NOT NULL)''');
          },
        ));
    await v2.insert('issuer', {'id': 1, 'name': 'Mi Empresa', 'tax_id': '900', 'next_number': 3});
    for (final (id, paid) in [(1, 1), (2, 0)]) {
      await v2.insert('invoices', {
        'id': id,
        'number': 'F-000$id',
        'issue_date': '2026-09-01T00:00:00.000',
        'client_name': 'C$id',
        'tax_rate': 21,
        'paid': paid,
        'paid_date': paid == 1 ? '2026-09-10T00:00:00.000' : null,
        'created_at': '2026-09-01',
      });
      await v2.insert('invoice_items',
          {'invoice_id': id, 'description': 'X', 'quantity': 2, 'unit_price': 50, 'position': 0});
    }
    await v2.close();

    final helper = DatabaseHelper(path: path);
    final repo = InvoiceRepository(helper);
    final db = await helper.database;

    final invoices = await repo.list();
    expect(invoices, hasLength(2));
    final paid = invoices.firstWhere((i) => i.number == 'F-0001');
    final pending = invoices.firstWhere((i) => i.number == 'F-0002');

    // Los conceptos siguen ahí: reconstruir la tabla no los borró en cascada.
    expect(paid.items, hasLength(1));
    expect(pending.items, hasLength(1));

    // La factura pagada recibió su pago por el total (v3) con identificador (v4).
    expect(paid.paid, isTrue);
    expect(paid.payments.single.amount, 121);
    expect(paid.payments.single.uuid, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(pending.payments, isEmpty);
    expect(paid.uuid, isNot(pending.uuid));

    // Pendientes de subir al servidor al iniciar sesión; la cola existe y está vacía.
    expect(await repo.countLocalOnly(), 2);
    expect(await db.query('outbox'), isEmpty);
    // El login local ya no existe.
    expect(await db.query('sqlite_master', where: "name = 'users'"), isEmpty);
    // Campos de anulación (versión 5).
    final columns = (await db.rawQuery('PRAGMA table_info(payments)')).map((c) => c['name']);
    expect(columns, containsAll(['voided_at', 'void_reason']));
    expect(paid.isVoided, isFalse);

    // Las claves foráneas vuelven a estar activas tras migrar.
    expect((await db.rawQuery('PRAGMA foreign_keys')).first.values.first, 1);

    await helper.close();
  });
}
