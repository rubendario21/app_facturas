import 'package:facturas_app/models/invoice.dart';
import 'package:facturas_app/models/issuer.dart';
import 'package:facturas_app/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calcula base, impuesto y total', () {
    final inv = Invoice(
      issueDate: DateTime(2026, 1, 1),
      clientName: 'Cliente',
      taxRate: 21,
      items: const [
        InvoiceItem(description: 'A', quantity: 2, unitPrice: 50),
        InvoiceItem(description: 'B', quantity: 1, unitPrice: 100),
      ],
    );
    expect(inv.subtotal, 200);
    expect(inv.taxAmount, closeTo(42, 1e-9));
    expect(inv.total, closeTo(242, 1e-9));
  });

  test('una factura pagada nunca está vencida', () {
    final inv = Invoice(
      issueDate: DateTime(2020, 1, 1),
      dueDate: DateTime(2020, 2, 1),
      clientName: 'Cliente',
      taxRate: 0,
      paid: true,
    );
    expect(inv.isOverdue, isFalse);
  });

  test('formatea el número de factura con prefijo', () {
    expect(const Issuer(invoicePrefix: 'F-2026-').formatNumber(7), 'F-2026-0007');
  });

  group('abonos', () {
    final inv = Invoice(
      issueDate: DateTime(2026, 1, 1),
      clientName: 'Cliente',
      taxRate: 21,
      items: const [InvoiceItem(description: 'A', quantity: 1, unitPrice: 100)],
      payments: [
        Payment(amount: 50, date: DateTime(2026, 1, 5)),
        Payment(amount: 20.5, date: DateTime(2026, 1, 9)),
      ],
    );

    test('calcula pagado y saldo pendiente', () {
      expect(inv.paidAmount, closeTo(70.5, 1e-9));
      expect(inv.balance, closeTo(50.5, 1e-9));
    });

    test('con abonos queda parcialmente pagada y no editable', () {
      expect(inv.isPartiallyPaid, isTrue);
      expect(inv.isEditable, isFalse);
    });

    test('el saldo no es negativo ni arrastra errores de redondeo', () {
      final exact = Invoice(
        issueDate: DateTime(2026, 1, 1),
        clientName: 'C',
        taxRate: 0,
        items: const [InvoiceItem(description: 'A', quantity: 3, unitPrice: 0.1)],
        payments: [Payment(amount: 0.3, date: DateTime(2026, 1, 2))],
      );
      expect(exact.balance, 0);
    });
  });

  test('el símbolo de moneda va delante del importe', () {
    expect(fmtMoney(1234.5, r'$'), r'$ 1.234,50');
    expect(fmtMoney(0, r'$'), r'$ 0,00');
    expect(const Issuer().currency, r'$');
  });

  group('anulaciones', () {
    final inv = Invoice(
      issueDate: DateTime(2026, 1, 1),
      dueDate: DateTime(2026, 1, 2),
      clientName: 'Cliente',
      taxRate: 0,
      items: const [InvoiceItem(description: 'A', quantity: 1, unitPrice: 100)],
      payments: [
        Payment(amount: 60, date: DateTime(2026, 1, 3)),
        Payment(amount: 40, date: DateTime(2026, 1, 4), voidedAt: DateTime(2026, 1, 5), voidReason: 'Devuelto'),
      ],
    );

    test('un pago anulado no cuenta en lo pagado ni en el saldo', () {
      expect(inv.paidAmount, 60);
      expect(inv.balance, 40);
      expect(inv.activePayments, hasLength(1));
      expect(inv.payments, hasLength(2), reason: 'el historial conserva el anulado');
    });

    test('una factura anulada no está pendiente, ni vencida, ni se edita', () {
      final voided = Invoice(
        issueDate: DateTime(2026, 1, 1),
        dueDate: DateTime(2026, 1, 2),
        clientName: 'C',
        taxRate: 0,
        voidedAt: DateTime(2026, 1, 3),
        voidReason: 'Duplicada',
      );
      expect(voided.isVoided, isTrue);
      expect(voided.isOpen, isFalse);
      expect(voided.isOverdue, isFalse);
      expect(voided.isEditable, isFalse);
    });
  });
}
