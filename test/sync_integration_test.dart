@Tags(['servidor'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:facturas_app/data/database_helper.dart';
import 'package:facturas_app/data/invoice_repository.dart';
import 'package:facturas_app/data/issuer_repository.dart';
import 'package:facturas_app/models/invoice.dart';
import 'package:facturas_app/models/issuer.dart';
import 'package:facturas_app/services/auth_service.dart';
import 'package:facturas_app/services/session.dart';
import 'package:facturas_app/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Varios dispositivos sincronizando contra la API real, con una base de
/// datos VACÍA:
///
///   flutter test test/sync_integration_test.dart --dart-define=API_URL=http://127.0.0.1:8080
const apiUrl = String.fromEnvironment('API_URL');

/// Un dispositivo: una base local por negocio, sesión y sincronización.
class Device {
  Device(this.name, this.dir) {
    auth = AuthService(store: MemorySessionStore(), dbFor: dbFor);
    sync = SyncService(auth: auth);
  }

  final String name;
  final Directory dir;
  final _dbs = <int, DatabaseHelper>{};
  late final AuthService auth;
  late final SyncService sync;

  DatabaseHelper dbFor(int businessId) =>
      _dbs.putIfAbsent(businessId, () => DatabaseHelper(path: join(dir.path, '$name-b$businessId.db')));

  InvoiceRepository get invoices => InvoiceRepository(auth.db);
  IssuerRepository get issuer => IssuerRepository(auth.db);

  Future<Invoice> byNumber(String number) async =>
      (await invoices.list()).firstWhere((i) => i.number == number);
}

void main() {
  late Directory dir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('facturas_sync');
  });

  Invoice draft(String client, double price) => Invoice(
        issueDate: DateTime(2026, 10, 1),
        clientName: client,
        taxRate: 19,
        items: [InvoiceItem(description: 'Servicio', quantity: 1, unitPrice: price)],
      );

  test('dos dispositivos del equipo comparten facturas, pagos y emisor', () async {
    final a = Device('admin', dir);
    final b = Device('miembro', dir);

    // --- Dispositivo A: alta del negocio y emisor con logo.
    await a.auth.setup(apiUrl, 'Mi Empresa', 'Rubén', 'ruben', 'secreto1');
    expect(a.auth.isAdmin, isTrue);
    final logo = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4]);
    await a.issuer.save(Issuer(name: 'Mi Empresa', taxId: '900.123.456-7', currency: r'$', logo: logo));

    // --- A crea una factura sin conexión: borrador sin número.
    final idA = await a.invoices.create(draft('Cliente Uno', 100));
    expect((await a.invoices.get(idA))!.isDraft, isTrue);
    await a.sync.sync();
    expect(a.sync.status, SyncStatus.idle);
    expect((await a.invoices.get(idA))!.number, 'F-0001');

    // --- A da de alta a un miembro del equipo.
    await a.auth.request('POST', '/users',
        body: {'name': 'Ana', 'username': 'ana', 'password': 'secreto2', 'role': 'member'});

    // --- B entra y recibe todo: factura y emisor con su logo.
    await b.auth.login(apiUrl, 'ana', 'secreto2');
    expect(b.auth.isAdmin, isFalse);
    await b.sync.sync();
    final invB = await b.byNumber('F-0001');
    expect(invB.clientName, 'Cliente Uno');
    expect((await b.issuer.get()).logo, logo);

    // --- Conflicto sin conexión: los dos pagan 100 sobre 119 a la vez.
    await a.invoices.addPayment(idA, Payment(amount: 100, date: DateTime(2026, 10, 2)));
    await b.invoices.addPayment(invB.id!, Payment(amount: 100, date: DateTime(2026, 10, 3)));
    await b.sync.sync(); // B llega primero: se acepta.
    expect((await b.byNumber('F-0001')).payments.single.receiptNumber, 'RC-0001');
    await a.sync.sync(); // A llega tarde: se rechaza y ve el pago de B.
    expect(a.sync.takeRejections().single, contains('supera el saldo'));
    final afterA = (await a.invoices.get(idA))!;
    expect(afterA.payments.single.amount, 100);
    expect(afterA.payments.single.receiptNumber, 'RC-0001');
    expect(afterA.balance, 19);

    // --- B paga el resto: la factura queda pagada en los dos.
    await b.invoices.addPayment(invB.id!, Payment(amount: 19, date: DateTime(2026, 10, 5)));
    await b.sync.sync();
    await a.sync.sync();
    expect((await a.invoices.get(idA))!.paid, isTrue);
    expect((await a.invoices.get(idA))!.paidDate, DateTime(2026, 10, 5));

    // --- Un miembro no puede eliminar pagos sincronizados: se restaura.
    final paidB = await b.byNumber('F-0001');
    await b.invoices.deletePayment(paidB.id!, paidB.payments.first.id!);
    expect((await b.byNumber('F-0001')).payments, hasLength(1));
    await b.sync.sync();
    expect(b.sync.takeRejections().single, contains('administrador'));
    expect((await b.byNumber('F-0001')).payments, hasLength(2));

    // --- B crea y edita sin conexión: un solo envío, número siguiente.
    final idB = await b.invoices.create(draft('Cliente Dos', 50));
    final created = (await b.invoices.get(idB))!;
    await b.invoices.update(Invoice(
      id: idB,
      uuid: created.uuid,
      issueDate: created.issueDate,
      clientName: 'Cliente Dos (editado)',
      taxRate: 19,
      items: created.items,
    ));
    await b.sync.sync();
    expect((await b.invoices.get(idB))!.number, 'F-0002');

    // --- A la ve, la elimina; B deja de verla.
    await a.sync.sync();
    final inA = await a.byNumber('F-0002');
    expect(inA.clientName, 'Cliente Dos (editado)');
    await a.invoices.delete(inA.id!);
    await a.sync.sync();
    await b.sync.sync();
    expect(await b.invoices.get(idB), isNull);

    // --- Un miembro no puede cambiar el emisor: se restaura el del servidor.
    await b.issuer.save(Issuer(name: 'Intento', taxId: 'X', currency: r'$', logo: logo));
    await b.sync.sync();
    expect(b.sync.takeRejections().single, contains('administrador'));
    expect((await b.issuer.get()).name, 'Mi Empresa');

    // --- Dispositivo antiguo con facturas previas: se suben con su número.
    final c = Device('antiguo', dir);
    final cdb = await c.dbFor(a.auth.session!.businessId).database;
    final oldId = await cdb.insert('invoices', {
      'uuid': '33333333-3333-4333-8333-333333333333',
      'number': 'F-0050',
      'issue_date': DateTime(2026, 8, 1).toIso8601String(),
      'client_name': 'Cliente antiguo',
      'tax_rate': 0,
      'paid': 0,
      'created_at': DateTime(2026, 8, 1).toIso8601String(),
    });
    await cdb.insert('invoice_items',
        {'invoice_id': oldId, 'description': 'X', 'quantity': 1, 'unit_price': 10, 'position': 0});
    await c.auth.login(apiUrl, 'ruben', 'secreto1');
    expect(await c.invoices.countLocalOnly(), 1);
    await c.invoices.enqueueLocalOnly();
    await c.sync.sync();
    expect((await c.byNumber('F-0050')).clientName, 'Cliente antiguo');
    expect(await c.invoices.countLocalOnly(), 0);

    // --- La siguiente factura nueva continúa después del número subido.
    await a.invoices.create(draft('Cliente Tres', 10));
    await a.sync.sync();
    expect((await a.invoices.list()).map((i) => i.number), contains('F-0051'));

    // --- Anulaciones: el admin anula un pago y luego la factura; B lo ve.
    final toVoid = await a.invoices.create(draft('Cliente a anular', 100));
    await a.sync.sync();
    await a.invoices.addPayment(toVoid, Payment(amount: 50, date: DateTime(2026, 10, 6)));
    await a.invoices.addPayment(toVoid, Payment(amount: 69, date: DateTime(2026, 10, 7)));
    await a.sync.sync();
    final number = (await a.invoices.get(toVoid))!.number!;
    await b.sync.sync();
    final inB = await b.byNumber(number);
    expect(inB.paid, isTrue);

    // Un miembro no puede anular: el servidor lo rechaza y se restaura.
    await b.invoices.voidPayment(inB.id!, inB.payments.last.id!, 'Prueba de miembro');
    await b.sync.sync();
    expect(b.sync.takeRejections().single, contains('administrador'));
    expect((await b.byNumber(number)).payments.every((p) => !p.isVoided), isTrue);

    final payA = (await a.invoices.get(toVoid))!.payments.last;
    await a.invoices.voidPayment(toVoid, payA.id!, 'Cheque devuelto');
    await a.sync.sync();
    await b.sync.sync();
    final afterPayVoid = await b.byNumber(number);
    expect(afterPayVoid.paid, isFalse);
    expect(afterPayVoid.balance, 69);
    expect(afterPayVoid.payments.last.voidReason, 'Cheque devuelto');

    await a.invoices.voidInvoice(toVoid, 'El cliente canceló el pedido');
    await a.sync.sync();
    await b.sync.sync();
    final afterInvoiceVoid = await b.byNumber(number);
    expect(afterInvoiceVoid.isVoided, isTrue);
    expect(afterInvoiceVoid.voidReason, 'El cliente canceló el pedido');
    expect(afterInvoiceVoid.payments.every((p) => p.isVoided), isTrue);
    expect(afterInvoiceVoid.payments.last.voidReason, 'Cheque devuelto', reason: 'el ya anulado conserva su motivo');

    // --- Varios negocios: el superadmin crea otro y cambia entre ellos.
    final mainId = a.auth.session!.businessId;
    final mainInvoices = (await a.invoices.list()).map((i) => i.number).toSet();
    final newBusiness = await a.auth.request('POST', '/businesses', body: {'name': 'Segundo negocio', 'include_me': true});
    final secondId = ((newBusiness['business'] as Map)['id'] as num).toInt();
    await a.auth.switchBusiness(secondId);
    expect(a.auth.session!.businessName, 'Segundo negocio');
    expect(a.auth.session!.businesses.map((x) => x.id), containsAll([mainId, secondId]));
    await a.sync.sync();
    expect(await a.invoices.list(), isEmpty, reason: 'cada negocio tiene su propia base');
    await a.issuer.save(Issuer(name: 'Segundo negocio', taxId: 'NIT 2', currency: r'$'));
    await a.invoices.create(draft('Cliente del segundo', 40));
    await a.sync.sync();
    expect((await a.invoices.list()).single.number, 'F-0001', reason: 'numeración propia del negocio');

    await a.auth.switchBusiness(mainId);
    await a.sync.sync();
    final back = (await a.invoices.list()).map((i) => i.number).toSet();
    expect(back, mainInvoices, reason: 'al volver, el primer negocio sigue intacto');
    expect((await a.issuer.get()).name, 'Mi Empresa');

    // --- Un miembro de un solo negocio no puede entrar en el segundo.
    await b.auth.login(apiUrl, 'ana', 'secreto2');
    expect(b.auth.session!.hasSeveralBusinesses, isFalse);
    await expectLater(b.auth.switchBusiness(secondId), throwsA(anything));

    // --- Cerrar sesión borra los datos de todos los negocios del dispositivo.
    await a.auth.logout();
    expect(await File(join(dir.path, 'admin-b$mainId.db')).exists(), isFalse);
    expect(await File(join(dir.path, 'admin-b$secondId.db')).exists(), isFalse);
  }, skip: apiUrl.isEmpty ? 'Define API_URL para probar contra el servidor' : false);
}
