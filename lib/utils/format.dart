import 'package:intl/intl.dart';

final _dateFormat = DateFormat('dd/MM/yyyy', 'es');
final _qtyFormat = NumberFormat('#,##0.##', 'es');
final _moneyFormat = NumberFormat('#,##0.00', 'es');

String fmtDate(DateTime d) => _dateFormat.format(d);

/// Símbolo delante del importe: "$ 1.234,50".
String fmtMoney(double value, String symbol) {
  final amount = _moneyFormat.format(value.abs());
  final sign = value < 0 ? '-' : '';
  return symbol.isEmpty ? '$sign$amount' : '$sign$symbol $amount';
}

String fmtQty(double q) => _qtyFormat.format(q);

/// Acepta tanto "12.5" como "12,5".
double? parseNum(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Fecha en formato AAAA-MM-DD (el que usa el servidor).
String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
