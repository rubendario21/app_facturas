import '../models/invoice.dart';

const _accents = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
  'ñ': 'n', 'ç': 'c',
};

/// Texto para comparar sin mayúsculas ni tildes ("Café" → "cafe").
String normalizeSearch(String text) {
  final lower = text.toLowerCase().trim();
  final buffer = StringBuffer();
  for (final ch in lower.split('')) {
    buffer.write(_accents[ch] ?? ch);
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ');
}

final _trailingDigits = RegExp(r'(\d{1,9})$');

/// ¿La factura coincide con lo escrito en el buscador?
///
/// Un solo campo para todo:
/// - cliente o identificación fiscal: todas las palabras deben aparecer, en
///   cualquier orden ("dental sonrie" encuentra "Clínica Dental Sonríe");
/// - número: el texto aparece en el número, o la cifra coincide aunque falten
///   los ceros o el guion ("7", "f7", "F-7" y "0007" encuentran F-0007).
bool matchesInvoiceSearch(Invoice invoice, String query) {
  final q = normalizeSearch(query);
  if (q.isEmpty) return true;

  final haystack = normalizeSearch('${invoice.clientName} ${invoice.clientTaxId}');
  if (q.split(' ').every(haystack.contains)) return true;

  final number = invoice.number;
  if (number == null) return false;
  final n = normalizeSearch(number);
  if (n.contains(q)) return true;

  final qDigits = _trailingDigits.firstMatch(q)?.group(1);
  final nDigits = _trailingDigits.firstMatch(n)?.group(1);
  if (qDigits == null || nDigits == null) return false;
  if (int.parse(qDigits) != int.parse(nDigits)) return false;
  // Si se escribió un prefijo ("f", "rc"), debe coincidir con el del número.
  final letters = RegExp(r'[^a-z]');
  final qPrefix = q.substring(0, q.length - qDigits.length).replaceAll(letters, '');
  final nPrefix = n.substring(0, n.length - nDigits.length).replaceAll(letters, '');
  return qPrefix.isEmpty || nPrefix.startsWith(qPrefix);
}
