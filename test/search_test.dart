import 'package:facturas_app/models/invoice.dart';
import 'package:facturas_app/utils/search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Invoice inv(String client, String? number, {String taxId = ''}) => Invoice(
        number: number,
        issueDate: DateTime(2026, 10, 1),
        clientName: client,
        clientTaxId: taxId,
        taxRate: 0,
      );

  final cafe = inv('Café La Montaña', 'F-0007', taxId: 'NIT 900.555.123');
  final dental = inv('Clínica Dental Sonríe', 'F-0012');
  final draft = inv('Panadería San José', null);

  test('vacío muestra todas', () {
    expect(matchesInvoiceSearch(cafe, ''), isTrue);
    expect(matchesInvoiceSearch(cafe, '   '), isTrue);
  });

  test('por cliente, sin mayúsculas ni tildes', () {
    expect(matchesInvoiceSearch(cafe, 'cafe'), isTrue);
    expect(matchesInvoiceSearch(cafe, 'MONTANA'), isTrue);
    expect(matchesInvoiceSearch(cafe, 'café la montaña'), isTrue);
    expect(matchesInvoiceSearch(dental, 'cafe'), isFalse);
  });

  test('varias palabras en cualquier orden', () {
    expect(matchesInvoiceSearch(dental, 'sonrie dental'), isTrue);
    expect(matchesInvoiceSearch(dental, 'dental hotel'), isFalse);
  });

  test('por identificación fiscal', () {
    expect(matchesInvoiceSearch(cafe, '900.555'), isTrue);
  });

  test('por número, aunque falten ceros, guion o prefijo', () {
    for (final q in ['F-0007', 'f-0007', '0007', '7', 'f7', 'F-7', 'f 7']) {
      expect(matchesInvoiceSearch(cafe, q), isTrue, reason: q);
    }
    expect(matchesInvoiceSearch(cafe, '13'), isFalse);
    expect(matchesInvoiceSearch(dental, '12'), isTrue);
    expect(matchesInvoiceSearch(cafe, 'rc7'), isFalse, reason: 'otro prefijo');
  });

  test('los borradores sin número se encuentran por cliente', () {
    expect(matchesInvoiceSearch(draft, 'panaderia'), isTrue);
    expect(matchesInvoiceSearch(draft, '7'), isFalse);
  });
}
