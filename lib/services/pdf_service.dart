import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/invoice.dart';
import '../models/issuer.dart';
import '../utils/format.dart';

class PdfService {
  static final _accent = PdfColor.fromHex('#2E3A8C');

  static String fileName(Invoice inv) =>
      'factura_${inv.displayNumber.replaceAll(RegExp(r'[^\w-]'), '_')}.pdf';

  static String receiptFileName(Payment p) =>
      'recibo_${p.receiptNumber ?? "pendiente"}.pdf';

  static Future<pw.ThemeData> _theme() async => pw.ThemeData.withFont(
        base: pw.Font.ttf(
            await rootBundle.load('assets/fonts/IBMPlexSans-Regular.ttf')),
        bold:
            pw.Font.ttf(await rootBundle.load('assets/fonts/IBMPlexSans-SemiBold.ttf')),
      );

  static Future<Uint8List> build(Invoice inv, Issuer issuer) async {
    String money(double v) => fmtMoney(v, issuer.currency);

    final doc = pw.Document(
      theme: await _theme(),
      title: 'Factura ${inv.displayNumber}',
      author: issuer.name,
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ),
        build: (ctx) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: _issuerBlock(issuer)),
              pw.SizedBox(width: 16),
              _headerBlock(inv),
            ],
          ),
          pw.SizedBox(height: 24),
          if (inv.isVoided) ...[
            _voidBanner('Factura anulada el ${fmtDate(inv.voidedAt!)}', inv.voidReason),
            pw.SizedBox(height: 16),
          ],
          _clientBlock(inv),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headers: ['Descripción', 'Cant.', 'Precio', 'Importe'],
            data: [
              for (final it in inv.items)
                [
                  it.description,
                  fmtQty(it.quantity),
                  money(it.unitPrice),
                  money(it.total),
                ],
            ],
            border: null,
            headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: pw.BoxDecoration(color: _accent),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            cellPadding:
                const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            cellStyle: const pw.TextStyle(fontSize: 10),
            columnWidths: const {
              0: pw.FlexColumnWidth(5),
              1: pw.FlexColumnWidth(1.3),
              2: pw.FlexColumnWidth(2),
              3: pw.FlexColumnWidth(2),
            },
            headerAlignments: const {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
            cellAlignments: const {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 12),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.SizedBox(
              width: 220,
              child: pw.Column(children: [
                _totalRow('Base imponible', money(inv.subtotal)),
                _totalRow(
                    'IVA (${fmtQty(inv.taxRate)} %)', money(inv.taxAmount)),
                pw.Divider(color: _accent),
                _totalRow('TOTAL', money(inv.total), big: true),
                if (inv.hasPayments && !inv.isVoided) ...[
                  pw.SizedBox(height: 6),
                  _totalRow('Pagado', money(inv.paidAmount)),
                  _totalRow('Saldo pendiente', money(inv.balance), big: true),
                ],
              ]),
            ),
          ),
          if (issuer.bankAccount.trim().isNotEmpty) ...[
            pw.SizedBox(height: 24),
            pw.Text('Forma de pago',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text('Transferencia bancaria a: ${issuer.bankAccount}'),
          ],
          if (inv.notes.trim().isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text('Observaciones',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text(inv.notes),
          ],
        ],
      ),
    );
    return doc.save();
  }

  /// Recibo de un pago o abono concreto, para entregar al cliente.
  static Future<Uint8List> buildReceipt(
      Invoice inv, Payment payment, Issuer issuer) async {
    String money(double v) => fmtMoney(v, issuer.currency);

    // Pagos anteriores a este (por fecha y orden de registro).
    final index = inv.payments.indexWhere((p) => p.id == payment.id);
    final previousCents = inv.payments
        .take(index < 0 ? 0 : index)
        .where((p) => !p.isVoided)
        .fold<int>(0, (s, p) => s + toCents(p.amount));
    final totalCents = toCents(inv.total);
    final afterCents = previousCents + toCents(payment.amount);
    final balanceAfter =
        totalCents > afterCents ? (totalCents - afterCents) / 100 : 0.0;
    final settles = afterCents >= totalCents;
    final concept = !settles
        ? 'Abono a la factura Nº ${inv.displayNumber}'
        : previousCents == 0
            ? 'Pago total de la factura Nº ${inv.displayNumber}'
            : 'Pago del saldo final de la factura Nº ${inv.displayNumber}';

    final doc = pw.Document(
      theme: await _theme(),
      title: 'Recibo ${payment.receiptNumber ?? "pendiente"}',
      author: issuer.name,
    );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(child: _issuerBlock(issuer)),
                pw.SizedBox(width: 16),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('RECIBO DE PAGO',
                        style: pw.TextStyle(
                            fontSize: 22,
                            fontWeight: pw.FontWeight.bold,
                            color: _accent)),
                    pw.SizedBox(height: 4),
                    pw.Text('Nº ${payment.receiptNumber ?? "pendiente"}',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text('Fecha: ${fmtDate(payment.date)}'),
                    if (payment.isVoided) ...[
                      pw.SizedBox(height: 8),
                      _stamp('ANULADO', _void),
                    ],
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 24),
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#E8EAF6'),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('VALOR RECIBIDO',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, color: _accent)),
                  pw.Text(money(payment.amount),
                      style: pw.TextStyle(
                          fontSize: 20, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            _labeled('Recibimos de', [
              inv.clientName,
              if (inv.clientTaxId.trim().isNotEmpty) inv.clientTaxId,
            ]),
            _labeled('Por concepto de', [concept]),
            _labeled('Forma de pago',
                [payment.method.isEmpty ? '-' : payment.method]),
            if (payment.note.trim().isNotEmpty)
              _labeled('Referencia / nota', [payment.note]),
            pw.SizedBox(height: 16),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.SizedBox(
                width: 260,
                child: pw.Column(children: [
                  _totalRow('Valor total de la factura', money(inv.total)),
                  _totalRow('Pagos anteriores', money(previousCents / 100)),
                  _totalRow('Este pago', money(payment.amount)),
                  pw.Divider(color: _accent),
                  _totalRow('Saldo pendiente', money(balanceAfter), big: true),
                ]),
              ),
            ),
            if (payment.isVoided) ...[
              pw.SizedBox(height: 12),
              _voidBanner('Recibo anulado el ${fmtDate(payment.voidedAt!)}', payment.voidReason),
            ] else if (settles) ...[
              pw.SizedBox(height: 12),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.green700, width: 2),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Text('FACTURA PAGADA',
                      style: pw.TextStyle(
                          color: PdfColors.green700,
                          fontWeight: pw.FontWeight.bold)),
                ),
              ),
            ],
            pw.Spacer(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.SizedBox(
                  width: 220,
                  child: pw.Column(children: [
                    pw.Divider(color: PdfColors.grey700),
                    pw.Text('Recibido por',
                        style: const pw.TextStyle(fontSize: 10)),
                    pw.Text(issuer.name,
                        style: pw.TextStyle(
                            fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  ]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  static pw.Widget _labeled(String label, List<String> lines) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label.toUpperCase(),
                style: pw.TextStyle(
                    fontSize: 9,
                    color: _accent,
                    fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            for (final l in lines) pw.Text(l),
          ],
        ),
      );

  static pw.Widget _issuerBlock(Issuer i) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (i.logo != null) ...[
            pw.ConstrainedBox(
              constraints:
                  const pw.BoxConstraints(maxHeight: 64, maxWidth: 180),
              child: pw.Image(pw.MemoryImage(i.logo!), fit: pw.BoxFit.contain),
            ),
            pw.SizedBox(height: 8),
          ],
          pw.Text(i.name,
              style:
                  pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          for (final line in [
            i.taxId,
            i.address,
            i.city,
            i.phone,
            i.email,
          ])
            if (line.trim().isNotEmpty)
              pw.Text(line, style: const pw.TextStyle(fontSize: 10)),
        ],
      );

  static final _void = PdfColor.fromHex('#C2412D');

  static pw.Widget _stamp(String text, PdfColor color) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: color, width: 2),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Text(text, style: pw.TextStyle(color: color, fontWeight: pw.FontWeight.bold)),
      );

  /// Franja con la fecha y el motivo de la anulación.
  static pw.Widget _voidBanner(String title, String reason) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromHex('#FBEDEA'),
          border: pw.Border.all(color: _void, width: 1.5),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _void)),
            pw.SizedBox(height: 2),
            pw.Text('Motivo: $reason'),
          ],
        ),
      );

  static pw.Widget _headerBlock(Invoice inv) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text('FACTURA',
              style: pw.TextStyle(
                  fontSize: 26,
                  fontWeight: pw.FontWeight.bold,
                  color: _accent)),
          pw.SizedBox(height: 4),
          pw.Text('Nº ${inv.displayNumber}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Text('Fecha: ${fmtDate(inv.issueDate)}'),
          if (inv.dueDate != null)
            pw.Text('Vencimiento: ${fmtDate(inv.dueDate!)}'),
          if (inv.isVoided) ...[
            pw.SizedBox(height: 8),
            _stamp('ANULADA', _void),
          ] else if (inv.paid) ...[
            pw.SizedBox(height: 8),
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.green700, width: 2),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(
                inv.paidDate != null
                    ? 'PAGADA ${fmtDate(inv.paidDate!)}'
                    : 'PAGADA',
                style: pw.TextStyle(
                    color: PdfColors.green700, fontWeight: pw.FontWeight.bold),
              ),
            ),
          ],
        ],
      );

  static pw.Widget _clientBlock(Invoice inv) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(12),
        decoration: const pw.BoxDecoration(color: PdfColors.grey100),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('FACTURAR A',
                style: pw.TextStyle(
                    fontSize: 9,
                    color: _accent,
                    fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(inv.clientName,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            for (final line in [
              inv.clientTaxId,
              inv.clientAddress,
              inv.clientEmail,
            ])
              if (line.trim().isNotEmpty)
                pw.Text(line, style: const pw.TextStyle(fontSize: 10)),
          ],
        ),
      );

  static pw.Widget _totalRow(String label, String value, {bool big = false}) {
    final style = pw.TextStyle(
      fontSize: big ? 13 : 10,
      fontWeight: big ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [pw.Text(label, style: style), pw.Text(value, style: style)],
      ),
    );
  }
}
