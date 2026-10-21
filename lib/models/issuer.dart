import 'dart:typed_data';

/// Datos del emisor de las facturas (tu empresa o actividad).
class Issuer {
  final String name;
  final String taxId;
  final String address;
  final String city;
  final String phone;
  final String email;
  final String bankAccount;
  final String invoicePrefix;
  final int nextNumber;
  final double defaultTaxRate;
  final String currency;

  /// Logo en PNG o JPG; null si no se ha configurado.
  final Uint8List? logo;

  const Issuer({
    this.name = '',
    this.taxId = '',
    this.address = '',
    this.city = '',
    this.phone = '',
    this.email = '',
    this.bankAccount = '',
    this.invoicePrefix = 'F-',
    this.nextNumber = 1,
    this.defaultTaxRate = 21,
    this.currency = r'$',
    this.logo,
  });

  bool get isConfigured => name.trim().isNotEmpty && taxId.trim().isNotEmpty;

  String formatNumber(int n) => '$invoicePrefix${n.toString().padLeft(4, '0')}';

  factory Issuer.fromMap(Map<String, Object?> m) => Issuer(
        name: m['name'] as String? ?? '',
        taxId: m['tax_id'] as String? ?? '',
        address: m['address'] as String? ?? '',
        city: m['city'] as String? ?? '',
        phone: m['phone'] as String? ?? '',
        email: m['email'] as String? ?? '',
        bankAccount: m['bank_account'] as String? ?? '',
        invoicePrefix: m['invoice_prefix'] as String? ?? 'F-',
        nextNumber: m['next_number'] as int? ?? 1,
        defaultTaxRate: (m['default_tax_rate'] as num?)?.toDouble() ?? 21,
        currency: m['currency'] as String? ?? r'$',
        logo: m['logo'] as Uint8List?,
      );

  Map<String, Object?> toMap() => {
        'id': 1,
        'name': name,
        'tax_id': taxId,
        'address': address,
        'city': city,
        'phone': phone,
        'email': email,
        'bank_account': bankAccount,
        'invoice_prefix': invoicePrefix,
        'next_number': nextNumber,
        'default_tax_rate': defaultTaxRate,
        'currency': currency,
        'logo': logo,
      };
}
