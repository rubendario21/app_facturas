import 'dart:convert';

import 'package:facturas_app/models/invoice.dart';
import 'package:facturas_app/models/issuer.dart';
import 'package:facturas_app/services/pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('es'));

  final invoice = Invoice(
    id: 1,
    number: 'F-0001',
    issueDate: DateTime(2026, 10, 1),
    clientName: 'Cliente S.A.S.',
    taxRate: 19,
    items: const [InvoiceItem(description: 'Servicio', quantity: 1, unitPrice: 100)],
    payments: [
      Payment(id: 3, receiptNumber: 'RC-0003', amount: 50, date: DateTime(2026, 10, 2), method: 'Efectivo'),
      Payment(id: 7, receiptNumber: 'RC-0007', amount: 69, date: DateTime(2026, 10, 9), method: 'Transferencia'),
    ],
  );
  const issuer = Issuer(name: 'Mi Empresa', taxId: '900.123.456-7');

  test('genera la factura y los recibos en PDF', () async {
    for (final bytes in [
      await PdfService.build(invoice, issuer),
      await PdfService.buildReceipt(invoice, invoice.payments.first, issuer),
      await PdfService.buildReceipt(invoice, invoice.payments.last, issuer),
    ]) {
      expect(latin1.decode(bytes.sublist(0, 4)), '%PDF');
    }
  });

  test('número y nombre de archivo del recibo', () {
    expect(invoice.payments.last.receiptNumber, 'RC-0007');
    expect(PdfService.receiptFileName(invoice.payments.last), 'recibo_RC-0007.pdf');
  });
}
